// Regras do MqttService sem rede: notificacao (uma por episodio), mensagem
// malformada, historico guardado no banco local (acumula, ve offline,
// avaliacao pendente de confirmacao) e a ordem de reset (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/config/app_config.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
import 'package:puzzleband/services/banco.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio/servico_falso.dart' show AvisoFalso;

class Chamada {
  Chamada(this.id, this.titulo, this.comSom, this.atualizacao);

  final int id;
  final String titulo;
  final bool comSom;
  final bool atualizacao;
}

class NotificacoesFalsas extends NotificationService {
  final chamadas = <Chamada>[];

  @override
  Future<void> mostrarAlerta({
    required int id,
    required String titulo,
    required String texto,
    required bool comSom,
    required bool atualizacao,
    String? payload,
    bool ignoraNaoPerturbe = false,
  }) async {
    chamadas.add(Chamada(id, titulo, comSom, atualizacao));
  }
}

// Senha vazia: iniciar() carrega as preferencias mas nao tenta conectar.
const _semRede = AppConfig(host: 'broker.invalido', port: 8883, user: 'app', pass: '', childId: 'C01');
const _alertas = 'puzzleband/C01/alertas';
const _historico = 'puzzleband/C01/historico';
const _comando = 'puzzleband/C01/comando';

String alerta(String episodio, String nivel, {DateTime? quando}) => jsonEncode({
      'origem': 'site',
      'timestamp': (quando ?? DateTime.now()).toUtc().toIso8601String(),
      'episodio_id': episodio,
      'nivel_anterior': 'baixo_risco',
      'nivel': nivel,
      'probabilidade': 0.7,
      'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
    });

/// Abre o "app": um MqttService no mesmo shared_preferences e no mesmo banco
/// (o arquivo do celular), ja com o historico lido, como no main.
Future<(MqttService, NotificacoesFalsas)> criar(SharedPreferences prefs, BancoPuzzleBand banco) async {
  final notificacoes = NotificacoesFalsas();
  final service = MqttService(config: _semRede, prefs: prefs, banco: banco, notificacoes: notificacoes);
  await service.iniciar();
  await service.historicoLocal.recarregar();
  return (service, notificacoes);
}

/// A lista do Historico (o que as telas leem do banco).
List<Episodio> lista(MqttService s) => s.historicoLocal.recentes;

/// Como uma mensagem chegando, esperando a gravacao no banco.
Future<bool> receber(MqttService s, String topico, String texto) async {
  final mudou = s.tratarMensagem(topico, texto);
  await s.gravacoesPendentes;
  return mudou;
}

void main() {
  late SharedPreferences prefs;
  late BancoPuzzleBand banco;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    banco = BancoPuzzleBand.emMemoria();
  });

  tearDown(() => banco.close());

  test('sem configuracao completa nao conecta e explica o motivo', () async {
    final (service, _) = await criar(prefs, banco);
    expect(service.brokerStatus, BrokerStatus.naoConfigurado);
    expect(service.ultimoErro, contains('MQTT_PASS'));
  });

  test('uma notificacao por episodio; subir para possivel crise toca de novo na mesma', () async {
    final (service, n) = await criar(prefs, banco);

    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
    await service.notificacoesPendentes;
    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao')); // repetido (QoS 1)
    await service.notificacoesPendentes;
    expect(n.chamadas.length, 1);
    expect(n.chamadas[0].titulo, 'Atenção');
    expect(n.chamadas[0].atualizacao, isFalse);
    expect(n.chamadas[0].comSom, isTrue);

    service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    await service.notificacoesPendentes;
    expect(n.chamadas.length, 2);
    expect(n.chamadas[1].titulo, 'Possível crise');
    expect(n.chamadas[1].atualizacao, isTrue, reason: 'substitui a mesma notificacao');
    expect(n.chamadas[1].comSom, isTrue, reason: 'subiu de nivel: toca de novo');
    expect(n.chamadas[1].id, n.chamadas[0].id);

    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao')); // desceu: nada
    await service.notificacoesPendentes;
    service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco')); // de novo: nada
    await service.notificacoesPendentes;
    expect(n.chamadas.length, 2);

    service.tratarMensagem(_alertas, alerta('ep_2', 'alto_risco'));
    await service.notificacoesPendentes;
    expect(n.chamadas.length, 3);
    expect(n.chamadas[2].atualizacao, isFalse);
    expect(service.alertas.length, 6);
  });

  test('episodios ja notificados continuam lembrados depois de reabrir o app (no banco)', () async {
    final (primeiro, n1) = await criar(prefs, banco);
    primeiro.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    await primeiro.notificacoesPendentes;
    expect(n1.chamadas.length, 1);
    expect((await banco.notificados()).keys, ['ep_1']);
    expect(prefs.getString('episodios_notificados'), isNull, reason: 'nao vai mais para o shared_preferences');

    final (segundo, n2) = await criar(prefs, banco);
    segundo.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    await segundo.notificacoesPendentes;
    expect(n2.chamadas, isEmpty);
  });

  test('alerta velho, nivel calmo ou malformado nao notifica', () async {
    final (service, n) = await criar(prefs, banco);
    final velho = DateTime.now().subtract(const Duration(hours: 1));
    service.tratarMensagem(_alertas, alerta('ep_velho', 'alto_risco', quando: velho));
    await service.notificacoesPendentes;
    service.tratarMensagem(_alertas, alerta('ep_calmo', 'baixo_risco'));
    await service.notificacoesPendentes;
    expect(service.tratarMensagem(_alertas, '{"nivel": '), isFalse);
    expect(service.tratarMensagem(_alertas, '{"nivel":"desconhecido"}'), isFalse);
    expect(n.chamadas, isEmpty);
  });

  test('"Alertas sonoros" desligado: notificacao sem som', () async {
    final (service, n) = await criar(prefs, banco);
    await service.definirAlertasSonoros(false);
    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
    await service.notificacoesPendentes;
    expect(n.chamadas.single.comSom, isFalse);
    expect(prefs.getBool('alertas_sonoros'), isFalse);
  });

  test('banco indisponivel: notifica assim mesmo (melhor repetir que perder um alerta)', () async {
    final (service, n) = await criar(prefs, banco);
    await banco.close();
    service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    await service.notificacoesPendentes;
    expect(n.chamadas.single.titulo, 'Possível crise');
    banco = BancoPuzzleBand.emMemoria(); // para o tearDown
  });

  test('historico recebido fica no banco para ver offline', () async {
    final (primeiro, _) = await criar(prefs, banco);
    final mensagem = jsonEncode({
      'origem': 'pulseira',
      'episodios': [
        {
          'id': 'ep_1',
          'inicio': '2026-11-04T10:00:00Z',
          'nivel_maximo': 'alto_risco',
          'encerramento': 'normalizou',
          'duracao_s': 90,
          'avaliacao_cuidador': 'confirmado',
          'avaliacao_origem': 'site',
          'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
        },
      ],
    });
    expect(await receber(primeiro, _historico, mensagem), isTrue);
    expect(lista(primeiro).single.avaliacao, Avaliacao.confirmado);
    expect(lista(primeiro).single.gatilho!.tipo, 'ruido');
    expect(await receber(primeiro, _historico, 'quebrado'), isFalse);
    expect(lista(primeiro).length, 1, reason: 'mensagem ruim nao apaga a lista');
    expect(prefs.getString('historico_v1'), isNull, reason: 'nao vai mais para o shared_preferences');

    final (segundo, _) = await criar(prefs, banco);
    expect(lista(segundo).single.id, 'ep_1');
    expect(segundo.historicoRecebidoEm, isNotNull);
    expect(segundo.historicoAoVivo, isFalse, reason: 'salvo no banco, nao recebido nesta sessao');
  });

  test('estado com todas as metricas: lido, mas so entra no grafico ao vivo', () async {
    final (service, _) = await criar(prefs, banco);
    final estado = jsonEncode({
      'origem': 'site',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'fonte': 'manual',
      'nivel': 'atencao',
      'probabilidade': 0.61,
      'leituras': {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'bpm': 112, 'eda_uS': 7.1, 'hrv_ms': 30.5, 'gyro_mag_dps': 4.2,
        'regularidade': 0.35, 'luz_lux': 640, 'ruido_db': 71.2,
      },
    });
    expect(service.tratarMensagem('puzzleband/C01/estado', estado), isTrue);
    expect(service.estado!.leituras!.ruidoDb, 71.2);
    expect(service.sinaisRecentes, isEmpty, reason: 'sem conexao com o broker o estado nao e ao vivo');
  });

  test('sem conexao, ack e avaliacao nao sao enviados (episodio ainda na pulseira)', () async {
    final (service, _) = await criar(prefs, banco);
    await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'pendente')]));
    expect(service.enviarCiente('ep_1'), isFalse);
    expect(service.cienteEm('ep_1'), isNull);
    expect(service.enviarAvaliacao(lista(service).single, Avaliacao.confirmado, 'obs'), ResultadoDaAvaliacao.naoEnviada);
    await service.gravacoesPendentes;
    expect(lista(service).single.avaliacao, Avaliacao.pendente, reason: 'nada mudou');
  });

  // -------------------------------------------------------------------------
  // Lista da pulseira: acumula no banco; lista vazia nao apaga (mudanca)
  // -------------------------------------------------------------------------

  group('lista da pulseira', () {
    test('episodios que saem da lista de 50 continuam no banco do app', () async {
      final (service, _) = await criar(prefs, banco);
      await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-03T10:00:00Z'), ep('ep_2', '2026-11-04T10:00:00Z')]));
      // a pulseira passou de 50: o ep_1 saiu da lista publicada
      await receber(service, _historico, historico('pulseira', [ep('ep_2', '2026-11-04T10:00:00Z'), ep('ep_3', '2026-11-05T10:00:00Z')]));
      expect([for (final e in lista(service)) e.id], ['ep_3', 'ep_2', 'ep_1']);
      expect([for (final e in lista(service)) e.naPulseira], [true, true, false]);
    });

    test('lista vazia (--limpar-historico) NAO apaga o historico do app; so o reset apaga', () async {
      final (primeiro, _) = await criar(prefs, banco);
      await receber(primeiro, _historico, historico('pulseira', [ep('ep_1', '2026-11-03T10:00:00Z'), ep('ep_2', '2026-11-04T10:00:00Z')]));
      expect(await receber(primeiro, _historico, historico('pulseira', [])), isTrue);
      expect(lista(primeiro).length, 2);
      expect(lista(primeiro).every((e) => !e.naPulseira), isTrue, reason: 'nenhum esta mais na lista da pulseira');
      expect(contagemPorDia(lista(primeiro)), isNotEmpty, reason: 'calendario e 7 dias continuam');

      final (reaberto, _) = await criar(prefs, banco);
      expect(lista(reaberto).length, 2);
    });

    test('historico de outra origem (aba antiga do site) ou sem origem e ignorado', () async {
      final (service, _) = await criar(prefs, banco);
      final antigo = [ep('ep_velho', '2026-10-20T10:00:00Z')];
      expect(await receber(service, _historico, historico('site', antigo)), isFalse);
      expect(await receber(service, _historico, jsonEncode({'episodios': antigo})), isFalse);
      expect(lista(service), isEmpty);
      final (reaberto, _) = await criar(prefs, banco);
      expect(lista(reaberto), isEmpty);
    });

    test('a mesma lista recebida duas vezes (app e servico, QoS 1) nao duplica', () async {
      final (service, _) = await criar(prefs, banco);
      final msg = historico('pulseira', [ep('ep_1', '2026-11-03T10:00:00Z')]);
      await receber(service, _historico, msg);
      await receber(service, _historico, msg);
      expect(lista(service).length, 1);
      expect(service.historicoLocal.total, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Avaliacao do cuidador: pendente de confirmacao; episodio fora da lista
  // -------------------------------------------------------------------------

  group('avaliacao', () {
    late ServicoGravador service;

    setUp(() async {
      service = ServicoGravador(prefs: prefs, banco: banco);
      await service.iniciar();
    });

    /// O avaliacao_em que o app publicou (a pulseira devolve o mesmo valor).
    String timestampPublicado() =>
        jsonDecode(service.publicadas.lastWhere((p) => p.$1.endsWith('/avaliacao')).$2)['timestamp'] as String;

    test('vale a avaliacao local ate a pulseira devolver o mesmo avaliacao_em', () async {
      await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'pendente')]));
      expect(service.enviarAvaliacao(lista(service).single, Avaliacao.confirmado, 'barulho'), ResultadoDaAvaliacao.enviada);
      expect(lista(service).single.avaliacao, Avaliacao.confirmado, reason: 'aparece na hora');
      await service.gravacoesPendentes;
      final enviado = timestampPublicado();

      // lista retida antiga (de antes da avaliacao): nao desfaz
      await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'pendente')]));
      expect(lista(service).single.avaliacao, Avaliacao.confirmado);
      expect(lista(service).single.observacao, 'barulho');
      expect((await (banco.select(banco.episodios)).getSingle()).avaliacaoLocal, 'confirmado', reason: 'ainda pendente');

      // a pulseira aplicou e devolveu o mesmo avaliacao_em: confirmada
      await receber(service, _historico, historico('pulseira', [
        ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'confirmado', observacao: 'barulho', origem: 'app', em: enviado),
      ]));
      final linha = await (banco.select(banco.episodios)).getSingle();
      expect(linha.avaliacaoLocal, isNull, reason: 'confirmada pela pulseira');
      expect(linha.avaliacao, 'confirmado');
      expect(lista(service).single.avaliacao, Avaliacao.confirmado);
    });

    test('uma avaliacao mais nova (outro aparelho, depois desta) vence a local', () async {
      await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'pendente')]));
      service.enviarAvaliacao(lista(service).single, Avaliacao.confirmado, '');
      await service.gravacoesPendentes;
      final depois = DateTime.parse(timestampPublicado()).add(const Duration(minutes: 1)).toIso8601String();
      await receber(service, _historico, historico('pulseira', [
        ep('ep_1', '2026-11-04T10:00:00Z', avaliacao: 'descartado', origem: 'site', em: depois),
      ]));
      expect(lista(service).single.avaliacao, Avaliacao.descartado);
      expect(lista(service).single.avaliacaoOrigem, 'site');
    });

    test('episodio que ja saiu da lista da pulseira: grava so no app, sem publicar e sem conexao', () async {
      await receber(service, _historico, historico('pulseira', [ep('ep_velho', '2026-10-01T10:00:00Z', avaliacao: 'pendente')]));
      await receber(service, _historico, historico('pulseira', [ep('ep_novo', '2026-11-04T10:00:00Z')]));
      final velho = lista(service).firstWhere((e) => e.id == 'ep_velho');
      expect(velho.naPulseira, isFalse);

      service.conectado = false; // nem precisa de conexao
      expect(service.enviarAvaliacao(velho, Avaliacao.descartado, 'era exercício'), ResultadoDaAvaliacao.soNoCelular);
      await service.gravacoesPendentes;
      expect(service.publicadas.where((p) => p.$1.endsWith('/avaliacao')), isEmpty, reason: 'nada vai para a pulseira');
      final salvo = lista(service).firstWhere((e) => e.id == 'ep_velho');
      expect(salvo.avaliacao, Avaliacao.descartado);
      expect(salvo.observacao, 'era exercício');
      expect(salvo.avaliacaoOrigem, 'app');

      // continua depois de reabrir o app
      final (reaberto, _) = await criar(prefs, banco);
      expect(lista(reaberto).firstWhere((e) => e.id == 'ep_velho').avaliacao, Avaliacao.descartado);
    });
  });

  // -------------------------------------------------------------------------
  // Ordem de reset (npm run resetar) e "Apagar dados deste aparelho"
  // -------------------------------------------------------------------------

  group('ordem de reset', () {
    late AvisoFalso aviso;
    late PreferenciasLocais preferencias;
    late ServicoGravador service;

    setUp(() async {
      aviso = AvisoFalso();
      preferencias = PreferenciasLocais(prefs: prefs, banco: banco, nomePadrao: 'C01', aviso: aviso);
      await preferencias.carregar();
      service = ServicoGravador(prefs: prefs, banco: banco, aoApagarDados: preferencias.apagarDados);
      await service.iniciar();
      // dados de uma apresentacao anterior
      await receber(service, _historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z')]));
      service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
      await service.notificacoesPendentes;
      await preferencias.salvarLembrete('dia:2026-11-04', 'Levar o abafador',
          avisarEm: DateTime.now().add(const Duration(days: 1)), tituloDoAviso: 'Lembrete');
      await preferencias.definirNomeCrianca('Ana');
      await preferencias.definirAparencia(Aparencia.escuro);
      await service.definirAlertasSonoros(false);
    });

    Future<void> enviar(String id, {bool? manter}) async {
      service.tratarMensagem(_comando, jsonEncode({
        'acao': 'resetar',
        'id': id,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        if (manter != null) 'manter_preferencias': manter,
      }));
      await service.resetEmAndamento;
      await service.gravacoesPendentes;
    }

    test('apaga os dados (tambem do banco), confirma, avisa e guarda o id; mantem as preferencias', () async {
      final avisos = <String>[];
      service.avisos.listen(avisos.add);
      final lembreteId = PreferenciasLocais.idDoAviso('dia:2026-11-04');
      expect(aviso.agendados, contains(lembreteId));
      expect(await banco.lembretesSalvos(), isNotEmpty);

      await enviar('r1', manter: true);
      expect(lista(service), isEmpty);
      expect(service.alertas, isEmpty);
      expect(service.sinaisRecentes, isEmpty);
      expect(preferencias.lembrete('dia:2026-11-04'), isNull);
      expect(aviso.cancelados, contains(lembreteId), reason: 'o aviso agendado do lembrete e cancelado');
      // as tres tabelas vazias
      expect(await banco.recentes(10), isEmpty);
      expect(await banco.notificados(), isEmpty);
      expect(await banco.lembretesSalvos(), isEmpty);
      expect(service.resetAplicado, 'r1');
      expect(service.publicadas.single, ('puzzleband/C01/comando/resposta', '{"id":"r1","status":"aplicado"}'));
      await Future<void>.delayed(Duration.zero);
      expect(avisos, ['Dados apagados para uma nova apresentação.']);

      // preferencias mantidas
      expect(preferencias.nomeCrianca, 'Ana');
      expect(preferencias.aparencia, Aparencia.escuro);
      expect(service.alertasSonoros, isFalse);

      // o mesmo episodio volta a notificar (a lista de notificados foi apagada)
      final n = service.notificacoes as NotificacoesFalsas;
      final antes = n.chamadas.length;
      service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
      await service.notificacoesPendentes;
      expect(n.chamadas.length, antes + 1);
    });

    test('aplica uma vez so por id (a ordem e retida e chega a cada conexao)', () async {
      await enviar('r1');
      expect(service.publicadas.length, 1);

      // depois do reset, a pulseira publica episodios novos
      await receber(service, _historico, historico('pulseira', [ep('ep_novo', '2026-11-07T10:00:00Z')]));
      await enviar('r1'); // reconexao: a mesma ordem retida
      expect(lista(service).single.id, 'ep_novo', reason: 'nao apaga de novo');
      expect(service.publicadas.length, 1, reason: 'nao confirma de novo');

      // o app reaberto tambem lembra
      final reaberto = ServicoGravador(prefs: prefs, banco: banco);
      await reaberto.iniciar();
      await reaberto.historicoLocal.recarregar();
      reaberto.tratarMensagem(_comando, jsonEncode({'acao': 'resetar', 'id': 'r1'}));
      expect(reaberto.resetEmAndamento, isNull);
      expect(lista(reaberto).single.id, 'ep_novo');

      await enviar('r2'); // nova apresentacao
      expect(lista(service), isEmpty);
      expect(service.resetAplicado, 'r2');
    });

    test('manter_preferencias false volta nome, aparencia e alertas sonoros ao padrao', () async {
      await enviar('tudo', manter: false);
      expect(preferencias.nomeDigitado, '');
      expect(preferencias.nomeCrianca, 'C01');
      expect(preferencias.aparencia, Aparencia.sistema);
      expect(service.alertasSonoros, isTrue);
      expect(prefs.getString('nome_crianca'), isNull);
      expect(prefs.getString('aparencia'), isNull);
      expect(prefs.getBool('alertas_sonoros'), isNull);
      // um app reaberto le o padrao
      final reaberta = PreferenciasLocais(prefs: prefs, banco: banco, nomePadrao: 'C01', aviso: aviso);
      await reaberta.carregar();
      expect(reaberta.nomeCrianca, 'C01');
      expect(reaberta.aparencia, Aparencia.sistema);
      expect(reaberta.lembrete('dia:2026-11-04'), isNull);
    });

    test('ordem invalida, de outra acao ou payload vazio nao apaga nada', () async {
      for (final texto in ['', 'quebrado', '{"acao":"reiniciar","id":"x"}', '{"acao":"resetar"}']) {
        service.tratarMensagem(_comando, texto);
      }
      expect(service.resetEmAndamento, isNull);
      expect(lista(service).length, 1);
      expect(service.resetAplicado, isNull);
    });

    test('"Apagar dados deste aparelho": mesma limpeza, sem publicar nem guardar id', () async {
      await service.apagarDadosLocais(manterPreferencias: true);
      expect(lista(service), isEmpty);
      expect(await banco.recentes(10), isEmpty);
      expect(preferencias.lembrete('dia:2026-11-04'), isNull);
      expect(preferencias.nomeCrianca, 'Ana');
      expect(service.publicadas, isEmpty);
      expect(service.resetAplicado, isNull);
    });
  });
}

/// Historico como a pulseira (ou outra origem) publica.
String historico(String origem, List<Map<String, Object?>> episodios) =>
    jsonEncode({'origem': origem, 'timestamp': DateTime.now().toUtc().toIso8601String(), 'episodios': episodios});

Map<String, Object?> ep(
  String id,
  String inicio, {
  String avaliacao = 'confirmado',
  String observacao = '',
  String? origem,
  String? em,
}) =>
    {
      'id': id,
      'inicio': inicio,
      'nivel_maximo': 'alto_risco',
      'encerramento': 'normalizou',
      'duracao_s': 90,
      'avaliacao_cuidador': avaliacao,
      'observacao': observacao,
      'avaliacao_origem': origem,
      'avaliacao_em': em,
    };

/// MqttService sem rede que grava o que seria publicado.
class ServicoGravador extends MqttService {
  ServicoGravador({required super.prefs, required super.banco, super.aoApagarDados})
      : super(config: _semRede, notificacoes: NotificacoesFalsas());

  final publicadas = <(String, String)>[];

  /// false simula a falta de conexao (publicar devolve false).
  bool conectado = true;

  @override
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) {
    if (!conectado) return false;
    publicadas.add((topico, texto));
    return true;
  }
}
