// Regras do MqttService sem rede: notificacao (uma por episodio), mensagem
// malformada e copia offline do historico (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/config/app_config.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
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

Future<(MqttService, NotificacoesFalsas)> criar(SharedPreferences prefs) async {
  final notificacoes = NotificacoesFalsas();
  final service = MqttService(config: _semRede, prefs: prefs, notificacoes: notificacoes);
  await service.iniciar();
  return (service, notificacoes);
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('sem configuracao completa nao conecta e explica o motivo', () async {
    final (service, _) = await criar(prefs);
    expect(service.brokerStatus, BrokerStatus.naoConfigurado);
    expect(service.ultimoErro, contains('MQTT_PASS'));
  });

  test('uma notificacao por episodio; subir para possivel crise atualiza sem som', () async {
    final (service, n) = await criar(prefs);

    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao')); // repetido (QoS 1)
    expect(n.chamadas.length, 1);
    expect(n.chamadas[0].titulo, 'Atenção');
    expect(n.chamadas[0].atualizacao, isFalse);
    expect(n.chamadas[0].comSom, isTrue);

    service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    expect(n.chamadas.length, 2);
    expect(n.chamadas[1].titulo, 'Possível crise');
    expect(n.chamadas[1].atualizacao, isTrue, reason: 'mesma notificacao, sem tocar de novo');
    expect(n.chamadas[1].id, n.chamadas[0].id);

    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao')); // desceu: nada
    service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco')); // de novo: nada
    expect(n.chamadas.length, 2);

    service.tratarMensagem(_alertas, alerta('ep_2', 'alto_risco'));
    expect(n.chamadas.length, 3);
    expect(n.chamadas[2].atualizacao, isFalse);
    expect(service.alertas.length, 6);
  });

  test('episodios ja notificados continuam lembrados depois de reabrir o app', () async {
    final (primeiro, n1) = await criar(prefs);
    primeiro.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    expect(n1.chamadas.length, 1);

    final (segundo, n2) = await criar(prefs);
    segundo.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
    expect(n2.chamadas, isEmpty);
  });

  test('alerta velho, nivel calmo ou malformado nao notifica', () async {
    final (service, n) = await criar(prefs);
    final velho = DateTime.now().subtract(const Duration(hours: 1));
    service.tratarMensagem(_alertas, alerta('ep_velho', 'alto_risco', quando: velho));
    service.tratarMensagem(_alertas, alerta('ep_calmo', 'baixo_risco'));
    expect(service.tratarMensagem(_alertas, '{"nivel": '), isFalse);
    expect(service.tratarMensagem(_alertas, '{"nivel":"desconhecido"}'), isFalse);
    expect(n.chamadas, isEmpty);
  });

  test('"Alertas sonoros" desligado: notificacao sem som', () async {
    final (service, n) = await criar(prefs);
    await service.definirAlertasSonoros(false);
    service.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
    expect(n.chamadas.single.comSom, isFalse);
    expect(prefs.getBool('alertas_sonoros'), isFalse);
  });

  test('historico recebido fica salvo para ver offline', () async {
    final (primeiro, _) = await criar(prefs);
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
    expect(primeiro.tratarMensagem(_historico, mensagem), isTrue);
    expect(primeiro.historico.single.avaliacao, Avaliacao.confirmado);
    expect(primeiro.tratarMensagem(_historico, 'quebrado'), isFalse);
    expect(primeiro.historico.length, 1, reason: 'mensagem ruim nao apaga a lista');

    final (segundo, _) = await criar(prefs);
    expect(segundo.historico.single.id, 'ep_1');
    expect(segundo.historicoRecebidoEm, isNotNull);
    expect(segundo.historicoAoVivo, isFalse, reason: 'copia salva, nao recebida nesta sessao');
  });

  test('estado com todas as metricas: lido, mas so entra no grafico ao vivo', () async {
    final (service, _) = await criar(prefs);
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

  test('sem conexao, ack e avaliacao nao sao enviados', () async {
    final (service, _) = await criar(prefs);
    final ep = Episodio(id: 'ep_1', inicio: DateTime(2026, 11, 4), nivelMaximo: NivelRisco.atencao);
    expect(service.enviarCiente('ep_1'), isFalse);
    expect(service.cienteEm('ep_1'), isNull);
    expect(service.enviarAvaliacao(ep, Avaliacao.confirmado, 'obs'), isFalse);
  });

  // -------------------------------------------------------------------------
  // Historico vazio da pulseira (--limpar-historico) e origem
  // -------------------------------------------------------------------------

  group('historico vazio da pulseira', () {
    test('substitui a copia salva e continua vazio ao reabrir o app', () async {
      final (primeiro, _) = await criar(prefs);
      primeiro.tratarMensagem(_historico, historico('pulseira', [ep('ep_1', '2026-11-03T10:00:00Z'), ep('ep_2', '2026-11-04T10:00:00Z')]));
      expect(primeiro.historico.length, 2);

      // reabre: aparece a copia salva ate chegar o retido da pulseira
      final (segundo, _) = await criar(prefs);
      expect(segundo.historico.length, 2);
      expect(segundo.tratarMensagem(_historico, historico('pulseira', [])), isTrue);
      expect(segundo.historico, isEmpty);
      expect(contagemPorDia(segundo.historico), isEmpty, reason: 'calendario e 7 dias sem crises');

      final (terceiro, _) = await criar(prefs);
      expect(terceiro.historico, isEmpty, reason: 'a lista vazia fica salva');
    });

    test('historico de outra origem (aba antiga do site) ou sem origem e ignorado', () async {
      final (service, _) = await criar(prefs);
      service.tratarMensagem(_historico, historico('pulseira', []));
      final antigo = [ep('ep_velho', '2026-10-20T10:00:00Z')];
      expect(service.tratarMensagem(_historico, historico('site', antigo)), isFalse);
      expect(service.tratarMensagem(_historico, jsonEncode({'episodios': antigo})), isFalse);
      expect(service.historico, isEmpty);
      final (reaberto, _) = await criar(prefs);
      expect(reaberto.historico, isEmpty);
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
      preferencias = PreferenciasLocais(prefs: prefs, nomePadrao: 'C01', aviso: aviso);
      service = ServicoGravador(prefs: prefs, aoApagarDados: preferencias.apagarDados);
      await service.iniciar();
      // dados de uma apresentacao anterior
      service.tratarMensagem(_historico, historico('pulseira', [ep('ep_1', '2026-11-04T10:00:00Z')]));
      service.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
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
    }

    test('apaga os dados, confirma, avisa e guarda o id; mantem as preferencias', () async {
      final avisos = <String>[];
      service.avisos.listen(avisos.add);
      final lembreteId = PreferenciasLocais.idDoAviso('dia:2026-11-04');
      expect(aviso.agendados, contains(lembreteId));

      await enviar('r1', manter: true);
      expect(service.historico, isEmpty);
      expect(service.alertas, isEmpty);
      expect(service.sinaisRecentes, isEmpty);
      expect(preferencias.lembrete('dia:2026-11-04'), isNull);
      expect(aviso.cancelados, contains(lembreteId), reason: 'o aviso agendado do lembrete e cancelado');
      expect(prefs.getString('historico_v1'), isNull);
      expect(prefs.getString('episodios_notificados'), isNull);
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
      expect(n.chamadas.length, antes + 1);
    });

    test('aplica uma vez so por id (a ordem e retida e chega a cada conexao)', () async {
      await enviar('r1');
      expect(service.publicadas.length, 1);

      // depois do reset, a pulseira publica episodios novos
      service.tratarMensagem(_historico, historico('pulseira', [ep('ep_novo', '2026-11-07T10:00:00Z')]));
      await enviar('r1'); // reconexao: a mesma ordem retida
      expect(service.historico.single.id, 'ep_novo', reason: 'nao apaga de novo');
      expect(service.publicadas.length, 1, reason: 'nao confirma de novo');

      // o app reaberto tambem lembra
      final reaberto = ServicoGravador(prefs: prefs);
      await reaberto.iniciar();
      reaberto.tratarMensagem(_comando, jsonEncode({'acao': 'resetar', 'id': 'r1'}));
      expect(reaberto.resetEmAndamento, isNull);
      expect(reaberto.historico.single.id, 'ep_novo');

      await enviar('r2'); // nova apresentacao
      expect(service.historico, isEmpty);
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
      final reaberta = PreferenciasLocais(prefs: prefs, nomePadrao: 'C01', aviso: aviso);
      expect(reaberta.nomeCrianca, 'C01');
      expect(reaberta.aparencia, Aparencia.sistema);
    });

    test('ordem invalida, de outra acao ou payload vazio nao apaga nada', () async {
      for (final texto in ['', 'quebrado', '{"acao":"reiniciar","id":"x"}', '{"acao":"resetar"}']) {
        service.tratarMensagem(_comando, texto);
      }
      expect(service.resetEmAndamento, isNull);
      expect(service.historico.length, 1);
      expect(service.resetAplicado, isNull);
    });

    test('"Apagar dados deste aparelho": mesma limpeza, sem publicar nem guardar id', () async {
      await service.apagarDadosLocais(manterPreferencias: true);
      expect(service.historico, isEmpty);
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

Map<String, Object?> ep(String id, String inicio) => {
      'id': id,
      'inicio': inicio,
      'nivel_maximo': 'alto_risco',
      'encerramento': 'normalizou',
      'duracao_s': 90,
      'avaliacao_cuidador': 'confirmado',
    };

/// MqttService sem rede que grava o que seria publicado.
class ServicoGravador extends MqttService {
  ServicoGravador({required super.prefs, super.aoApagarDados})
      : super(config: _semRede, notificacoes: NotificacoesFalsas());

  final publicadas = <(String, String)>[];

  @override
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) {
    publicadas.add((topico, texto));
    return true;
  }
}
