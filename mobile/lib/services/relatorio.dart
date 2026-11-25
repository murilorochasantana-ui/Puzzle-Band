// Relatorio em Excel para o cuidador (docs/app.md, "Relatorio em Excel"):
// um dia (padrao: hoje) ou um periodo de ate 31 dias, no fuso do celular,
// com tres abas:
//   - "Resumo do dia": uma linha por dia (e o total do periodo): episodios
//     por nivel, avaliacoes, tempo em episodio, gatilho mais frequente, media
//     de cada sinal (do resumo de cada minuto) e a cobertura do
//     monitoramento;
//   - "Episodios": uma linha por episodio, com as metricas dos sinais antes,
//     durante (media e pico) e na recuperacao (celula vazia sem metricas);
//   - "Por hora": media de cada sinal e episodios por hora.
// Le so o banco local (banco.dart); nada sai do celular ate o cuidador
// compartilhar o arquivo.

import 'dart:io';

import '../models/lembrete.dart';
import '../models/metricas.dart';
import '../models/models.dart';
import 'banco.dart';
import 'planilha_xlsx.dart';

/// Periodo maximo de um relatorio.
const maxDiasDoRelatorio = 31;

/// Dias inteiros do relatorio, no fuso do celular: de [primeiro] ate
/// [ultimo] (inclusive).
class PeriodoDoRelatorio {
  PeriodoDoRelatorio(DateTime primeiro, DateTime ultimo)
      : primeiro = DateTime(primeiro.year, primeiro.month, primeiro.day),
        ultimo = DateTime(ultimo.year, ultimo.month, ultimo.day) {
    if (this.ultimo.isBefore(this.primeiro)) throw ArgumentError('O fim vem antes do início.');
    if (dias.length > maxDiasDoRelatorio) throw ArgumentError('No máximo $maxDiasDoRelatorio dias.');
  }

  PeriodoDoRelatorio.dia(DateTime dia) : this(dia, dia);

  final DateTime primeiro;
  final DateTime ultimo;

  /// Inicio (meia-noite) de cada dia. Pelo calendario, nao por 24 h: um dia
  /// com mudanca de horario continua sendo um dia.
  List<DateTime> get dias => [
        for (var d = primeiro; !d.isAfter(ultimo); d = DateTime(d.year, d.month, d.day + 1)) d,
      ];

  DateTime get inicio => primeiro;
  DateTime get fim => DateTime(ultimo.year, ultimo.month, ultimo.day + 1);
  bool get umDia => primeiro == ultimo;
}

String _dois(int n) => n.toString().padLeft(2, '0');
String _dataIso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';

/// `puzzleband_relatorio_<CHILD_ID>_<AAAA-MM-DD>.xlsx`, ou
/// `..._<inicio>_a_<fim>.xlsx` para um periodo.
String nomeDoArquivo(String childId, PeriodoDoRelatorio p) {
  final id = childId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final datas = p.umDia ? _dataIso(p.primeiro) : '${_dataIso(p.primeiro)}_a_${_dataIso(p.ultimo)}';
  return 'puzzleband_relatorio_${id}_$datas.xlsx';
}

/// O que o relatorio le do banco.
class DadosDoRelatorio {
  const DadosDoRelatorio({
    required this.periodo,
    required this.childId,
    required this.geradoEm,
    required this.episodios,
    required this.metricas,
    required this.minutos,
    required this.lembretes,
  });

  final PeriodoDoRelatorio periodo;
  final String childId;

  /// Agora: o dia de hoje so conta ate aqui (cobertura).
  final DateTime geradoEm;

  /// Episodios com inicio no periodo, do mais antigo para o mais novo.
  final List<Episodio> episodios;
  final Map<String, MetricasDoEpisodio> metricas;
  final List<ResumoDoMinuto> minutos;

  /// Lembretes por chave (`episodio:<id>`).
  final Map<String, Lembrete> lembretes;

  static Future<DadosDoRelatorio> doBanco(
    BancoPuzzleBand banco, {
    required PeriodoDoRelatorio periodo,
    required String childId,
    required DateTime agora,
  }) async {
    final episodios = (await banco.episodiosEntre(periodo.inicio, periodo.fim)).reversed.toList();
    return DadosDoRelatorio(
      periodo: periodo,
      childId: childId,
      geradoEm: agora,
      episodios: episodios,
      metricas: await banco.metricasDe([for (final e in episodios) e.id]),
      minutos: await banco.resumosEntre(periodo.inicio.toUtc(), periodo.fim.toUtc()),
      lembretes: await banco.lembretesSalvos(),
    );
  }
}

// ---------------------------------------------------------------------------
// Textos
// ---------------------------------------------------------------------------

String rotuloDoNivel(NivelRisco n) => switch (n) {
      NivelRisco.altoRisco => 'Possível crise',
      NivelRisco.atencao => 'Atenção',
      NivelRisco.baixoRisco => 'Calmo',
    };

String rotuloDaAvaliacao(Avaliacao a) => switch (a) {
      Avaliacao.confirmado => 'Confirmada',
      Avaliacao.descartado => 'Descartada',
      Avaliacao.pendente => 'Pendente',
    };

String rotuloDoGatilho(String? tipo) => switch (tipo) {
      'ruido' => 'Barulho',
      'luminosidade' => 'Luz',
      'ruido_e_luminosidade' => 'Barulho e luz',
      'nenhum_ambiental' => 'Nenhum (som e luz não mudaram)',
      null => 'Não calculado',
      _ => tipo,
    };

String _situacao(Episodio e) => switch (e.encerramento) {
      null => 'Em andamento',
      'interrompido' => 'Interrompido',
      _ => 'Encerrado',
    };

// ---------------------------------------------------------------------------
// Contas
// ---------------------------------------------------------------------------

/// Media ponderada pelo n de cada minuto (null sem dados).
double? _mediaDosMinutos(Iterable<ResumoDoMinuto> minutos, Sinal s) {
  var soma = 0.0;
  var n = 0;
  for (final m in minutos) {
    final v = m.sinais[s];
    if (v == null || v.n <= 0) continue;
    soma += v.media * v.n;
    n += v.n;
  }
  return n == 0 ? null : soma / n;
}

/// Gatilho(s) mais frequente(s); empate = os dois, separados por " / ".
String? _gatilhoMaisFrequente(List<Episodio> episodios) {
  final contagem = <String, int>{};
  for (final e in episodios) {
    final r = rotuloDoGatilho(e.gatilho?.tipo);
    contagem[r] = (contagem[r] ?? 0) + 1;
  }
  if (contagem.isEmpty) return null;
  final maior = contagem.values.reduce((a, b) => a > b ? a : b);
  final empatados = [for (final MapEntry(:key, :value) in contagem.entries) if (value == maior) key];
  return '${empatados.join(' / ')} ($maior de ${episodios.length})';
}

Duration _duracao(Episodio e) => Duration(milliseconds: ((e.duracaoS ?? 0) * 1000).round());

/// Minutos do dia que ja passaram (hoje: ate agora; futuro: 0).
int _minutosDoDia(DateTime dia, DateTime agora) {
  final fim = DateTime(dia.year, dia.month, dia.day + 1);
  final ate = agora.isBefore(fim) ? agora : fim;
  if (!ate.isAfter(dia)) return 0;
  return ate.difference(dia).inMinutes;
}

// ---------------------------------------------------------------------------
// Abas
// ---------------------------------------------------------------------------

const abaResumo = 'Resumo do dia';
const abaEpisodios = 'Episódios';
const abaPorHora = 'Por hora';

String _media(Sinal s) => switch (s) {
      Sinal.bpm => 'BPM médio (bpm)',
      Sinal.vfc => 'VFC média (ms)',
      Sinal.eda => 'EDA média (µS)',
      Sinal.movimento => 'Movimento médio (dps)',
      Sinal.luz => 'Luz média (lux)',
      Sinal.ruido => 'Ruído médio (dB)',
    };

List<Aba> montarAbas(DadosDoRelatorio d) => [_resumo(d), _episodios(d), _porHora(d)];

Aba _resumo(DadosDoRelatorio d) {
  final colunas = [
    const Coluna('Data', largura: 12, formato: Formato.data),
    const Coluna('Episódios de atenção', largura: 12, formato: Formato.inteiro),
    const Coluna('Episódios de possível crise', largura: 14, formato: Formato.inteiro),
    const Coluna('Crises confirmadas', largura: 12, formato: Formato.inteiro),
    const Coluna('Crises descartadas', largura: 12, formato: Formato.inteiro),
    const Coluna('Crises pendentes de avaliação', largura: 14, formato: Formato.inteiro),
    const Coluna('Tempo total em episódio (h:mm:ss)', largura: 16, formato: Formato.duracao),
    const Coluna('Gatilho mais frequente', largura: 30),
    for (final s in Sinal.values) Coluna(_media(s), largura: 13, formato: Formato.decimal(s.casas)),
    const Coluna('Cobertura do monitoramento (%)', largura: 16, formato: Formato.porcentagem),
    const Coluna('Minutos com dados', largura: 11, formato: Formato.inteiro),
  ];

  List<Object?> linha(Object rotulo, List<Episodio> eps, List<ResumoDoMinuto> mins, int minutosPossiveis) {
    int conta(bool Function(Episodio) f) => eps.where(f).length;
    // so os minutos que ja comecaram (o relogio da pulseira pode estar um
    // pouco adiantado em relacao ao do celular)
    final comDados = mins.where((m) => m.nLeituras > 0 && m.minuto.isBefore(d.geradoEm)).length;
    return [
      rotulo,
      conta((e) => e.nivelMaximo == NivelRisco.atencao),
      conta((e) => e.nivelMaximo == NivelRisco.altoRisco),
      conta((e) => e.avaliacao == Avaliacao.confirmado),
      conta((e) => e.avaliacao == Avaliacao.descartado),
      conta((e) => e.avaliacao == Avaliacao.pendente),
      eps.fold<Duration>(Duration.zero, (t, e) => t + _duracao(e)),
      _gatilhoMaisFrequente(eps),
      for (final s in Sinal.values) _mediaDosMinutos(mins, s),
      minutosPossiveis == 0 ? null : (comDados / minutosPossiveis).clamp(0.0, 1.0),
      comDados,
    ];
  }

  final linhas = <List<Object?>>[];
  var possiveis = 0;
  for (final dia in d.periodo.dias) {
    final fim = DateTime(dia.year, dia.month, dia.day + 1);
    final eps = [for (final e in d.episodios) if (!e.inicio.isBefore(dia) && e.inicio.isBefore(fim)) e];
    final mins = [
      for (final m in d.minutos)
        if (!m.minuto.toLocal().isBefore(dia) && m.minuto.toLocal().isBefore(fim)) m,
    ];
    final p = _minutosDoDia(dia, d.geradoEm);
    possiveis += p;
    linhas.add(linha(dia, eps, mins, p));
  }
  if (!d.periodo.umDia) linhas.add(linha('Período inteiro', d.episodios, d.minutos, possiveis));
  return Aba(nome: abaResumo, colunas: colunas, linhas: linhas);
}

Aba _episodios(DadosDoRelatorio d) {
  final colunas = [
    const Coluna('Início', largura: 17, formato: Formato.dataHora),
    const Coluna('Fim', largura: 17, formato: Formato.dataHora),
    const Coluna('Duração (h:mm:ss)', largura: 11, formato: Formato.duracao),
    const Coluna('Situação', largura: 13),
    const Coluna('Nível máximo', largura: 14),
    const Coluna('Probabilidade máxima (%)', largura: 13, formato: Formato.porcentagem),
    const Coluna('Provável gatilho', largura: 24),
    const Coluna('Avaliação do cuidador', largura: 13),
    const Coluna('Observação', largura: 30),
    const Coluna('Lembrete', largura: 30),
    for (final s in Sinal.values) ...[
      Coluna('${s.nome} antes (${s.unidade})', largura: 12, formato: Formato.decimal(s.casas)),
      Coluna('${s.nome} durante (${s.unidade})', largura: 12, formato: Formato.decimal(s.casas)),
      Coluna('${s.nome} pico durante (${s.unidade})', largura: 12, formato: Formato.decimal(s.casas)),
      Coluna('${s.nome} recuperação (${s.unidade})', largura: 13, formato: Formato.decimal(s.casas)),
    ],
    const Coluna('Leituras antes', largura: 10, formato: Formato.inteiro),
    const Coluna('Leituras durante', largura: 10, formato: Formato.inteiro),
    const Coluna('Leituras recuperação', largura: 11, formato: Formato.inteiro),
  ];
  final linhas = [
    for (final e in d.episodios)
      () {
        final m = d.metricas[e.id];
        final p = e.probabilidadeMaxima;
        return <Object?>[
          e.inicio,
          e.fim,
          _duracao(e),
          _situacao(e),
          rotuloDoNivel(e.nivelMaximo),
          p?.clamp(0.0, 1.0),
          rotuloDoGatilho(e.gatilho?.tipo),
          rotuloDaAvaliacao(e.avaliacao),
          e.observacao.isEmpty ? null : e.observacao,
          d.lembretes['episodio:${e.id}']?.texto,
          for (final s in Sinal.values) ...[
            m?[Fase.antes]?.sinais[s]?.media,
            m?[Fase.durante]?.sinais[s]?.media,
            m?[Fase.durante]?.sinais[s]?.maximo,
            m?[Fase.recuperacao]?.sinais[s]?.media,
          ],
          m?[Fase.antes]?.nLeituras,
          m?[Fase.durante]?.nLeituras,
          m?[Fase.recuperacao]?.nLeituras,
        ];
      }(),
  ];
  return Aba(nome: abaEpisodios, colunas: colunas, linhas: linhas);
}

Aba _porHora(DadosDoRelatorio d) {
  final colunas = [
    const Coluna('Data', largura: 12, formato: Formato.data),
    const Coluna('Hora', largura: 13),
    const Coluna('Episódios iniciados', largura: 11, formato: Formato.inteiro),
    const Coluna('Nível máximo', largura: 14),
    for (final s in Sinal.values) Coluna(_media(s), largura: 13, formato: Formato.decimal(s.casas)),
    const Coluna('Minutos com dados', largura: 11, formato: Formato.inteiro),
  ];
  // minutos por hora local
  final porHora = <DateTime, List<ResumoDoMinuto>>{};
  for (final m in d.minutos) {
    final l = m.minuto.toLocal();
    porHora.putIfAbsent(DateTime(l.year, l.month, l.day, l.hour), () => []).add(m);
  }
  final linhas = <List<Object?>>[];
  for (final dia in d.periodo.dias) {
    for (var h = 0; h < 24; h++) {
      final hora = DateTime(dia.year, dia.month, dia.day, h);
      if (hora.isAfter(d.geradoEm)) break; // hoje: so ate a hora atual
      if (hora.day != dia.day) continue; // dia com mudanca de horario
      final fim = DateTime(dia.year, dia.month, dia.day, h + 1);
      final mins = porHora[hora] ?? const [];
      final eps = d.episodios.where((e) => !e.inicio.isBefore(hora) && e.inicio.isBefore(fim)).length;
      final nivel = mins.isEmpty ? null : mins.map((m) => m.nivelMaximo).reduce((a, b) => a.rank >= b.rank ? a : b);
      linhas.add([
        dia,
        '${_dois(h)}:00–${_dois(h)}:59',
        eps,
        nivel == null ? null : rotuloDoNivel(nivel),
        for (final s in Sinal.values) _mediaDosMinutos(mins, s),
        mins.where((m) => m.nLeituras > 0).length,
      ]);
    }
  }
  return Aba(nome: abaPorHora, colunas: colunas, linhas: linhas);
}

/// Gera o .xlsx em [pasta] (apaga os relatorios gerados antes, para nao
/// deixar dados de saude parados no celular) e devolve o arquivo.
Future<File> gravarRelatorio(DadosDoRelatorio dados, Directory pasta) async {
  await pasta.create(recursive: true);
  await for (final f in pasta.list()) {
    if (f is File && f.path.endsWith('.xlsx')) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
  final arquivo = File('${pasta.path}${Platform.pathSeparator}${nomeDoArquivo(dados.childId, dados.periodo)}');
  await arquivo.writeAsBytes(gerarXlsx(montarAbas(dados), criadoEm: dados.geradoEm), flush: true);
  return arquivo;
}
