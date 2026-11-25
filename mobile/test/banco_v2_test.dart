// Banco v2 (relatorio em Excel): metricas dos episodios chegando pelo
// historico, resumo de cada minuto (resumo_minuto) gravado so por quem
// notifica (app ou servico, sem duplicar), retencao configuravel ("Guardar
// historico por") e o reset limpando as tabelas novas (flutter test).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/metricas.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/banco.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _semRede = AppConfig(host: 'broker.invalido', port: 8883, user: 'app', pass: '', childId: 'C01');
const _historico = 'puzzleband/C01/historico';
const _resumo = 'puzzleband/C01/resumo_minuto';

class _Notificacoes extends NotificationService {
  @override
  Future<void> mostrarAlerta({
    required int id,
    required String titulo,
    required String texto,
    required bool comSom,
    required bool atualizacao,
    String? payload,
    bool ignoraNaoPerturbe = false,
  }) async {}
}

class _Mqtt extends MqttService {
  _Mqtt({required super.prefs, required super.banco, super.papel})
      : super(config: _semRede, notificacoes: _Notificacoes());

  @override
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) => false;
}

Future<File> _arquivoNovo() async {
  final pasta = await Directory.systemTemp.createTemp('puzzleband_v2_');
  addTearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } catch (_) {}
  });
  return File('${pasta.path}${Platform.pathSeparator}puzzleband.db');
}

Map<String, dynamic> _janela(int n, double bpm, {bool minMax = false}) => {
      'n_leituras': n,
      for (final (i, s) in Sinal.values.indexed)
        s.codigo: {
          'media': bpm + i,
          'n': n,
          if (minMax) 'min': bpm + i - 10,
          if (minMax) 'max': bpm + i + 10,
        },
    };

Map<String, dynamic> metricasJson({double antes = 80, double durante = 120, double recuperacao = 90, int nRec = 30}) => {
      'antes': _janela(120, antes),
      'durante': _janela(95, durante, minMax: true),
      'recuperacao': _janela(nRec, recuperacao),
    };

Map<String, dynamic> episodioJson(String id, DateTime inicio, {Map<String, dynamic>? metricas, String? encerramento = 'normalizou'}) => {
      'id': id,
      'crianca': 'C01',
      'fonte': 'pulseira',
      'inicio': inicio.toUtc().toIso8601String(),
      'fim': inicio.add(const Duration(seconds: 125)).toUtc().toIso8601String(),
      'duracao_s': 95,
      'encerramento': encerramento,
      'nivel_maximo': 'alto_risco',
      'probabilidade_maxima': 0.87,
      'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
      'avaliacao_cuidador': 'pendente',
      'observacao': '',
      'avaliacao_origem': null,
      'avaliacao_em': null,
      'visto_pelo_cuidador_em': null,
      if (metricas != null) 'metricas': metricas,
    };

String historico(List<Map<String, dynamic>> episodios) =>
    jsonEncode({'origem': 'pulseira', 'timestamp': DateTime.now().toUtc().toIso8601String(), 'crianca': 'C01', 'total': episodios.length, 'episodios': episodios});

Map<String, dynamic> minutoJson(DateTime minuto, {double bpm = 90, int n = 60, String nivel = 'baixo_risco'}) => {
      'minuto': minuto.toUtc().toIso8601String(),
      'nivel_maximo': nivel,
      'n_leituras': n,
      for (final (i, s) in Sinal.values.indexed) s.codigo: {'media': bpm + i, 'n': n},
    };

String resumo(List<Map<String, dynamic>> minutos, {String origem = 'pulseira', String motivo = 'minuto'}) =>
    jsonEncode({'origem': origem, 'timestamp': DateTime.now().toUtc().toIso8601String(), 'crianca': 'C01', 'motivo': motivo, 'minutos': minutos});

Future<void> receber(MqttService s, String topico, String texto) async {
  s.tratarMensagem(topico, texto);
  await s.gravacoesPendentes;
}

final _sempre = (DateTime.utc(2000), DateTime.utc(2100));

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('metricas dos episodios chegando no banco', () {
    test('episodio com metricas: 18 linhas (6 sinais x 3 fases) com media, minimo, maximo e n', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final s = _Mqtt(prefs: prefs, banco: banco);
      addTearDown(s.dispose);
      final inicio = DateTime.now().subtract(const Duration(hours: 1));
      await receber(s, _historico, historico([episodioJson('ep_1', inicio, metricas: metricasJson())]));

      final linhas = await banco.select(banco.episodioMetricas).get();
      expect(linhas, hasLength(18));
      final m = (await banco.metricasDe(['ep_1']))['ep_1']!;
      expect(m[Fase.antes]!.nLeituras, 120);
      expect(m[Fase.antes]!.sinais[Sinal.bpm]!.media, 80);
      expect(m[Fase.durante]!.sinais[Sinal.ruido]!.media, 125);
      expect(m[Fase.durante]!.sinais[Sinal.bpm]!.minimo, 110);
      expect(m[Fase.durante]!.sinais[Sinal.bpm]!.maximo, 130);
      expect(m[Fase.durante]!.nLeituras, 95);
      expect(m[Fase.recuperacao]!.sinais[Sinal.luz]!.media, 94);
      expect(m[Fase.antes]!.sinais[Sinal.bpm]!.minimo, isNull, reason: 'min/max so no durante');
    });

    test('episodio em andamento chega de novo: as metricas sao trocadas, nao somadas', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final s = _Mqtt(prefs: prefs, banco: banco);
      addTearDown(s.dispose);
      final inicio = DateTime.now().subtract(const Duration(minutes: 5));
      await receber(s, _historico, historico([episodioJson('ep_1', inicio, metricas: metricasJson(nRec: 4), encerramento: null)]));
      await receber(s, _historico, historico([episodioJson('ep_1', inicio, metricas: metricasJson(recuperacao: 70))]));
      expect(await banco.select(banco.episodioMetricas).get(), hasLength(18));
      final m = (await banco.metricasDe(['ep_1']))['ep_1']!;
      expect(m[Fase.recuperacao]!.nLeituras, 30);
      expect(m[Fase.recuperacao]!.sinais[Sinal.bpm]!.media, 70);
    });

    test('episodio antigo sem metricas continua valido; sem o campo, as metricas que ja estao no banco ficam', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final s = _Mqtt(prefs: prefs, banco: banco);
      addTearDown(s.dispose);
      final inicio = DateTime.now().subtract(const Duration(hours: 2));
      await receber(s, _historico, historico([
        episodioJson('ep_novo', inicio, metricas: metricasJson()),
        episodioJson('ep_antigo', inicio.subtract(const Duration(hours: 1))),
      ]));
      expect([for (final e in s.historicoLocal.recentes) e.id], ['ep_novo', 'ep_antigo']);
      expect((await banco.metricasDe(['ep_novo', 'ep_antigo'])).keys, ['ep_novo']);

      // uma pulseira antiga republica sem o campo: nada some
      await receber(s, _historico, historico([episodioJson('ep_novo', inicio)]));
      expect((await banco.metricasDe(['ep_novo'])).keys, ['ep_novo']);
    });

    test('sinal sem leitura na janela: linha com media nula e n 0 (fica fora do relatorio)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final metricas = metricasJson();
      (metricas['antes'] as Map<String, dynamic>)['hrv_ms'] = null;
      final ep = Episodio.fromJson(episodioJson('ep_1', DateTime.now(), metricas: metricas))!;
      await banco.gravarDaPulseira([ep], DateTime.now());
      final m = (await banco.metricasDe(['ep_1']))['ep_1']!;
      expect(m[Fase.antes]!.sinais.containsKey(Sinal.vfc), isFalse);
      expect(m[Fase.antes]!.nLeituras, 120);
    });
  });

  group('resumo de cada minuto (resumo_minuto)', () {
    test('o app sem o servico grava; o valor reenviado pela pulseira substitui (nao soma)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final s = _Mqtt(prefs: prefs, banco: banco);
      addTearDown(s.dispose);
      expect(s.gravaResumos, isTrue);
      final m0 = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
      final minuto = DateTime.utc(m0.year, m0.month, m0.day, m0.hour, m0.minute);
      await receber(s, _resumo, resumo([minutoJson(minuto, n: 30, bpm: 80)]));
      await receber(s, _resumo, resumo([minutoJson(minuto, n: 60, bpm: 95, nivel: 'atencao')], motivo: 'reenvio'));
      await receber(s, _resumo, resumo([minutoJson(minuto, n: 60, bpm: 95, nivel: 'atencao')], motivo: 'reenvio'));
      final lidos = await banco.resumosEntre(_sempre.$1, _sempre.$2);
      expect(lidos, hasLength(1));
      expect(lidos.single.nLeituras, 60);
      expect(lidos.single.sinais[Sinal.bpm], (media: 95.0, n: 60));
      expect(lidos.single.nivelMaximo, NivelRisco.atencao);
      expect(lidos.single.minuto, minuto);
    });

    test('mensagem de outra origem ou malformada nao grava nada', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final s = _Mqtt(prefs: prefs, banco: banco);
      addTearDown(s.dispose);
      final minuto = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
      await receber(s, _resumo, resumo([minutoJson(minuto)], origem: 'site'));
      await receber(s, _resumo, '{"origem": "pulseira", "minutos": 3}');
      await receber(s, _resumo, 'nao e json');
      await receber(s, _resumo, resumo([{'minuto': 'ontem'}]));
      expect(await banco.resumosEntre(_sempre.$1, _sempre.$2), isEmpty);
    });

    test('com o servico rodando, so o servico grava; o app (mesma mensagem, mesmo arquivo) nao', () async {
      final arquivo = await _arquivoNovo();
      final bancoApp = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
      final bancoServico = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
      addTearDown(() async {
        await bancoApp.close();
        await bancoServico.close();
      });
      final app = _Mqtt(prefs: prefs, banco: bancoApp);
      final servico = _Mqtt(prefs: prefs, banco: bancoServico, papel: PapelDaConexao.servico);
      addTearDown(app.dispose);
      addTearDown(servico.dispose);
      app.definirServicoRodando(true);
      expect(app.gravaResumos, isFalse);
      expect(servico.gravaResumos, isTrue);

      final agora = DateTime.now().toUtc();
      final base = DateTime.utc(agora.year, agora.month, agora.day, agora.hour, agora.minute).subtract(const Duration(minutes: 5));
      final texto = resumo([minutoJson(base), minutoJson(base.add(const Duration(minutes: 1)))]);
      await Future.wait([receber(app, _resumo, texto), receber(servico, _resumo, texto)]);
      final lidos = await bancoApp.resumosEntre(_sempre.$1, _sempre.$2);
      expect(lidos, hasLength(2));
      expect(lidos.every((m) => m.nLeituras == 60), isTrue);

      // o servico parou: o app passa a gravar (na mesma hora, sem lacuna)
      app.definirServicoRodando(false);
      expect(app.gravaResumos, isTrue);
      await receber(app, _resumo, resumo([minutoJson(base.add(const Duration(minutes: 2)))]));
      expect(await bancoServico.resumosEntre(_sempre.$1, _sempre.$2), hasLength(3));
    });

    test('mesmo se os dois gravassem a mesma mensagem, o minuto nao duplica nem soma (upsert)', () async {
      final arquivo = await _arquivoNovo();
      final a = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
      final b = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      final agora = DateTime.now();
      final minuto = DateTime.utc(2026, 11, 25, 10, 0);
      final lista = parseResumoMinuto(resumo([minutoJson(minuto)]))!;
      // em sequencia: as duas conexoes estao na mesma thread aqui (no celular
      // cada uma tem o seu isolate; a concorrencia real esta em banco_test.dart)
      await a.gravarResumos(lista, agora);
      await b.gravarResumos(lista, agora);
      final lidos = await a.resumosEntre(_sempre.$1, _sempre.$2);
      expect(lidos, hasLength(1));
      expect(lidos.single.nLeituras, 60);
    });
  });

  group('retencao ("Guardar historico por") e 90 dias do resumo', () {
    final agora = DateTime(2026, 11, 25, 12);

    Episodio ep(String id, DateTime inicio) =>
        Episodio(id: id, inicio: inicio, nivelMaximo: NivelRisco.atencao, encerramento: 'normalizou');

    test('1 ano (padrao): sai o de 13 meses; 2 anos: fica; ate eu apagar: fica o de 3 anos', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      Future<void> gravar() => banco.transaction(() async {
            for (final e in [
              ep('3_anos', DateTime(2023, 11, 1)),
              ep('13_meses', DateTime(2025, 10, 20)),
              ep('ontem', DateTime(2026, 11, 24)),
            ]) {
              await banco.importarEpisodio(e, agora);
            }
          });
      Future<List<String>> ids() async => [for (final e in await banco.recentes(10)) e.id];

      await gravar();
      expect(await banco.aplicarRetencao(agora, guardar: GuardarHistorico.ateEuApagar), 0);
      expect(await ids(), ['ontem', '13_meses', '3_anos']);
      expect(await banco.aplicarRetencao(agora, guardar: GuardarHistorico.doisAnos), 1);
      expect(await ids(), ['ontem', '13_meses']);
      expect(await banco.aplicarRetencao(agora), 1, reason: 'padrao = 1 ano');
      expect(await ids(), ['ontem']);
    });

    test('a pulseira manda um episodio antigo: entra so se a opcao guarda ate la', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final velho = ep('velho', DateTime(2025, 6, 1));
      await banco.gravarDaPulseira([velho], agora);
      expect(await banco.recentes(10), isEmpty);
      await banco.gravarDaPulseira([velho], agora, guardar: GuardarHistorico.doisAnos);
      expect(await banco.recentes(10), hasLength(1));
    });

    test('limite de quantidade: 10.000 com 2 anos, nenhum com "ate eu apagar"', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final inicio = DateTime(2026, 1, 1);
      await banco.transaction(() async {
        for (var i = 0; i < 10002; i++) {
          await banco.importarEpisodio(ep('ep_$i', inicio.add(Duration(minutes: i))), agora);
        }
      });
      expect(await banco.aplicarRetencao(agora, guardar: GuardarHistorico.ateEuApagar), 0);
      expect(await banco.aplicarRetencao(agora, guardar: GuardarHistorico.doisAnos), 2);
      expect((await banco.resumo()).total, 10000);
      expect(await banco.aplicarRetencao(agora), 5000);
    });

    test('a retencao leva as metricas e os lembretes do episodio; resumo de minuto com mais de 90 dias sai', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final velho = Episodio.fromJson(episodioJson('velho', DateTime(2025, 10, 1), metricas: metricasJson()))!;
      final novo = Episodio.fromJson(episodioJson('novo', DateTime(2026, 11, 1), metricas: metricasJson()))!;
      await banco.gravarDaPulseira([velho, novo], agora, guardar: GuardarHistorico.ateEuApagar);
      await banco.gravarResumos([
        ResumoDoMinuto.fromJson(minutoJson(DateTime.utc(2026, 8, 26, 11)))!, // 91 dias
        ResumoDoMinuto.fromJson(minutoJson(DateTime.utc(2026, 8, 28, 11)))!, // 89 dias
      ], DateTime(2026, 9, 1));
      await banco.aplicarRetencao(agora);
      expect((await banco.metricasDe(['velho', 'novo'])).keys, ['novo']);
      final minutos = await banco.resumosEntre(_sempre.$1, _sempre.$2);
      expect([for (final m in minutos) m.minuto], [DateTime.utc(2026, 8, 28, 11)]);
    });

    test('o servico le a opcao do disco (as telas podem ter mudado)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final servico = _Mqtt(prefs: prefs, banco: banco, papel: PapelDaConexao.servico);
      addTearDown(servico.dispose);
      final velho = episodioJson('velho', DateTime.now().subtract(const Duration(days: 500)));
      await receber(servico, _historico, historico([velho]));
      expect(await banco.recentes(10), isEmpty);
      await prefs.setString(GuardarHistorico.chave, GuardarHistorico.doisAnos.codigo);
      await receber(servico, _historico, historico([velho]));
      expect(await banco.recentes(10), hasLength(1));
    });
  });

  test('reset ("Apagar os dados" e a ordem da pulseira) limpa metricas e resumo de cada minuto', () async {
    final banco = BancoPuzzleBand.emMemoria();
    addTearDown(banco.close);
    final s = _Mqtt(prefs: prefs, banco: banco);
    addTearDown(s.dispose);
    final agora = DateTime.now();
    await receber(s, _historico, historico([episodioJson('ep_1', agora.subtract(const Duration(hours: 1)), metricas: metricasJson())]));
    await receber(s, _resumo, resumo([minutoJson(agora.toUtc().subtract(const Duration(minutes: 2)))]));
    expect(await banco.select(banco.episodioMetricas).get(), isNotEmpty);
    expect(await banco.resumosEntre(_sempre.$1, _sempre.$2), isNotEmpty);

    await s.apagarDadosLocais(manterPreferencias: true);
    expect(await banco.select(banco.episodioMetricas).get(), isEmpty);
    expect(await banco.resumosEntre(_sempre.$1, _sempre.$2), isEmpty);
    expect(await banco.recentes(10), isEmpty);

    // a ordem do terminal (npm run resetar) passa pelo mesmo caminho
    await receber(s, _resumo, resumo([minutoJson(agora.toUtc().subtract(const Duration(minutes: 1)))]));
    s.tratarMensagem('puzzleband/C01/comando', jsonEncode({'acao': 'resetar', 'id': 'r1'}));
    await s.resetEmAndamento;
    expect(await banco.resumosEntre(_sempre.$1, _sempre.$2), isEmpty);
  });
}
