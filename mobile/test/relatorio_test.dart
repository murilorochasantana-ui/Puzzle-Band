// Relatorio em Excel (services/relatorio.dart e services/planilha_xlsx.dart):
// gera o .xlsx a partir do banco, abre o arquivo com uma biblioteca de
// leitura independente (pacote excel, so nos testes) e confere o XML (aba
// congelada, larguras, nenhum texto como formula).
//
// Arquivo de exemplo para abrir no Excel, no Google Planilhas e no
// LibreOffice (docs/exemplos/):
//   flutter test test/relatorio_test.dart --dart-define=GERAR_EXEMPLO=true
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/lembrete.dart';
import 'package:puzzleband/models/metricas.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/banco.dart';
import 'package:puzzleband/services/planilha_xlsx.dart';
import 'package:puzzleband/services/relatorio.dart';
import 'package:xml/xml.dart';

const _gerarExemplo = bool.fromEnvironment('GERAR_EXEMPLO');

// ---------------------------------------------------------------------------
// Dados de exemplo: um dia de escola (horario local do celular)
// ---------------------------------------------------------------------------

final dia = DateTime(2026, 11, 25);
DateTime as(int h, int m, [int s = 0]) => DateTime(dia.year, dia.month, dia.day, h, m, s);

MetricasDoEpisodio metricas({
  required double bpmAntes,
  required double bpmDurante,
  required double bpmPico,
  required double bpmRecuperacao,
  required double ruidoAntes,
  required double ruidoDurante,
  required double luzDurante,
  int nDurante = 95,
}) {
  JanelaDeMetricas janela(int n, Map<Sinal, (double, double?, double?)> v) => JanelaDeMetricas(
        nLeituras: n,
        sinais: {
          for (final MapEntry(key: s, value: (media, min, max)) in v.entries)
            s: ValorDoSinal(media: media, minimo: min, maximo: max, nLeituras: n),
        },
      );
  return MetricasDoEpisodio({
    Fase.antes: janela(120, {
      Sinal.bpm: (bpmAntes, null, null),
      Sinal.vfc: (52.4, null, null),
      Sinal.eda: (2.31, null, null),
      Sinal.movimento: (14.2, null, null),
      Sinal.luz: (310, null, null),
      Sinal.ruido: (ruidoAntes, null, null),
    }),
    Fase.durante: janela(nDurante, {
      Sinal.bpm: (bpmDurante, bpmAntes - 2, bpmPico),
      Sinal.vfc: (28.7, 19.5, 41.0),
      Sinal.eda: (6.84, 2.9, 9.42),
      Sinal.movimento: (48.3, 9.1, 112.6),
      Sinal.luz: (luzDurante, 280, luzDurante + 300),
      Sinal.ruido: (ruidoDurante, ruidoAntes, ruidoDurante + 6),
    }),
    Fase.recuperacao: janela(30, {
      Sinal.bpm: (bpmRecuperacao, null, null),
      Sinal.vfc: (44.1, null, null),
      Sinal.eda: (4.02, null, null),
      Sinal.movimento: (18.9, null, null),
      Sinal.luz: (315, null, null),
      Sinal.ruido: (ruidoAntes + 3, null, null),
    }),
  });
}

Episodio episodio(
  String id,
  DateTime inicio,
  int duracaoS,
  NivelRisco nivel,
  String? gatilho, {
  Avaliacao avaliacao = Avaliacao.pendente,
  String observacao = '',
  MetricasDoEpisodio? m,
  double prob = 0.7,
}) =>
    Episodio(
      id: id,
      crianca: 'C01',
      fonte: 'pulseira',
      inicio: inicio,
      fim: inicio.add(Duration(seconds: duracaoS + 30)),
      duracaoS: duracaoS.toDouble(),
      encerramento: 'normalizou',
      nivelMaximo: nivel,
      probabilidadeMaxima: prob,
      gatilho: gatilho == null ? null : Gatilho(tipo: gatilho, texto: 'Provável gatilho'),
      avaliacao: avaliacao,
      observacao: observacao,
      avaliacaoOrigem: avaliacao == Avaliacao.pendente ? null : 'app',
      avaliacaoEm: avaliacao == Avaliacao.pendente ? null : inicio.add(const Duration(minutes: 10)),
      metricas: m,
    );

List<Episodio> episodiosDoDia() => [
      // pulseira antiga: sem metricas (celulas vazias)
      episodio('ep_0740', as(7, 40), 48, NivelRisco.atencao, 'nenhum_ambiental'),
      episodio('ep_0912', as(9, 12), 74, NivelRisco.atencao, 'ruido',
          avaliacao: Avaliacao.descartado,
          observacao: 'Brincadeira no pátio, estava bem.',
          prob: 0.58,
          m: metricas(bpmAntes: 92, bpmDurante: 108.4, bpmPico: 117, bpmRecuperacao: 95.2, ruidoAntes: 58.3, ruidoDurante: 79.6, luzDurante: 340)),
      episodio('ep_1432', as(14, 32), 187, NivelRisco.altoRisco, 'ruido',
          avaliacao: Avaliacao.confirmado,
          observacao: '=sirene da escola tocou antes',
          prob: 0.91,
          m: metricas(bpmAntes: 88.6, bpmDurante: 128.3, bpmPico: 142, bpmRecuperacao: 97.5, ruidoAntes: 46.2, ruidoDurante: 86.9, luzDurante: 330, nDurante: 187)),
      episodio('ep_1605', as(16, 5), 95, NivelRisco.atencao, 'luminosidade',
          prob: 0.66,
          m: metricas(bpmAntes: 90.1, bpmDurante: 112.7, bpmPico: 121, bpmRecuperacao: 93.4, ruidoAntes: 51.0, ruidoDurante: 54.2, luzDurante: 980)),
    ];

/// Minutos monitorados: 07:00 as 18:00, com uma falha das 12:00 as 12:30
/// (celular sem internet e pulseira desligada).
List<ResumoDoMinuto> minutosDoDia() {
  final lista = <ResumoDoMinuto>[];
  for (var t = as(7, 0); t.isBefore(as(18, 0)); t = t.add(const Duration(minutes: 1))) {
    if (!t.isBefore(as(12, 0)) && t.isBefore(as(12, 30))) continue;
    final i = t.difference(as(7, 0)).inMinutes;
    final crise = !t.isBefore(as(14, 31)) && t.isBefore(as(14, 36));
    final atencao = (!t.isBefore(as(9, 11)) && t.isBefore(as(9, 14))) || (!t.isBefore(as(16, 4)) && t.isBefore(as(16, 7)));
    final bpm = 90 + 6 * sin(i / 37) + (crise ? 35 : 0) + (atencao ? 18 : 0);
    lista.add(ResumoDoMinuto(
      minuto: t.toUtc(),
      nivelMaximo: crise ? NivelRisco.altoRisco : (atencao ? NivelRisco.atencao : NivelRisco.baixoRisco),
      nLeituras: 60,
      sinais: {
        Sinal.bpm: (media: bpm, n: 60),
        Sinal.vfc: (media: 50 - (crise ? 20 : 0) + 3 * cos(i / 23), n: 60),
        Sinal.eda: (media: 2.4 + (crise ? 4 : 0) + 0.3 * sin(i / 50), n: 60),
        Sinal.movimento: (media: 15 + (crise ? 35 : 0) + 5 * sin(i / 11).abs(), n: 60),
        Sinal.luz: (media: t.hour < 12 ? 320 : 290 + (t.hour == 16 ? 500 : 0), n: 60),
        Sinal.ruido: (media: 52 + (crise ? 33 : 0) + 4 * sin(i / 17), n: 60),
      },
    ));
  }
  return lista;
}

Future<BancoPuzzleBand> bancoComODia() async {
  final banco = BancoPuzzleBand.emMemoria();
  addTearDown(banco.close);
  final agora = as(18, 30);
  await banco.gravarDaPulseira(episodiosDoDia(), agora);
  await banco.gravarResumos(minutosDoDia(), agora);
  await banco.gravarLembrete('episodio:ep_1432', Lembrete(texto: 'Levar o abafador de ruído amanhã.', salvoEm: agora));
  return banco;
}

Future<DadosDoRelatorio> dadosDoDia(BancoPuzzleBand banco, {DateTime? agora}) => DadosDoRelatorio.doBanco(
      banco,
      periodo: PeriodoDoRelatorio.dia(dia),
      childId: 'C01',
      agora: agora ?? DateTime(2026, 11, 26, 8), // dia ja terminado
    );

// ---------------------------------------------------------------------------
// Leitura do .xlsx
// ---------------------------------------------------------------------------

String? texto(xls.Data? c) => switch (c?.value) {
      null => null,
      xls.TextCellValue v => v.value.text,
      final v => v.toString(),
    };

double? numero(xls.Data? c) => switch (c?.value) {
      xls.IntCellValue v => v.value.toDouble(),
      xls.DoubleCellValue v => v.value,
      _ => null,
    };

/// Duracao ([h]:mm:ss): o leitor entrega como horario.
double? segundos(xls.Data? c) => switch (c?.value) {
      xls.TimeCellValue v => (v.hour * 3600 + v.minute * 60 + v.second).toDouble(),
      xls.DoubleCellValue v => v.value * 86400,
      _ => null,
    };

Archive zipDe(List<int> bytes) => ZipDecoder().decodeBytes(bytes);

XmlDocument xmlDe(Archive zip, String nome) => XmlDocument.parse(utf8.decode(zip.findFile(nome)!.content as List<int>));

void main() {
  group('gravador .xlsx', () {
    test('letras das colunas e numero de serie do Excel', () {
      expect([letraDaColuna(0), letraDaColuna(25), letraDaColuna(26), letraDaColuna(39), letraDaColuna(701)],
          ['A', 'Z', 'AA', 'AN', 'ZZ']);
      expect(serialDoExcel(DateTime(1900, 1, 1)), 2); // 1 + o 29/02/1900 que o Excel conta
      expect(serialDoExcel(DateTime(2026, 11, 25, 18)), closeTo(46351.75, 1e-9));
    });

    test('texto com "=" ou caracteres especiais fica texto (nunca formula) e o XML continua valido', () {
      final bytes = gerarXlsx([
        const Aba(nome: 'Teste: [1]', colunas: [Coluna('A'), Coluna('B', formato: Formato.decimal1)], linhas: [
          ['=SOMA(A1:A9)', 1.25],
          ['<b>&"aspas"\u0001', null],
        ]),
      ]);
      final zip = zipDe(bytes);
      final planilha = xmlDe(zip, 'xl/worksheets/sheet1.xml');
      expect(planilha.findAllElements('f'), isEmpty);
      final textos = xmlDe(zip, 'xl/sharedStrings.xml').findAllElements('t').map((e) => e.innerText).toList();
      expect(textos, containsAll(['=SOMA(A1:A9)', '<b>&"aspas"']));
      // nome de aba sem os caracteres proibidos
      expect(xmlDe(zip, 'xl/workbook.xml').findAllElements('sheet').single.getAttribute('name'), 'Teste   1');
      final excel = xls.Excel.decodeBytes(bytes);
      expect(texto(excel.tables.values.single.rows[1][0]), '=SOMA(A1:A9)');
    });
  });

  group('relatorio do dia', () {
    late List<int> bytes;
    late xls.Excel excel;
    late Archive zip;

    setUp(() async {
      final banco = await bancoComODia();
      final dados = await dadosDoDia(banco);
      final pasta = await Directory.systemTemp.createTemp('puzzleband_relatorio_');
      addTearDown(() => pasta.delete(recursive: true));
      final arquivo = await gravarRelatorio(dados, pasta);
      expect(arquivo.path, endsWith('puzzleband_relatorio_C01_2026-11-25.xlsx'));
      bytes = await arquivo.readAsBytes();
      excel = xls.Excel.decodeBytes(bytes);
      zip = zipDe(bytes);
      if (_gerarExemplo) {
        final destino = File('../docs/exemplos/${nomeDoArquivo('C01', dados.periodo)}');
        await destino.parent.create(recursive: true);
        await destino.writeAsBytes(bytes);
      }
    });

    test('tres abas, na ordem, e o pacote excel (leitor independente) abre o arquivo', () {
      final nomes = [for (final s in xmlDe(zip, 'xl/workbook.xml').findAllElements('sheet')) s.getAttribute('name')];
      expect(nomes, ['Resumo do dia', 'Episódios', 'Por hora']);
      expect(excel.tables.keys.toSet(), nomes.toSet());
    });

    test('cabecalhos em portugues com unidades, primeira linha congelada e larguras', () {
      final episodios = excel.tables['Episódios']!;
      final cabecalho = [for (final c in episodios.rows.first) texto(c)];
      expect(cabecalho.take(10), [
        'Início', 'Fim', 'Duração (h:mm:ss)', 'Situação', 'Nível máximo', 'Probabilidade máxima (%)',
        'Provável gatilho', 'Avaliação do cuidador', 'Observação', 'Lembrete',
      ]);
      expect(cabecalho, containsAll([
        'BPM antes (bpm)', 'BPM durante (bpm)', 'BPM pico durante (bpm)', 'BPM recuperação (bpm)',
        'VFC antes (ms)', 'EDA durante (µS)', 'Movimento pico durante (dps)', 'Luz recuperação (lux)',
        'Ruído antes (dB)', 'Leituras antes', 'Leituras durante', 'Leituras recuperação',
      ]));
      final resumo = [for (final c in excel.tables['Resumo do dia']!.rows.first) texto(c)];
      expect(resumo, containsAll([
        'Data', 'Episódios de atenção', 'Episódios de possível crise', 'Crises confirmadas', 'Crises descartadas',
        'Crises pendentes de avaliação', 'Tempo total em episódio (h:mm:ss)', 'Gatilho mais frequente',
        'BPM médio (bpm)', 'VFC média (ms)', 'EDA média (µS)', 'Movimento médio (dps)', 'Luz média (lux)',
        'Ruído médio (dB)', 'Cobertura do monitoramento (%)',
      ]));

      for (var i = 1; i <= 3; i++) {
        final planilha = xmlDe(zip, 'xl/worksheets/sheet$i.xml');
        final pane = planilha.findAllElements('pane').single;
        expect(pane.getAttribute('state'), 'frozen');
        expect(pane.getAttribute('ySplit'), '1');
        expect(pane.getAttribute('topLeftCell'), 'A2');
        final larguras = [for (final c in planilha.findAllElements('col')) double.parse(c.getAttribute('width')!)];
        final colunas = planilha.findAllElements('row').first.findElements('c').length;
        expect(larguras, hasLength(colunas));
        expect(larguras.every((l) => l >= 10), isTrue, reason: 'colunas com largura legivel');
      }
    });

    test('Episodios: uma linha por episodio, valores e celula vazia sem metricas', () {
      final aba = excel.tables['Episódios']!;
      final cab = [for (final c in aba.rows.first) texto(c)];
      int col(String nome) => cab.indexOf(nome);
      expect(aba.rows, hasLength(5)); // cabecalho + 4
      final linhas = aba.rows.skip(1).toList();
      String? t(int linha, String coluna) => texto(linhas[linha][col(coluna)]);
      double? n(int linha, String coluna) => numero(linhas[linha][col(coluna)]);

      // do mais antigo para o mais novo
      expect(t(0, 'Nível máximo'), 'Atenção');
      expect(t(2, 'Nível máximo'), 'Possível crise');
      expect(t(2, 'Avaliação do cuidador'), 'Confirmada');
      expect(t(2, 'Observação'), '=sirene da escola tocou antes');
      expect(t(2, 'Lembrete'), 'Levar o abafador de ruído amanhã.');
      expect(t(2, 'Provável gatilho'), 'Barulho');
      expect(n(2, 'Probabilidade máxima (%)'), closeTo(0.91, 1e-9));
      expect(n(2, 'BPM antes (bpm)'), closeTo(88.6, 1e-9));
      expect(n(2, 'BPM durante (bpm)'), closeTo(128.3, 1e-9));
      expect(n(2, 'BPM pico durante (bpm)'), 142);
      expect(n(2, 'BPM recuperação (bpm)'), closeTo(97.5, 1e-9));
      expect(n(2, 'Ruído durante (dB)'), closeTo(86.9, 1e-9));
      expect(n(2, 'Leituras durante'), 187);
      expect(n(2, 'Leituras recuperação'), 30);
      // duracao 187 s como fracao do dia (h:mm:ss)
      expect(segundos(linhas[2][col('Duração (h:mm:ss)')]), 187);

      // episodio sem metricas (pulseira antiga): celulas vazias
      expect(t(0, 'Provável gatilho'), 'Nenhum (som e luz não mudaram)');
      for (final s in ['BPM antes (bpm)', 'BPM durante (bpm)', 'Ruído recuperação (dB)', 'Leituras antes']) {
        expect(linhas[0].length <= col(s) || linhas[0][col(s)] == null, isTrue, reason: s);
      }
    });

    test('Resumo do dia: contagens, tempo em episodio, gatilho, medias e cobertura', () {
      final aba = excel.tables['Resumo do dia']!;
      expect(aba.rows, hasLength(2), reason: 'um dia: sem a linha do periodo');
      final cab = [for (final c in aba.rows.first) texto(c)];
      final l = aba.rows[1];
      double? n(String c) => numero(l[cab.indexOf(c)]);
      expect(n('Episódios de atenção'), 3);
      expect(n('Episódios de possível crise'), 1);
      expect(n('Crises confirmadas'), 1);
      expect(n('Crises descartadas'), 1);
      expect(n('Crises pendentes de avaliação'), 2);
      expect(segundos(l[cab.indexOf('Tempo total em episódio (h:mm:ss)')]), 48 + 74 + 187 + 95);
      expect(texto(l[cab.indexOf('Gatilho mais frequente')]), 'Barulho (2 de 4)');
      // 07:00-18:00 menos 30 min = 630 minutos com dados
      expect(n('Minutos com dados'), 630);
      expect(n('Cobertura do monitoramento (%)'), closeTo(630 / 1440, 1e-9));
      final minutos = minutosDoDia();
      final bpm = minutos.map((m) => m.sinais[Sinal.bpm]!.media).reduce((a, b) => a + b) / minutos.length;
      expect(n('BPM médio (bpm)'), closeTo(bpm, 1e-9));
    });

    test('Por hora: 24 linhas, medias da hora e episodios iniciados', () {
      final aba = excel.tables['Por hora']!;
      final cab = [for (final c in aba.rows.first) texto(c)];
      expect(aba.rows, hasLength(25));
      final h14 = aba.rows[15];
      expect(texto(h14[cab.indexOf('Hora')]), '14:00–14:59');
      expect(numero(h14[cab.indexOf('Episódios iniciados')]), 1);
      expect(texto(h14[cab.indexOf('Nível máximo')]), 'Possível crise');
      expect(numero(h14[cab.indexOf('Minutos com dados')]), 60);
      final h12 = aba.rows[13];
      expect(numero(h12[cab.indexOf('Minutos com dados')]), 30);
      final h3 = aba.rows[4]; // 03:00, sem dados
      expect(h3[cab.indexOf('BPM médio (bpm)')], isNull);
      expect(numero(h3[cab.indexOf('Minutos com dados')]), 0);
    });
  });

  group('periodo e dia de hoje', () {
    test('periodo: uma linha por dia + total; nome do arquivo com inicio e fim; no maximo 31 dias', () async {
      final banco = await bancoComODia();
      final periodo = PeriodoDoRelatorio(DateTime(2026, 11, 24), dia);
      final dados = await DadosDoRelatorio.doBanco(banco, periodo: periodo, childId: 'C01', agora: DateTime(2026, 11, 26, 8));
      final abas = montarAbas(dados);
      final resumo = abas.first;
      expect(resumo.linhas, hasLength(3));
      expect(resumo.linhas.last.first, 'Período inteiro');
      expect(resumo.linhas[0][1], 0, reason: 'dia 24 sem episodios');
      expect(resumo.linhas[2][1], 3);
      expect(abas.last.linhas, hasLength(48));
      expect(nomeDoArquivo('C01', periodo), 'puzzleband_relatorio_C01_2026-11-24_a_2026-11-25.xlsx');
      expect(() => PeriodoDoRelatorio(DateTime(2026, 10, 1), DateTime(2026, 11, 1)), throwsArgumentError);
      expect(PeriodoDoRelatorio(DateTime(2026, 10, 2), DateTime(2026, 11, 1)).dias, hasLength(31));
    });

    test('hoje: a cobertura conta so os minutos ate agora, e "Por hora" para na hora atual', () async {
      final banco = await bancoComODia();
      final dados = await dadosDoDia(banco, agora: as(10, 0));
      final abas = montarAbas(dados);
      final resumo = abas.first;
      final cab = [for (final c in resumo.colunas) c.titulo];
      // 07:00-10:00 = 180 minutos com dados de 600 minutos do dia ate as
      // 10:00 (minutos "do futuro" no banco nao contam)
      final cobertura = resumo.linhas.single[cab.indexOf('Cobertura do monitoramento (%)')]! as double;
      expect(cobertura, closeTo(180 / 600, 1e-9));
      expect(resumo.linhas.single[cab.indexOf('Minutos com dados')], 180);
      expect(abas.last.linhas, hasLength(11), reason: '00:00 a 10:00');
    });
  });
}
