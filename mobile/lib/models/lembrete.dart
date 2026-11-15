// Lembrete curto do cuidador (de um episodio ou do dia). Fica so neste
// celular, na tabela `lembretes` do banco local (services/banco.dart). O
// toJson/fromJson e o formato antigo do shared_preferences (`lembretes_v1`),
// usado so na importacao unica (services/importacao_antiga.dart). Sem
// Flutter aqui: o esquema do banco e exportado fora do app (drift_dev).

/// Lembrete curto do cuidador, com um aviso opcional no celular (imutavel).
class Lembrete {
  const Lembrete({required this.texto, required this.salvoEm, this.avisarEm});

  final String texto;
  final DateTime salvoEm;
  final DateTime? avisarEm;

  /// Aviso ainda por vir (os passados nao aparecem mais na tela).
  DateTime? avisoPendente(DateTime agora) {
    final aviso = avisarEm;
    return aviso != null && aviso.isAfter(agora) ? aviso : null;
  }

  Map<String, dynamic> toJson() => {
        'texto': texto,
        'salvo_em': salvoEm.toUtc().toIso8601String(),
        if (avisarEm != null) 'avisar_em': avisarEm!.toUtc().toIso8601String(),
      };

  static Lembrete? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final texto = json['texto'];
    final salvo = json['salvo_em'];
    if (texto is! String || texto.trim().isEmpty || salvo is! String) return null;
    final salvoEm = DateTime.tryParse(salvo)?.toLocal();
    if (salvoEm == null) return null;
    final aviso = json['avisar_em'];
    return Lembrete(
      texto: texto,
      salvoEm: salvoEm,
      avisarEm: aviso is String ? DateTime.tryParse(aviso)?.toLocal() : null,
    );
  }
}
