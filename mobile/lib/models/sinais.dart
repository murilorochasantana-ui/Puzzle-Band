// Sinais do topico `estado` guardados para o grafico ao vivo (ultimos 5
// minutos): todas as leituras da pulseira, a probabilidade e o nivel do
// modelo em cada instante. Funcoes puras, testadas em test/models_test.dart.

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// Uma leitura recebida no estado ao vivo.
@immutable
class AmostraSinais {
  const AmostraSinais({
    required this.hora,
    required this.nivel,
    this.bpm,
    this.edaUs,
    this.hrvMs,
    this.gyroDps,
    this.regularidade,
    this.luzLux,
    this.ruidoDb,
    this.probabilidade,
  });

  /// Quando o app recebeu a leitura.
  final DateTime hora;
  final NivelRisco nivel;
  final double? bpm;
  final double? edaUs;
  final double? hrvMs;
  final double? gyroDps;
  final double? regularidade;
  final double? luzLux;
  final double? ruidoDb;

  /// 0 a 1, como vem do site (null nos primeiros 30 s).
  final double? probabilidade;

  static AmostraSinais de(EstadoAtual e, DateTime hora) {
    final l = e.leituras;
    return AmostraSinais(
      hora: hora,
      nivel: e.nivel,
      bpm: l?.bpm,
      edaUs: l?.edaUs,
      hrvMs: l?.hrvMs,
      gyroDps: l?.gyroDps,
      regularidade: l?.regularidade,
      luzLux: l?.luzLux,
      ruidoDb: l?.ruidoDb,
      probabilidade: e.probabilidade,
    );
  }
}

/// Faixa do eixo Y de uma metrica: o padrao, que cresce (em passos do
/// intervalo) quando o dado sai dela. Faixas fixas nao crescem.
@immutable
class FaixaEixo {
  const FaixaEixo(this.minimo, this.maximo, this.intervalo, {this.fixa = false});

  final double minimo;
  final double maximo;
  final double intervalo;
  final bool fixa;

  /// No maximo 6 divisoes: o intervalo dobra se a faixa crescer muito.
  FaixaEixo ajustada(Iterable<double> valores) {
    if (fixa || valores.isEmpty) return this;
    final menor = valores.reduce(min);
    final maior = valores.reduce(max);
    var passo = intervalo;
    double baixo() => min(minimo, (menor / passo).floor() * passo);
    double alto() => max(maximo, (maior / passo).ceil() * passo);
    while ((alto() - baixo()) / passo > 6) {
      passo *= 2;
    }
    return FaixaEixo(baixo(), alto(), passo);
  }
}

/// As metricas do estado, na ordem do seletor da tela Graficos.
enum Metrica {
  bpm(
    nome: 'Batimentos cardíacos',
    curto: 'BPM',
    unidade: 'bpm',
    casas: 0,
    faixa: FaixaEixo(40, 140, 20),
  ),
  eda(
    nome: 'Suor da pele, EDA',
    curto: 'EDA',
    unidade: 'µS',
    casas: 1,
    faixa: FaixaEixo(0, 12, 2),
  ),
  hrv(
    nome: 'Variabilidade cardíaca, HRV',
    curto: 'HRV',
    unidade: 'ms',
    casas: 0,
    faixa: FaixaEixo(0, 100, 20),
  ),
  movimento(
    nome: 'Movimento',
    curto: 'Movimento',
    unidade: '°/s',
    casas: 1,
    faixa: FaixaEixo(0, 20, 5),
  ),
  regularidade(
    nome: 'Regularidade do movimento',
    curto: 'Regularidade',
    unidade: '',
    unidadeExtensa: '0 a 1',
    casas: 2,
    faixa: FaixaEixo(0, 1, 0.25, fixa: true),
  ),
  luz(
    nome: 'Luz ambiente',
    curto: 'Luz',
    unidade: 'lux',
    casas: 0,
    faixa: FaixaEixo(0, 1000, 250),
  ),
  ruido(
    nome: 'Ruído ambiente',
    curto: 'Ruído',
    unidade: 'dB',
    casas: 0,
    faixa: FaixaEixo(20, 100, 20),
  ),
  probabilidade(
    nome: 'Probabilidade estimada',
    curto: 'Probabilidade',
    unidade: '%',
    casas: 0,
    faixa: FaixaEixo(0, 100, 25, fixa: true),
  );

  const Metrica({
    required this.nome,
    required this.curto,
    required this.unidade,
    this.unidadeExtensa,
    required this.casas,
    required this.faixa,
  });

  /// Nome por extenso (seletor, titulo do eixo, leitor de tela).
  final String nome;

  /// Nome curto (balao do grafico).
  final String curto;

  /// Unidade junto do valor ("128 bpm"); vazia na regularidade (indice).
  final String unidade;

  /// Unidade no seletor quando difere de [unidade] ("0 a 1").
  final String? unidadeExtensa;

  /// Casas decimais mostradas.
  final int casas;
  final FaixaEixo faixa;

  /// "Batimentos cardíacos (bpm)" / "Regularidade do movimento (0 a 1)"
  String get rotulo => '$nome (${unidadeExtensa ?? unidade})';

  /// Valor mostrado (a probabilidade vira porcentagem).
  double? valor(AmostraSinais a) => switch (this) {
        Metrica.bpm => a.bpm,
        Metrica.eda => a.edaUs,
        Metrica.hrv => a.hrvMs,
        Metrica.movimento => a.gyroDps,
        Metrica.regularidade => a.regularidade,
        Metrica.luz => a.luzLux,
        Metrica.ruido => a.ruidoDb,
        Metrica.probabilidade => a.probabilidade == null ? null : a.probabilidade! * 100,
      };
}

/// Ultimos [duracao] de leituras ao vivo, uma amostra por leitura.
class JanelaDeSinais {
  JanelaDeSinais({this.duracao = const Duration(minutes: 5)});

  final Duration duracao;
  final List<AmostraSinais> _amostras = [];
  String? _ultimaLeitura;

  List<AmostraSinais> get amostras => List.unmodifiable(_amostras);

  /// Tira as amostras mais velhas que a janela e, se o estado e ao vivo e
  /// traz leituras, guarda uma amostra. A mesma leitura repetida (site
  /// pausado) nao entra de novo. Devolve true se guardou.
  bool registrar(EstadoAtual estado, DateTime agora, {required bool aoVivo}) {
    _amostras.removeWhere((a) => agora.difference(a.hora) > duracao);
    final leituras = estado.leituras;
    if (!aoVivo || leituras == null) return false;
    final id = leituras.timestamp;
    if (id != null && id == _ultimaLeitura) return false;
    _ultimaLeitura = id;
    _amostras.add(AmostraSinais.de(estado, agora));
    return true;
  }

  /// Esvazia a janela (reset para uma nova apresentacao).
  void limpar() {
    _amostras.clear();
    _ultimaLeitura = null;
  }
}

/// Atual, minima, maxima e media de uma metrica (null sem nenhum valor).
@immutable
class EstatisticaSinal {
  const EstatisticaSinal({required this.atual, required this.minima, required this.maxima, required this.media});

  final double atual;
  final double minima;
  final double maxima;
  final double media;

  static EstatisticaSinal? de(List<AmostraSinais> amostras, Metrica metrica) {
    final valores = amostras.map(metrica.valor).whereType<double>().toList();
    if (valores.isEmpty) return null;
    return EstatisticaSinal(
      atual: valores.last,
      minima: valores.reduce(min),
      maxima: valores.reduce(max),
      media: valores.reduce((a, b) => a + b) / valores.length,
    );
  }
}

/// Trecho continuo em que o nivel do modelo ficou em Atencao ou Possivel
/// crise (faixas de fundo do grafico).
@immutable
class TrechoNivel {
  const TrechoNivel(this.nivel, this.inicio, this.fim);

  final NivelRisco nivel;
  final DateTime inicio;
  final DateTime fim;
}

/// Trechos de Atencao e Possivel crise, na ordem do tempo. Cada trecho vai
/// da primeira amostra no nivel ate a amostra seguinte (ou, no fim da
/// serie, ate a ultima amostra).
List<TrechoNivel> trechosDeNivel(List<AmostraSinais> amostras) {
  final trechos = <TrechoNivel>[];
  NivelRisco? atual;
  DateTime? inicio;
  for (var i = 0; i < amostras.length; i++) {
    final a = amostras[i];
    if (a.nivel == atual) continue;
    if (atual != null && atual.isAlerta) trechos.add(TrechoNivel(atual, inicio!, a.hora));
    atual = a.nivel;
    inicio = a.hora;
  }
  if (atual != null && atual.isAlerta && amostras.isNotEmpty) {
    trechos.add(TrechoNivel(atual, inicio!, amostras.last.hora));
  }
  return trechos;
}
