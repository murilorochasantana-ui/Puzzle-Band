// Mensagens recebidas do site (formatos em docs/mqtt.md). Todo parse e
// defensivo: JSON malformado ou campo com tipo errado vira null (a mensagem
// e descartada) - nunca lanca excecao.

import 'dart:convert';

// ---------------------------------------------------------------------------
// Utilitarios de JSON
// ---------------------------------------------------------------------------

Map<String, dynamic>? decodeObject(String text) {
  try {
    final data = jsonDecode(text);
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    return null;
  }
}

String? _str(Object? v) => v is String ? v : null;

String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

Map<String, dynamic>? _obj(Object? v) => v is Map<String, dynamic> ? v : null;

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// Nivel do modelo
// ---------------------------------------------------------------------------

enum NivelRisco {
  baixoRisco('baixo_risco', 0),
  atencao('atencao', 1),
  altoRisco('alto_risco', 2);

  const NivelRisco(this.codigo, this.rank);

  final String codigo;
  final int rank;

  static NivelRisco? fromCodigo(Object? value) {
    for (final n in NivelRisco.values) {
      if (n.codigo == value) return n;
    }
    return null;
  }

  bool get isAlerta => this != NivelRisco.baixoRisco;
}

// ---------------------------------------------------------------------------
// Gatilho (resumido: tipo + texto)
// ---------------------------------------------------------------------------

class Gatilho {
  const Gatilho({this.tipo, required this.texto});

  final String? tipo;
  final String texto;

  static Gatilho? fromJson(Object? json) {
    final m = _obj(json);
    if (m == null) return null;
    final texto = _str(m['texto']) ?? '';
    final tipo = _str(m['tipo']);
    if (texto.isEmpty && tipo == null) return null;
    return Gatilho(tipo: tipo, texto: texto);
  }

  Map<String, dynamic> toJson() => {'tipo': tipo, 'texto': texto};
}

// ---------------------------------------------------------------------------
// puzzleband/<id>/estado
// ---------------------------------------------------------------------------

class Leituras {
  const Leituras({
    this.timestamp,
    this.bpm,
    this.edaUs,
    this.hrvMs,
    this.gyroDps,
    this.regularidade,
    this.luzLux,
    this.ruidoDb,
  });

  final String? timestamp; // da propria leitura (identifica leituras repetidas)
  final double? bpm;
  final double? edaUs;
  final double? hrvMs;
  final double? gyroDps;
  final double? regularidade;
  final double? luzLux;
  final double? ruidoDb;

  static Leituras? fromJson(Object? json) {
    final m = _obj(json);
    if (m == null) return null;
    return Leituras(
      timestamp: _str(m['timestamp']),
      bpm: _num(m['bpm']),
      edaUs: _num(m['eda_uS']),
      hrvMs: _num(m['hrv_ms']),
      gyroDps: _num(m['gyro_mag_dps']),
      regularidade: _num(m['regularidade']),
      luzLux: _num(m['luz_lux']),
      ruidoDb: _num(m['ruido_db']),
    );
  }
}

class EpisodioAtivo {
  const EpisodioAtivo({required this.id, this.inicio, required this.nivelMaximo, this.vistoEm});

  final String id;
  final DateTime? inicio;
  final NivelRisco nivelMaximo;
  final DateTime? vistoEm;

  static EpisodioAtivo? fromJson(Object? json) {
    final m = _obj(json);
    final id = _nonEmpty(m?['id']);
    if (m == null || id == null) return null;
    return EpisodioAtivo(
      id: id,
      inicio: _date(m['inicio']),
      nivelMaximo: NivelRisco.fromCodigo(m['nivel_maximo']) ?? NivelRisco.atencao,
      vistoEm: _date(m['visto_pelo_cuidador_em']),
    );
  }
}

class EstadoAtual {
  const EstadoAtual({
    this.timestamp,
    required this.fonte,
    required this.nivel,
    this.probabilidade,
    this.leituras,
    this.mediaBpm5min,
    this.gatilho,
    this.episodio,
  });

  final DateTime? timestamp;
  final String fonte; // manual | pulseira
  final NivelRisco nivel;
  final double? probabilidade;
  final Leituras? leituras;
  final double? mediaBpm5min;
  final Gatilho? gatilho;
  final EpisodioAtivo? episodio;

  static EstadoAtual? tryParse(String text) {
    final m = decodeObject(text);
    if (m == null) return null;
    final nivel = NivelRisco.fromCodigo(m['nivel']);
    if (nivel == null) return null;
    return EstadoAtual(
      timestamp: _date(m['timestamp']),
      fonte: _str(m['fonte']) ?? 'desconhecida',
      nivel: nivel,
      probabilidade: _num(m['probabilidade']),
      leituras: Leituras.fromJson(m['leituras']),
      mediaBpm5min: _num(m['media_bpm_5min']),
      gatilho: Gatilho.fromJson(m['gatilho']),
      episodio: EpisodioAtivo.fromJson(m['episodio']),
    );
  }
}

// ---------------------------------------------------------------------------
// puzzleband/<id>/alertas
// ---------------------------------------------------------------------------

class Alerta {
  const Alerta({
    this.episodioId,
    this.nivelAnterior,
    required this.nivel,
    this.probabilidade,
    this.gatilho,
    this.timestamp,
    this.fonte,
  });

  final String? episodioId;
  final NivelRisco? nivelAnterior;
  final NivelRisco nivel;
  final double? probabilidade;
  final Gatilho? gatilho;
  final DateTime? timestamp;
  final String? fonte;

  static Alerta? tryParse(String text) {
    final m = decodeObject(text);
    if (m == null) return null;
    final nivel = NivelRisco.fromCodigo(m['nivel']);
    if (nivel == null) return null;
    return Alerta(
      episodioId: _nonEmpty(m['episodio_id']),
      nivelAnterior: NivelRisco.fromCodigo(m['nivel_anterior']),
      nivel: nivel,
      probabilidade: _num(m['probabilidade']),
      gatilho: Gatilho.fromJson(m['gatilho']),
      timestamp: _date(m['timestamp']),
      fonte: _str(m['fonte']),
    );
  }
}

// ---------------------------------------------------------------------------
// puzzleband/<id>/historico
// ---------------------------------------------------------------------------

enum Avaliacao {
  pendente('pendente'),
  confirmado('confirmado'),
  descartado('descartado');

  const Avaliacao(this.codigo);

  final String codigo;

  static Avaliacao fromCodigo(Object? value) {
    for (final a in Avaliacao.values) {
      if (a.codigo == value) return a;
    }
    return Avaliacao.pendente;
  }
}

class Episodio {
  const Episodio({
    required this.id,
    this.crianca,
    this.fonte,
    required this.inicio,
    this.fim,
    this.duracaoS,
    this.encerramento,
    required this.nivelMaximo,
    this.probabilidadeMaxima,
    this.gatilho,
    this.avaliacao = Avaliacao.pendente,
    this.observacao = '',
    this.avaliacaoOrigem,
    this.avaliacaoEm,
    this.vistoEm,
  });

  final String id;
  final String? crianca;
  final String? fonte; // manual | pulseira
  final DateTime inicio;
  final DateTime? fim;
  final double? duracaoS;
  final String? encerramento; // null = em andamento | normalizou | interrompido
  final NivelRisco nivelMaximo;
  final double? probabilidadeMaxima;
  final Gatilho? gatilho;
  final Avaliacao avaliacao;
  final String observacao;
  final String? avaliacaoOrigem; // site | app
  final DateTime? avaliacaoEm;
  final DateTime? vistoEm;

  bool get emAndamento => encerramento == null;

  static Episodio? fromJson(Object? json) {
    final m = _obj(json);
    if (m == null) return null;
    final id = _nonEmpty(m['id']);
    final inicio = _date(m['inicio']);
    final nivel = NivelRisco.fromCodigo(m['nivel_maximo']);
    if (id == null || inicio == null || nivel == null) return null;
    return Episodio(
      id: id,
      crianca: _str(m['crianca']),
      fonte: _str(m['fonte']),
      inicio: inicio,
      fim: _date(m['fim']),
      duracaoS: _num(m['duracao_s']),
      encerramento: _str(m['encerramento']),
      nivelMaximo: nivel,
      probabilidadeMaxima: _num(m['probabilidade_maxima']),
      gatilho: Gatilho.fromJson(m['gatilho']),
      avaliacao: Avaliacao.fromCodigo(m['avaliacao_cuidador']),
      observacao: _str(m['observacao']) ?? '',
      avaliacaoOrigem: _str(m['avaliacao_origem']),
      avaliacaoEm: _date(m['avaliacao_em']),
      vistoEm: _date(m['visto_pelo_cuidador_em']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'crianca': crianca,
        'fonte': fonte,
        'inicio': _iso(inicio),
        'fim': _iso(fim),
        'duracao_s': duracaoS,
        'encerramento': encerramento,
        'nivel_maximo': nivelMaximo.codigo,
        'probabilidade_maxima': probabilidadeMaxima,
        'gatilho': gatilho?.toJson(),
        'avaliacao_cuidador': avaliacao.codigo,
        'observacao': observacao,
        'avaliacao_origem': avaliacaoOrigem,
        'avaliacao_em': _iso(avaliacaoEm),
        'visto_pelo_cuidador_em': _iso(vistoEm),
      };

  /// Copia com a avaliacao feita neste app (antes de o site confirmar).
  Episodio avaliadoPeloApp(Avaliacao nova, String obs, DateTime quando) => Episodio(
        id: id,
        crianca: crianca,
        fonte: fonte,
        inicio: inicio,
        fim: fim,
        duracaoS: duracaoS,
        encerramento: encerramento,
        nivelMaximo: nivelMaximo,
        probabilidadeMaxima: probabilidadeMaxima,
        gatilho: gatilho,
        avaliacao: nova,
        observacao: obs,
        avaliacaoOrigem: 'app',
        avaliacaoEm: quando,
        vistoEm: vistoEm,
      );
}

/// Lista de episodios (mais recente primeiro). Itens invalidos sao pulados
/// sem descartar a lista inteira.
List<Episodio>? parseHistorico(String text) {
  final m = decodeObject(text);
  final lista = m?['episodios'];
  if (lista is! List) return null;
  final episodios = lista.map(Episodio.fromJson).whereType<Episodio>().toList();
  episodios.sort((a, b) => b.inicio.compareTo(a.inicio));
  return episodios;
}

/// So a pulseira publica o historico (`"origem": "pulseira"`). Uma lista de
/// outra origem (ex.: uma aba antiga do site, de quando ele era o
/// "servidor", republicando o localStorage) e ignorada: ela sobrescreveria o
/// historico da pulseira com episodios velhos.
bool historicoDaPulseira(String text) => decodeObject(text)?['origem'] == 'pulseira';

/// Ordem do terminal em `puzzleband/<id>/comando` (npm run resetar):
/// `{"acao": "resetar", "id", "timestamp", "manter_preferencias"}`. Sem
/// `manter_preferencias` (ou com valor que nao e booleano), vale true.
class ComandoResetar {
  const ComandoResetar({required this.id, required this.manterPreferencias, this.timestamp});

  final String id;
  final bool manterPreferencias;
  final DateTime? timestamp;

  static ComandoResetar? tryParse(String text) {
    final m = decodeObject(text);
    if (m == null || m['acao'] != 'resetar') return null;
    final id = _nonEmpty(m['id'])?.trim();
    if (id == null) return null;
    return ComandoResetar(
      id: id,
      manterPreferencias: m['manter_preferencias'] != false,
      timestamp: _date(m['timestamp']),
    );
  }
}

/// Confirmacao em `puzzleband/<id>/comando/resposta`.
String respostaDoComando(String id) => jsonEncode({'id': id, 'status': 'aplicado'});

/// Status de presenca (pulseira e app): texto puro "online" | "offline".
bool? parseOnline(String text) {
  final v = text.trim().toLowerCase();
  if (v == 'online') return true;
  if (v == 'offline') return false;
  return null;
}
