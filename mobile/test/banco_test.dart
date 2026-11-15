// Banco local (lib/services/banco.dart) e o historico das telas
// (lib/services/historico_local.dart): upsert pela lista da pulseira,
// episodios que saem da lista, consultas por dia/mes/7 dias, paginas da
// lista, retencao, reset, lembretes e a concorrencia de duas conexoes (app e
// servico) no mesmo arquivo, em isolates separados como no celular.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/lembrete.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
import 'package:puzzleband/services/banco.dart';
import 'package:puzzleband/services/historico_local.dart';
import 'package:puzzleband/utils/relogio.dart';

final agora = DateTime(2026, 11, 14, 15, 0);

Episodio ep(
  String id,
  DateTime inicio, {
  Avaliacao avaliacao = Avaliacao.pendente,
  NivelRisco nivel = NivelRisco.atencao,
  double duracao = 60,
  String? encerramento = 'normalizou',
}) =>
    Episodio(
      id: id,
      crianca: 'C01',
      fonte: 'pulseira',
      inicio: inicio,
      fim: inicio.add(Duration(seconds: duracao.round())),
      duracaoS: duracao,
      encerramento: encerramento,
      nivelMaximo: nivel,
      probabilidadeMaxima: 0.8,
      gatilho: const Gatilho(tipo: 'ruido', texto: 'Provável gatilho: ruído'),
      avaliacao: avaliacao,
    );

/// Um arquivo de banco novo numa pasta temporaria (apagada no fim).
Future<File> arquivoNovo() async {
  final pasta = await Directory.systemTemp.createTemp('puzzleband_banco_');
  addTearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } catch (_) {}
  });
  return File('${pasta.path}${Platform.pathSeparator}puzzleband.db');
}

void main() {
  late BancoPuzzleBand banco;

  setUp(() {
    relogio = () => agora;
    banco = BancoPuzzleBand.emMemoria();
  });

  tearDown(() async {
    relogio = DateTime.now;
    await banco.close();
  });

  group('episodios da pulseira', () {
    test('upsert pelo id: a atualizacao substitui, sem duplicar, e todos os campos voltam iguais', () async {
      final original = ep('ep_1', DateTime(2026, 11, 14, 9), encerramento: null);
      await banco.gravarDaPulseira([original], agora);
      final fechado = Episodio(
        id: 'ep_1',
        crianca: 'C01',
        fonte: 'pulseira',
        inicio: original.inicio,
        fim: DateTime(2026, 11, 14, 9, 3),
        duracaoS: 180,
        encerramento: 'normalizou',
        nivelMaximo: NivelRisco.altoRisco,
        probabilidadeMaxima: 0.91,
        gatilho: const Gatilho(tipo: 'luz', texto: 'Provável gatilho: luz'),
        avaliacao: Avaliacao.confirmado,
        observacao: 'sol forte',
        avaliacaoOrigem: 'site',
        avaliacaoEm: DateTime.utc(2026, 11, 14, 12, 5, 0, 123, 456),
        vistoEm: DateTime(2026, 11, 14, 9, 1),
      );
      await banco.gravarDaPulseira([fechado], agora.add(const Duration(minutes: 1)));
      final lido = (await banco.recentes(10)).single;
      expect(lido.toJson(), fechado.toJson());
      expect(lido.avaliacaoEm!.microsecond, 456, reason: 'microssegundos preservados');
      expect(lido.naPulseira, isTrue);
    });

    test('quem sai da lista continua no banco (fora da pulseira); a lista vazia nao apaga nada', () async {
      await banco.gravarDaPulseira([ep('a', DateTime(2026, 11, 1)), ep('b', DateTime(2026, 11, 2))], agora);
      await banco.gravarDaPulseira([ep('b', DateTime(2026, 11, 2)), ep('c', DateTime(2026, 11, 3))], agora);
      expect({for (final e in await banco.recentes(10)) e.id: e.naPulseira}, {'c': true, 'b': true, 'a': false});
      await banco.gravarDaPulseira(const [], agora);
      final todos = await banco.recentes(10);
      expect(todos.length, 3);
      expect(todos.every((e) => !e.naPulseira), isTrue);
    });

    test('acumula alem dos 50 da pulseira', () async {
      // a pulseira publica sempre os 50 mais recentes; 120 episodios ao longo do tempo
      final todos = [for (var i = 0; i < 120; i++) ep('ep_$i', DateTime(2026, 9, 1).add(Duration(hours: i * 12)))];
      for (var fim = 50; fim <= 120; fim += 10) {
        await banco.gravarDaPulseira(todos.sublist(fim - 50, fim).reversed.toList(), agora);
      }
      expect((await banco.resumo()).total, 120);
    });

    test('consultas por faixa: dia, mes e 7 dias (inicio no limite do dia entra no dia certo)', () async {
      await banco.gravarDaPulseira([
        ep('meia_noite', DateTime(2026, 11, 14)),
        ep('fim_do_dia', DateTime(2026, 11, 13, 23, 59, 59)),
        ep('outubro', DateTime(2026, 10, 31, 22)),
        ep('semana_passada', DateTime(2026, 11, 7, 12)),
      ], agora);
      final hoje = await banco.episodiosEntre(DateTime(2026, 11, 14), DateTime(2026, 11, 15));
      expect([for (final e in hoje) e.id], ['meia_noite']);
      final novembro = await banco.episodiosEntre(DateTime(2026, 11), DateTime(2026, 12));
      expect([for (final e in novembro) e.id], ['meia_noite', 'fim_do_dia', 'semana_passada']);
      final seteDias = await banco.episodiosEntre(DateTime(2026, 11, 8), DateTime(2026, 11, 15));
      expect([for (final e in seteDias) e.id], ['meia_noite', 'fim_do_dia']);
      final r = await banco.resumo();
      expect(r.primeiro, DateTime(2026, 10, 31, 22));
    });

    test('o indice de inicio existe e e usado nas consultas por faixa', () async {
      final plano = await banco
          .customSelect('EXPLAIN QUERY PLAN SELECT * FROM episodios WHERE inicio >= 0 AND inicio < 10 ORDER BY inicio DESC')
          .get();
      expect(plano.map((l) => l.data['detail']).join(' '), contains('idx_episodios_inicio'));
    });

    test('CHECK do esquema: nivel e avaliacao invalidos sao recusados pelo banco', () async {
      await expectLater(
        banco.customStatement(
          "INSERT INTO episodios (id, inicio, nivel_maximo, recebido_em) VALUES ('x', 0, 'qualquer', 0)",
        ),
        throwsA(anything),
      );
    });
  });

  group('avaliacao local (pendente de confirmacao)', () {
    test('vale ate a pulseira devolver o mesmo avaliacao_em ou um mais novo; lista antiga nao desfaz', () async {
      final inicio = DateTime(2026, 11, 14, 9);
      await banco.gravarDaPulseira([ep('ep_1', inicio)], agora);
      final enviadoEm = DateTime.utc(2026, 11, 14, 12, 0, 0, 0, 789);
      await banco.avaliarLocal('ep_1', Avaliacao.descartado, 'exercício', enviadoEm);
      expect((await banco.episodio('ep_1'))!.avaliacao, Avaliacao.descartado);

      await banco.gravarDaPulseira([ep('ep_1', inicio)], agora); // retida antiga
      expect((await banco.episodio('ep_1'))!.avaliacao, Avaliacao.descartado);
      expect((await banco.episodio('ep_1'))!.observacao, 'exercício');

      // um microssegundo antes nao confirma (comparacao exata, nao arredondada)
      final quase = Episodio.fromJson({
        ...ep('ep_1', inicio, avaliacao: Avaliacao.confirmado).toJson(),
        'avaliacao_em': enviadoEm.subtract(const Duration(microseconds: 1)).toIso8601String(),
      })!;
      await banco.gravarDaPulseira([quase], agora);
      expect((await banco.episodio('ep_1'))!.avaliacao, Avaliacao.descartado);

      final aplicado = Episodio.fromJson({
        ...ep('ep_1', inicio, avaliacao: Avaliacao.descartado).toJson(),
        'observacao': 'exercício',
        'avaliacao_origem': 'app',
        'avaliacao_em': enviadoEm.toIso8601String(),
      })!;
      await banco.gravarDaPulseira([aplicado], agora);
      final linha = await banco.select(banco.episodios).getSingle();
      expect(linha.avaliacaoLocal, isNull);
      expect(linha.avaliacao, 'descartado');
    });
  });

  group('retencao (1 ano / 5.000 episodios)', () {
    test('sai o que tem mais de 1 ano, com o lembrete do episodio; o resto fica', () async {
      await banco.gravarDaPulseira([ep('novo', DateTime(2026, 6, 1))], agora);
      // gravado ha mais de um ano (a pulseira nao manda mais episodios tao velhos)
      await banco.gravarDaPulseira([ep('velho', DateTime(2025, 11, 1))], DateTime(2025, 11, 2));
      await banco.gravarLembrete('episodio:velho', Lembrete(texto: 'x', salvoEm: DateTime(2025, 11, 1)));
      await banco.gravarLembrete('episodio:novo', Lembrete(texto: 'y', salvoEm: DateTime(2026, 6, 1)));
      expect(await banco.aplicarRetencao(agora), 1);
      expect([for (final e in await banco.recentes(10)) e.id], ['novo']);
      expect((await banco.lembretesSalvos()).keys, ['episodio:novo']);
    });

    test('episodio da pulseira mais velho que 1 ano nem entra', () async {
      await banco.gravarDaPulseira([ep('velho', DateTime(2025, 11, 1)), ep('novo', DateTime(2026, 11, 1))], agora);
      expect([for (final e in await banco.recentes(10)) e.id], ['novo']);
    });

    test('no maximo 5.000: os mais antigos saem', () async {
      final inicio = DateTime(2026, 1, 1);
      await banco.transaction(() async {
        for (var i = 0; i < BancoPuzzleBand.maxEpisodios + 3; i++) {
          await banco.importarEpisodio(ep('ep_$i', inicio.add(Duration(minutes: i))), agora);
        }
      });
      expect(await banco.aplicarRetencao(agora), 3);
      final r = await banco.resumo();
      expect(r.total, BancoPuzzleBand.maxEpisodios);
      expect(r.primeiro, inicio.add(const Duration(minutes: 3)));
    });
  });

  group('reset', () {
    test('apagarHistorico limpa episodios e notificados; apagarTodosOsLembretes, os lembretes', () async {
      await banco.gravarDaPulseira([ep('a', DateTime(2026, 11, 1))], agora);
      await banco.registrarNotificacao('a', NivelRisco.atencao, ignoraNaoPerturbe: false, agora: agora);
      await banco.gravarLembrete('dia:2026-11-01', Lembrete(texto: 'x', salvoEm: agora));
      await banco.apagarHistorico();
      expect(await banco.recentes(10), isEmpty);
      expect(await banco.notificados(), isEmpty);
      expect(await banco.lembretesSalvos(), isNotEmpty, reason: 'os lembretes saem pelas PreferenciasLocais');
      await banco.apagarTodosOsLembretes();
      expect(await banco.lembretesSalvos(), isEmpty);
    });

    test('no arquivo: secure_delete e WAL ligados', () async {
      final b = BancoPuzzleBand.noArquivo(await arquivoNovo(), emSegundoPlano: false);
      addTearDown(b.close);
      final modo = await b.customSelect('PRAGMA journal_mode').getSingle();
      expect(modo.data.values.single, 'wal');
      final seguro = await b.customSelect('PRAGMA secure_delete').getSingle();
      expect(seguro.data.values.single, 1);
      final espera = await b.customSelect('PRAGMA busy_timeout').getSingle();
      expect(espera.data.values.single, 5000);
    });
  });

  group('lembretes', () {
    test('gravar substitui pela chave; texto acima de 120 e cortado; importar nao sobrescreve', () async {
      await banco.gravarLembrete('dia:2026-11-14', Lembrete(texto: 'a' * 150, salvoEm: agora, avisarEm: agora));
      expect((await banco.lembretesSalvos())['dia:2026-11-14']!.texto.length, 120);
      await banco.gravarLembrete('dia:2026-11-14', Lembrete(texto: 'novo', salvoEm: agora));
      await banco.importarLembrete('dia:2026-11-14', Lembrete(texto: 'antigo', salvoEm: agora));
      final l = (await banco.lembretesSalvos())['dia:2026-11-14']!;
      expect(l.texto, 'novo');
      expect(l.avisarEm, isNull);
    });
  });

  group('HistoricoLocal (o que as telas leem)', () {
    test('dia, mes, 7 dias, ultimo e porId vem do banco', () async {
      final h = HistoricoLocal(banco);
      addTearDown(h.dispose);
      await h.receberDaPulseira([
        ep('hoje', DateTime(2026, 11, 14, 9), avaliacao: Avaliacao.confirmado),
        ep('ontem', DateTime(2026, 11, 13, 9)),
        ep('outubro', DateTime(2026, 10, 20, 9), avaliacao: Avaliacao.confirmado),
      ], agora);
      expect([for (final e in h.doDia(agora)) e.id], ['hoje']);
      expect(h.ultimo!.id, 'hoje');
      expect(h.contagensDoMes(agora)[DateTime(2026, 11, 14)]!.confirmadas, 1);
      expect(h.seteDias(agora).last.contagem.confirmadas, 1);
      expect(h.seteDias(agora)[5].contagem.pendentes, 1);
      expect(h.primeiroInicio, DateTime(2026, 10, 20, 9));
      expect(h.recebidoEm, agora);

      // mes que ainda nao estava na memoria: carrega e avisa
      var avisos = 0;
      h.addListener(() => avisos++);
      expect(h.contagensDoMes(DateTime(2026, 10)), isEmpty);
      await h.ocioso;
      expect(avisos, greaterThan(0));
      expect(contagemNoMes(h.contagensDoMes(DateTime(2026, 10)), 2026, 10).confirmadas, 1);
      expect(h.porId('outubro')!.id, 'outubro');
    });

    test('lista em paginas de 50, sem cortar um dia ao meio', () async {
      final h = HistoricoLocal(banco);
      addTearDown(h.dispose);
      // 120 episodios, 4 por dia (do 14/11 para tras)
      await h.receberDaPulseira([
        for (var i = 0; i < 120; i++) ep('ep_$i', DateTime(2026, 11, 14 - i ~/ 4, 20 - i % 4)),
      ], agora);
      expect(h.total, 120);
      expect(h.recentes.length, 52, reason: '50 + o resto do dia do 50.o');
      expect(h.temMais, isTrue);
      final porDia = episodiosPorDia(h.recentes);
      expect(porDia.last.$2.length, 4, reason: 'o ultimo dia veio inteiro');
      h.carregarMais();
      await h.ocioso;
      expect(h.recentes.length, 100);
      h.carregarMais();
      await h.ocioso;
      expect(h.recentes.length, 120);
      expect(h.temMais, isFalse);
    });

    test('avaliar mostra na hora e grava; apagar limpa a tela e o banco', () async {
      final h = HistoricoLocal(banco);
      addTearDown(h.dispose);
      await h.receberDaPulseira([ep('a', DateTime(2026, 11, 14, 9))], agora);
      final futuro = h.avaliar(h.ultimo!, Avaliacao.confirmado, 'ok', agora);
      expect(h.ultimo!.avaliacao, Avaliacao.confirmado, reason: 'antes de gravar');
      expect(h.doDia(agora).single.avaliacao, Avaliacao.confirmado);
      await futuro;
      expect((await banco.episodio('a'))!.avaliacao, Avaliacao.confirmado);

      final apagando = h.apagar();
      expect(h.vazio, isTrue);
      expect(h.doDia(agora), isEmpty);
      await apagando;
      expect((await banco.resumo()).total, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Concorrencia: app e servico, cada um no seu isolate, no mesmo arquivo
  // -------------------------------------------------------------------------

  group('concorrencia app x servico (isolates separados, mesmo arquivo, WAL)', () {
    test('abrem o arquivo novo ao mesmo tempo: as duas criacoes do esquema funcionam', () async {
      final arquivo = await arquivoNovo();
      final app = BancoPuzzleBand.noArquivo(arquivo);
      final servico = BancoPuzzleBand.noArquivo(arquivo);
      addTearDown(() async {
        await app.close();
        await servico.close();
      });
      await Future.wait([app.resumo(), servico.resumo()]);
      expect((await app.resumo()).total, 0);
    });

    test('gravando ao mesmo tempo: nada se perde, nada duplica, o arquivo continua integro', () async {
      final arquivo = await arquivoNovo();
      final app = BancoPuzzleBand.noArquivo(arquivo);
      final servico = BancoPuzzleBand.noArquivo(arquivo);
      addTearDown(() async {
        await app.close();
        await servico.close();
      });
      final listas = [
        for (var i = 0; i < 30; i++) [for (var j = i; j < i + 50; j++) ep('ep_$j', DateTime(2026, 9, 1).add(Duration(hours: j)))],
      ];
      // as duas conexoes recebem as mesmas listas (as duas assinam o historico)
      // e o servico ainda registra notificacoes no meio
      await Future.wait([
        for (final l in listas) app.gravarDaPulseira(l, agora),
        for (final l in listas) servico.gravarDaPulseira(l, agora),
        for (var i = 0; i < 30; i++)
          servico.registrarNotificacao('ep_$i', NivelRisco.atencao, ignoraNaoPerturbe: false, agora: agora),
        for (var i = 0; i < 30; i++) app.avaliarLocal('ep_$i', Avaliacao.confirmado, '', agora),
      ]);
      expect((await app.resumo()).total, 79);
      expect((await servico.resumo()).total, 79);
      expect((await servico.notificados()).length, 30);
      expect((await app.recentes(100)).where((e) => e.avaliacao == Avaliacao.confirmado).length, 30);
      final integro = await app.customSelect('PRAGMA integrity_check').getSingle();
      expect(integro.data.values.single, 'ok');
    });

    test('o mesmo alerta decidido pelos dois ao mesmo tempo: so um registra (notifica)', () async {
      final arquivo = await arquivoNovo();
      final app = BancoPuzzleBand.noArquivo(arquivo);
      final servico = BancoPuzzleBand.noArquivo(arquivo);
      addTearDown(() async {
        await app.close();
        await servico.close();
      });
      for (var i = 0; i < 40; i++) {
        final nivel = i.isEven ? NivelRisco.atencao : NivelRisco.altoRisco;
        final r = await Future.wait([
          app.registrarNotificacao('ep_${i ~/ 2}', nivel, ignoraNaoPerturbe: false, agora: agora),
          servico.registrarNotificacao('ep_${i ~/ 2}', nivel, ignoraNaoPerturbe: true, agora: agora),
        ]);
        expect(r.whereType<Notificacao>().length, 1, reason: 'ep_${i ~/ 2} ${nivel.codigo}');
        if (nivel == NivelRisco.altoRisco) expect(r.whereType<Notificacao>().single.subida, isTrue);
      }
    });
  });
}
