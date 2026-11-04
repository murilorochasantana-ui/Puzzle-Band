// Testes do parse das mensagens do site e dos resumos (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:puzzleband/utils/formatters.dart';

Map<String, dynamic> episodioJson(String id, String inicio, {String nivel = 'atencao', String? encerramento}) => {
      'id': id,
      'crianca': 'simulada',
      'fonte': 'manual',
      'inicio': inicio,
      'fim': null,
      'duracao_s': 65,
      'encerramento': encerramento,
      'nivel_maximo': nivel,
      'probabilidade_maxima': 0.71,
      'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído (45 → 88 dB).'},
      'avaliacao_cuidador': 'pendente',
      'observacao': '',
      'avaliacao_origem': null,
      'avaliacao_em': null,
      'visto_pelo_cuidador_em': null,
    };

void main() {
  group('estado', () {
    test('mensagem completa do site', () {
      final e = EstadoAtual.tryParse(jsonEncode({
        'origem': 'site',
        'timestamp': '2026-11-04T12:00:00.000Z',
        'fonte': 'manual',
        'crianca': 'C01',
        'nivel': 'alto_risco',
        'probabilidade': 0.83,
        'leituras': {'timestamp': '2026-11-04T12:00:00.000Z', 'bpm': 128, 'eda_uS': 9.1, 'hrv_ms': 20.5},
        'media_bpm_5min': 96.4,
        'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
        'episodio': {'id': 'ep_1', 'inicio': '2026-11-04T11:59:40.000Z', 'nivel_maximo': 'alto_risco', 'visto_pelo_cuidador_em': null},
      }))!;
      expect(e.nivel, NivelRisco.altoRisco);
      expect(e.fonte, 'manual');
      expect(e.probabilidade, 0.83);
      expect(e.leituras!.bpm, 128);
      expect(e.mediaBpm5min, 96.4);
      expect(e.gatilho!.texto, 'Provável gatilho: ruído');
      expect(e.episodio!.id, 'ep_1');
      expect(e.episodio!.vistoEm, isNull);
    });

    test('sem episodio, sem leituras e probabilidade nula', () {
      final e = EstadoAtual.tryParse('{"nivel":"baixo_risco","probabilidade":null,"leituras":null,"episodio":null}')!;
      expect(e.nivel, NivelRisco.baixoRisco);
      expect(e.probabilidade, isNull);
      expect(e.leituras, isNull);
      expect(e.episodio, isNull);
    });

    test('malformado nao lanca excecao', () {
      for (final texto in ['', 'xx', '[]', 'null', '{"nivel":"talvez"}', '{"nivel":3}', '{"bpm":80}']) {
        expect(EstadoAtual.tryParse(texto), isNull, reason: texto);
      }
      // campo com tipo errado vira null, o resto continua valendo
      final e = EstadoAtual.tryParse('{"nivel":"atencao","probabilidade":"alta","leituras":{"bpm":"80"}}')!;
      expect(e.probabilidade, isNull);
      expect(e.leituras!.bpm, isNull);
    });
  });

  group('alerta', () {
    test('com nivel anterior e gatilho', () {
      final a = Alerta.tryParse(jsonEncode({
        'episodio_id': 'ep_1',
        'nivel_anterior': 'baixo_risco',
        'nivel': 'atencao',
        'probabilidade': 0.55,
        'gatilho': {'tipo': 'luminosidade', 'texto': 'Provável gatilho: luminosidade', 'sinais': {}},
        'timestamp': '2026-11-04T12:00:00Z',
      }))!;
      expect(a.episodioId, 'ep_1');
      expect(a.nivelAnterior, NivelRisco.baixoRisco);
      expect(a.nivel, NivelRisco.atencao);
      expect(a.gatilho!.tipo, 'luminosidade');
    });

    test('malformado', () {
      expect(Alerta.tryParse('{"episodio_id":"ep_1"}'), isNull);
      expect(Alerta.tryParse('{{'), isNull);
    });
  });

  group('historico', () {
    test('lista ordenada (mais recente primeiro) e itens invalidos pulados', () {
      final lista = parseHistorico(jsonEncode({
        'origem': 'site',
        'episodios': [
          episodioJson('ep_a', '2026-11-03T10:00:00Z', encerramento: 'normalizou'),
          {'id': 'sem_inicio', 'nivel_maximo': 'atencao'},
          'texto',
          episodioJson('ep_b', '2026-11-04T10:00:00Z', nivel: 'alto_risco'),
        ],
      }))!;
      expect(lista.map((e) => e.id), ['ep_b', 'ep_a']);
      expect(lista.first.emAndamento, isTrue);
      expect(lista.last.emAndamento, isFalse);
      expect(lista.first.nivelMaximo, NivelRisco.altoRisco);
      expect(lista.first.avaliacao, Avaliacao.pendente);
    });

    test('sem lista de episodios e descartado', () {
      expect(parseHistorico('{"episodios":"x"}'), isNull);
      expect(parseHistorico('nada'), isNull);
    });

    test('ida e volta pelo JSON salvo (copia offline)', () {
      final original = Episodio.fromJson(episodioJson('ep_1', '2026-11-04T10:00:00Z'))!
          .avaliadoPeloApp(Avaliacao.confirmado, 'sirene', DateTime.utc(2026, 11, 4, 10, 5));
      final salvo = jsonEncode({'episodios': [original.toJson()]});
      final lido = parseHistorico(salvo)!.single;
      expect(lido.id, 'ep_1');
      expect(lido.avaliacao, Avaliacao.confirmado);
      expect(lido.observacao, 'sirene');
      expect(lido.avaliacaoOrigem, 'app');
      expect(lido.avaliacaoEm!.toUtc(), DateTime.utc(2026, 11, 4, 10, 5));
      expect(lido.gatilho!.tipo, 'ruido');
    });
  });

  group('resumos', () {
    final agora = DateTime(2026, 11, 4, 15);
    final episodios = [
      Episodio(id: '1', inicio: DateTime(2026, 11, 4, 9), nivelMaximo: NivelRisco.atencao),
      Episodio(id: '2', inicio: DateTime(2026, 11, 4, 14), nivelMaximo: NivelRisco.altoRisco),
      Episodio(id: '3', inicio: DateTime(2026, 11, 2, 8), nivelMaximo: NivelRisco.atencao),
      Episodio(id: '4', inicio: DateTime(2026, 10, 20, 8), nivelMaximo: NivelRisco.atencao),
    ];

    test('episodios hoje e no mes', () {
      expect(episodiosNoDia(episodios, agora), 2);
      expect(episodiosNoMes(episodios, agora), 3);
    });

    test('ultimos 7 dias: total e nivel mais alto por dia', () {
      final dias = ultimos7Dias(episodios, agora);
      expect(dias.length, 7);
      expect(dias.last.rotulo, 'Qua'); // 04/11/2026 e quarta-feira
      expect(dias.last.total, 2);
      expect(dias.last.nivelMaximo, NivelRisco.altoRisco);
      expect(dias[4].total, 1); // 02/11
      expect(dias[4].nivelMaximo, NivelRisco.atencao);
      expect(dias.first.total, 0);
      expect(dias.first.nivelMaximo, isNull);
    });
  });

  group('outros', () {
    test('status online/offline', () {
      expect(parseOnline('online'), isTrue);
      expect(parseOnline(' OFFLINE '), isFalse);
      expect(parseOnline('{}'), isNull);
    });

    test('id de notificacao estavel por episodio', () {
      expect(idDeNotificacao('ep_1'), idDeNotificacao('ep_1'));
      expect(idDeNotificacao('ep_1'), isNot(idDeNotificacao('ep_2')));
      expect(idDeNotificacao('ep_1'), greaterThanOrEqualTo(0));
    });

    test('configuracao: senha ausente e CHILD_ID invalido sao apontados', () {
      const ok = AppConfig(host: 'h', port: 8883, user: 'app', pass: 'x', childId: 'C01');
      expect(ok.isValid, isTrue);
      expect(ok.topic('app/status'), 'puzzleband/C01/app/status');
      const ruim = AppConfig(host: 'h', port: 8883, user: 'app', pass: '', childId: 'C 01');
      expect(ruim.problems, ['MQTT_PASS', 'CHILD_ID']);
    });

    test('formatos de duracao', () {
      expect(duracao(42), '42 s');
      expect(duracao(65), '1 min 5 s');
      expect(duracao(null), '—');
    });
  });
}
