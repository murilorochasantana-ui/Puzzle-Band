// Testes do parse das mensagens do site e dos resumos (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
import 'package:puzzleband/models/sinais.dart';
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

    Episodio ep(String id, DateTime inicio, Avaliacao avaliacao, {double? duracaoS = 60, String? encerramento = 'normalizou'}) =>
        Episodio(
          id: id,
          inicio: inicio,
          nivelMaximo: NivelRisco.atencao,
          avaliacao: avaliacao,
          duracaoS: duracaoS,
          encerramento: encerramento,
        );

    test('calendario: conta pela avaliacao, descartado nao entra', () {
      final lista = [
        for (var i = 0; i < 7; i++) ep('v$i', DateTime(2026, 11, 3, 8 + i), Avaliacao.confirmado),
        for (var i = 0; i < 3; i++) ep('a$i', DateTime(2026, 11, 1, 8 + i), Avaliacao.confirmado),
        ep('p1', DateTime(2026, 11, 2, 9), Avaliacao.pendente),
        ep('p2', DateTime(2026, 11, 2, 10), Avaliacao.pendente),
        ep('d1', DateTime(2026, 11, 4, 9), Avaliacao.descartado),
        ep('d2', DateTime(2026, 11, 1, 20), Avaliacao.descartado),
        ep('m1', DateTime(2026, 11, 5, 9), Avaliacao.confirmado),
        ep('m2', DateTime(2026, 11, 5, 10), Avaliacao.pendente),
      ];
      final dias = contagemPorDia(lista);
      expect(dias[DateTime(2026, 11, 3)]!.confirmadas, 7);
      expect(dias[DateTime(2026, 11, 1)]!.confirmadas, 3, reason: 'o descartado do dia nao conta');
      expect(dias[DateTime(2026, 11, 2)]!.somentePendentes, isTrue);
      expect(dias[DateTime(2026, 11, 5)]!.somentePendentes, isFalse, reason: 'tem confirmada: sem bolinha');
      expect(dias.containsKey(DateTime(2026, 11, 4)), isFalse, reason: 'dia so com descartado nao aparece');

      expect(corDoDia(0), CorDoDia.nenhuma);
      expect(corDoDia(1), CorDoDia.amarelo);
      expect(corDoDia(3), CorDoDia.amarelo);
      expect(corDoDia(5), CorDoDia.amarelo);
      expect(corDoDia(6), CorDoDia.vermelho);
      expect(corDoDia(7), CorDoDia.vermelho);

      final mes = contagemNoMes(dias, 2026, 11);
      expect(mes.confirmadas, 11);
      expect(mes.pendentes, 3);
    });

    test('ultimos 7 dias: confirmadas e pendentes, sem descartados; duracao so dos encerrados', () {
      final lista = [
        ep('1', DateTime(2026, 11, 4, 9), Avaliacao.confirmado, duracaoS: 65),
        ep('2', DateTime(2026, 11, 4, 14), Avaliacao.pendente, duracaoS: 40),
        ep('3', DateTime(2026, 11, 4, 14, 50), Avaliacao.pendente, duracaoS: null, encerramento: null),
        ep('4', DateTime(2026, 11, 4, 10), Avaliacao.descartado, duracaoS: 500),
        ep('5', DateTime(2026, 11, 2, 8), Avaliacao.descartado),
        ep('6', DateTime(2026, 10, 20, 8), Avaliacao.confirmado),
      ];
      final dias = ultimos7Dias(lista, agora);
      expect(dias.length, 7);
      expect(dias.last.rotulo, 'Qua'); // 04/11/2026 e quarta-feira
      expect(dias.last.contagem.confirmadas, 1);
      expect(dias.last.contagem.pendentes, 2);
      expect(dias.last.contagem.duracaoS, 105, reason: 'descartado e em andamento nao somam');
      expect(dias[4].contagem.total, 0, reason: '02/11 so tem descartado');
      expect(dias.first.contagem.total, 0);
    });

    test('lista por dia: mais recente primeiro, todos os episodios', () {
      final grupos = episodiosPorDia([
        ep('a', DateTime(2026, 11, 2, 8), Avaliacao.descartado),
        ep('b', DateTime(2026, 11, 4, 9), Avaliacao.pendente),
        ep('c', DateTime(2026, 11, 4, 14), Avaliacao.confirmado),
      ]);
      expect(grupos.map((g) => g.$1), [DateTime(2026, 11, 4), DateTime(2026, 11, 2)]);
      expect(grupos.first.$2.map((e) => e.id), ['c', 'b']);
      expect(grupos.last.$2.single.id, 'a', reason: 'descartado continua na lista');
    });
  });

  group('sinais ao vivo', () {
    final inicio = DateTime(2026, 11, 5, 15);
    EstadoAtual estado(String leitura, {double? bpm = 90, NivelRisco nivel = NivelRisco.baixoRisco}) => EstadoAtual(
          fonte: 'manual',
          nivel: nivel,
          probabilidade: 0.42,
          leituras: Leituras(
            timestamp: leitura,
            bpm: bpm,
            edaUs: 3.1,
            hrvMs: 48,
            gyroDps: 1.5,
            regularidade: 0.2,
            luzLux: 300,
            ruidoDb: 50,
          ),
        );

    test('guarda todas as metricas por 5 minutos, uma vez por leitura', () {
      final janela = JanelaDeSinais();
      expect(janela.registrar(estado('l1'), inicio, aoVivo: true), isTrue);
      expect(janela.registrar(estado('l1'), inicio.add(const Duration(seconds: 1)), aoVivo: true), isFalse,
          reason: 'site pausado repete a leitura');
      expect(janela.registrar(estado('l2', bpm: null), inicio.add(const Duration(seconds: 2)), aoVivo: true), isTrue,
          reason: 'sem BPM ainda guarda as outras metricas');
      expect(janela.registrar(estado('l3'), inicio.add(const Duration(seconds: 3)), aoVivo: false), isFalse);

      final a = janela.amostras.first;
      expect(Metrica.values.map((m) => m.valor(a)), [90, 3.1, 48, 1.5, 0.2, 300, 50, closeTo(42, 1e-9)]);
      expect(janela.amostras[1].bpm, isNull);

      janela.registrar(estado('l4'), inicio.add(const Duration(minutes: 5, seconds: 1)), aoVivo: true);
      expect(janela.amostras.length, 2, reason: 'a primeira passou de 5 min');
    });

    test('estatistica, faixa do eixo e trechos de nivel', () {
      const niveis = [
        NivelRisco.baixoRisco,
        NivelRisco.atencao,
        NivelRisco.atencao,
        NivelRisco.altoRisco,
        NivelRisco.baixoRisco,
        NivelRisco.atencao,
      ];
      final amostras = [
        for (var i = 0; i < 6; i++) AmostraSinais(hora: inicio.add(Duration(seconds: i)), nivel: niveis[i], bpm: 80.0 + i * 10),
      ];
      final est = EstatisticaSinal.de(amostras, Metrica.bpm)!;
      expect([est.atual, est.minima, est.maxima, est.media], [130, 80, 130, 105]);
      expect(EstatisticaSinal.de(amostras, Metrica.eda), isNull);

      final faixa = Metrica.bpm.faixa.ajustada([35, 190]);
      expect([faixa.minimo, faixa.maximo, faixa.intervalo], [0, 200, 40], reason: 'no maximo 6 divisoes');
      expect(Metrica.regularidade.faixa.ajustada([3]).maximo, 1, reason: 'faixa fixa');

      final trechos = trechosDeNivel(amostras);
      expect(trechos.map((t) => t.nivel), [NivelRisco.atencao, NivelRisco.altoRisco, NivelRisco.atencao]);
      expect(trechos.first.inicio, inicio.add(const Duration(seconds: 1)));
      expect(trechos.first.fim, inicio.add(const Duration(seconds: 3)));
      expect(trechos.last.fim, inicio.add(const Duration(seconds: 5)));
    });

    test('formatos: virgula decimal, datas por extenso e contagens', () {
      expect(numeroBr(9.42, 1), '9,4');
      expect(numeroBr(128, 0), '128');
      expect(dataCurta(DateTime(2026, 11, 3)), 'Ter, 3 de nov.');
      expect(dataCurta(DateTime(2025, 5, 4), agora: inicio), 'Dom, 4 de maio de 2025');
      expect(diaPorExtenso(DateTime(2026, 11, 3)), '3 de novembro');
      expect(mesEAno(DateTime(2026, 11)), 'Novembro de 2026');
      expect(contarConfirmadas(1), '1 crise confirmada');
      expect(contarPendentes(2), '2 possíveis crises aguardando confirmação');
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
