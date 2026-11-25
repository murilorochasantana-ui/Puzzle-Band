// Metricas dos sinais calculadas na pulseira (docs/mqtt.md):
//   - por episodio, o campo opcional `metricas` de cada episodio do
//     historico (antes, durante e recuperacao);
//   - por minuto, o topico resumo_minuto (media e n de cada sinal, nivel
//     maximo e quantas leituras).
// Parse defensivo, como em models.dart: campo com tipo errado vira null.

import 'models.dart';

/// Os seis sinais do relatorio, com o nome do campo na mensagem e a unidade.
enum Sinal {
  bpm('bpm', 'BPM', 'bpm', 0),
  vfc('hrv_ms', 'VFC', 'ms', 1),
  eda('eda_uS', 'EDA', 'µS', 2),
  movimento('gyro_mag_dps', 'Movimento', 'dps', 1),
  luz('luz_lux', 'Luz', 'lux', 0),
  ruido('ruido_db', 'Ruído', 'dB', 1);

  const Sinal(this.codigo, this.nome, this.unidade, this.casas);

  /// Nome do campo nas mensagens (e no banco).
  final String codigo;
  final String nome;
  final String unidade;

  /// Casas decimais no relatorio.
  final int casas;

  static Sinal? fromCodigo(Object? v) {
    for (final s in Sinal.values) {
      if (s.codigo == v) return s;
    }
    return null;
  }
}

/// Janelas das metricas de um episodio.
enum Fase {
  antes('antes'),
  durante('durante'),
  recuperacao('recuperacao');

  const Fase(this.codigo);

  final String codigo;

  static Fase? fromCodigo(Object? v) {
    for (final f in Fase.values) {
      if (f.codigo == v) return f;
    }
    return null;
  }
}

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

int _n(Object? v) => v is int && v >= 0 ? v : (v is num && v.isFinite && v >= 0 ? v.toInt() : 0);

Map<String, dynamic>? _obj(Object? v) => v is Map<String, dynamic> ? v : null;

/// Um sinal numa janela: media (e, no "durante", minimo e maximo) e quantas
/// leituras validas daquele sinal entraram.
class ValorDoSinal {
  const ValorDoSinal({required this.media, this.minimo, this.maximo, required this.nLeituras});

  final double media;
  final double? minimo;
  final double? maximo;
  final int nLeituras;

  static ValorDoSinal? fromJson(Object? json) {
    final m = _obj(json);
    final media = _num(m?['media']);
    if (m == null || media == null) return null;
    return ValorDoSinal(media: media, minimo: _num(m['min']), maximo: _num(m['max']), nLeituras: _n(m['n']));
  }

  Map<String, dynamic> toJson() => {
        'media': media,
        if (minimo != null) 'min': minimo,
        if (maximo != null) 'max': maximo,
        'n': nLeituras,
      };
}

/// Uma janela (antes, durante ou recuperacao): quantas leituras e o valor de
/// cada sinal (ausente = sem leitura valida).
class JanelaDeMetricas {
  const JanelaDeMetricas({required this.nLeituras, required this.sinais});

  final int nLeituras;
  final Map<Sinal, ValorDoSinal> sinais;

  static JanelaDeMetricas? fromJson(Object? json) {
    final m = _obj(json);
    if (m == null) return null;
    return JanelaDeMetricas(
      nLeituras: _n(m['n_leituras']),
      sinais: {
        for (final s in Sinal.values)
          if (ValorDoSinal.fromJson(m[s.codigo]) case final v?) s: v,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'n_leituras': nLeituras,
        for (final s in Sinal.values) s.codigo: sinais[s]?.toJson(),
      };
}

/// O campo `metricas` de um episodio. Episodio antigo (sem o campo) = null.
class MetricasDoEpisodio {
  const MetricasDoEpisodio(this.fases);

  final Map<Fase, JanelaDeMetricas> fases;

  JanelaDeMetricas? operator [](Fase f) => fases[f];

  bool get vazia => fases.isEmpty;

  static MetricasDoEpisodio? fromJson(Object? json) {
    final m = _obj(json);
    if (m == null) return null;
    final fases = {
      for (final f in Fase.values)
        if (JanelaDeMetricas.fromJson(m[f.codigo]) case final j?) f: j,
    };
    return fases.isEmpty ? null : MetricasDoEpisodio(fases);
  }

  Map<String, dynamic> toJson() => {for (final f in Fase.values) f.codigo: fases[f]?.toJson()};
}

/// Um minuto de `puzzleband/<id>/resumo_minuto`.
class ResumoDoMinuto {
  const ResumoDoMinuto({
    required this.minuto,
    required this.nivelMaximo,
    required this.nLeituras,
    required this.sinais,
  });

  /// Inicio do minuto (UTC, como a pulseira mandou).
  final DateTime minuto;
  final NivelRisco nivelMaximo;
  final int nLeituras;

  /// Media e n de cada sinal (ausente = sem leitura valida no minuto).
  final Map<Sinal, ({double media, int n})> sinais;

  static ResumoDoMinuto? fromJson(Object? json) {
    final m = _obj(json);
    final minuto = m?['minuto'] is String ? DateTime.tryParse(m!['minuto'] as String) : null;
    if (m == null || minuto == null) return null;
    return ResumoDoMinuto(
      minuto: minuto.toUtc(),
      nivelMaximo: NivelRisco.fromCodigo(m['nivel_maximo']) ?? NivelRisco.baixoRisco,
      nLeituras: _n(m['n_leituras']),
      sinais: {
        for (final s in Sinal.values)
          if (ValorDoSinal.fromJson(m[s.codigo]) case final v?) s: (media: v.media, n: v.nLeituras),
      },
    );
  }
}

/// Minutos de uma mensagem resumo_minuto. So a pulseira publica este topico
/// (`"origem": "pulseira"`); outra origem ou JSON invalido = null. Minuto
/// invalido e pulado sem descartar os outros.
List<ResumoDoMinuto>? parseResumoMinuto(String text) {
  final m = decodeObject(text);
  if (m == null || m['origem'] != 'pulseira') return null;
  final lista = m['minutos'];
  if (lista is! List) return null;
  return lista.map(ResumoDoMinuto.fromJson).whereType<ResumoDoMinuto>().toList();
}
