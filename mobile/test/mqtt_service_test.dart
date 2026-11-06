// Regras do MqttService sem rede: notificacao (uma por episodio), mensagem
// malformada e copia offline do historico (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      'origem': 'site',
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
}
