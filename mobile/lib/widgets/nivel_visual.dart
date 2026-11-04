import 'package:flutter/material.dart';

import '../models/models.dart';

/// Rotulo, cor e icone de cada nivel - sempre texto + icone, nunca so cor.
class NivelVisual {
  const NivelVisual({
    required this.rotulo,
    required this.cor,
    required this.fundo,
    required this.icone,
  });

  final String rotulo;
  final Color cor;
  final Color fundo;
  final IconData icone;

  static const calmo = NivelVisual(
    rotulo: 'Calmo',
    cor: Color(0xFF2C6302),
    fundo: Color(0xFFE8F5E9),
    icone: Icons.sentiment_satisfied_alt,
  );

  static const atencao = NivelVisual(
    rotulo: 'Atenção',
    cor: Color(0xFFB26A00),
    fundo: Color(0xFFFFF8E1),
    icone: Icons.warning_amber_rounded,
  );

  static const possivelCrise = NivelVisual(
    rotulo: 'Possível crise',
    cor: Color(0xFFC62828),
    fundo: Color(0xFFFFEBEE),
    icone: Icons.error_outline,
  );

  static const semDados = NivelVisual(
    rotulo: 'Sem dados',
    cor: Color(0xFF757575),
    fundo: Color(0xFFF5F5F5),
    icone: Icons.sensors_off,
  );

  static NivelVisual de(NivelRisco nivel) => switch (nivel) {
        NivelRisco.baixoRisco => calmo,
        NivelRisco.atencao => atencao,
        NivelRisco.altoRisco => possivelCrise,
      };
}
