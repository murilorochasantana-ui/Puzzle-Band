// Paleta "Sala calma" (docs/design-app.md): cores pouco saturadas, sem
// vermelho nem amarelo decorativos - essas cores ficam reservadas para os
// niveis de risco. Contrastes WCAG conferidos em docs/design-app.md.

import 'package:flutter/material.dart';

/// Tons de um nivel: texto/icone, fundo tingido e cor de grafico.
@immutable
class TomRisco {
  const TomRisco({required this.texto, required this.fundo, required this.grafico});

  /// Texto e icone do nivel (>= 4.5:1 sobre [fundo] e sobre a superficie).
  final Color texto;

  /// Fundo tingido (faixa de estado, selos).
  final Color fundo;

  /// Barras e marcas de grafico (>= 3:1 sobre a superficie).
  final Color grafico;

  static TomRisco lerp(TomRisco a, TomRisco b, double t) => TomRisco(
        texto: Color.lerp(a.texto, b.texto, t)!,
        fundo: Color.lerp(a.fundo, b.fundo, t)!,
        grafico: Color.lerp(a.grafico, b.grafico, t)!,
      );
}

/// Cores do app, acessiveis por `CoresApp.of(context)` em qualquer tela.
@immutable
class CoresApp extends ThemeExtension<CoresApp> {
  const CoresApp({
    required this.fundo,
    required this.superficie,
    required this.superficieAlta,
    required this.tinta,
    required this.tintaSuave,
    required this.contorno,
    required this.divisoria,
    required this.primaria,
    required this.sobrePrimaria,
    required this.primariaSuave,
    required this.sobrePrimariaSuave,
    required this.calmo,
    required this.atencao,
    required this.crise,
    required this.semDados,
  });

  /// Fundo das telas ("nevoa").
  final Color fundo;

  /// Cartoes e secoes.
  final Color superficie;

  /// Areas de destaque neutras (avisos de conexao, linha de avaliacao).
  final Color superficieAlta;

  /// Texto principal.
  final Color tinta;

  /// Texto secundario.
  final Color tintaSuave;

  /// Contorno de campos e controles (>= 3:1).
  final Color contorno;

  /// Divisorias e linhas de grade (decorativas).
  final Color divisoria;

  /// Cor de acao (azul ardosia, vindo do azul da fita do logo).
  final Color primaria;
  final Color sobrePrimaria;
  final Color primariaSuave;
  final Color sobrePrimariaSuave;

  final TomRisco calmo;
  final TomRisco atencao;
  final TomRisco crise;
  final TomRisco semDados;

  static CoresApp of(BuildContext context) => Theme.of(context).extension<CoresApp>()!;

  /// Fundo do selo do logo nos dois temas: o PNG da fita tem fundo branco.
  static const fundoDoLogo = Color(0xFFFFFFFF);

  static const claro = CoresApp(
    fundo: Color(0xFFF0F3F5),
    superficie: Color(0xFFFFFFFF),
    superficieAlta: Color(0xFFE4E9ED),
    tinta: Color(0xFF1B2A35),
    tintaSuave: Color(0xFF4B5B67),
    contorno: Color(0xFF7A8994),
    divisoria: Color(0xFFD6DDE2),
    primaria: Color(0xFF2D5B86),
    sobrePrimaria: Color(0xFFFFFFFF),
    primariaSuave: Color(0xFFDCE7F2),
    sobrePrimariaSuave: Color(0xFF12324F),
    calmo: TomRisco(texto: Color(0xFF2B6A4E), fundo: Color(0xFFE2F1E9), grafico: Color(0xFF2B9066)),
    atencao: TomRisco(texto: Color(0xFF8A5200), fundo: Color(0xFFFCEFD6), grafico: Color(0xFFC08A00)),
    crise: TomRisco(texto: Color(0xFFA3304F), fundo: Color(0xFFFBE6EC), grafico: Color(0xFFC73E66)),
    semDados: TomRisco(texto: Color(0xFF56636D), fundo: Color(0xFFE6EBEE), grafico: Color(0xFF7A8994)),
  );

  static const escuro = CoresApp(
    fundo: Color(0xFF11181D),
    superficie: Color(0xFF1A232A),
    superficieAlta: Color(0xFF26313A),
    tinta: Color(0xFFE8EEF2),
    tintaSuave: Color(0xFFAEBBC5),
    contorno: Color(0xFF6B7A86),
    divisoria: Color(0xFF2E3A44),
    primaria: Color(0xFF9DC2E6),
    sobrePrimaria: Color(0xFF0E2A44),
    primariaSuave: Color(0xFF23415E),
    sobrePrimariaSuave: Color(0xFFD6E6F5),
    calmo: TomRisco(texto: Color(0xFF8FD3AE), fundo: Color(0xFF16352A), grafico: Color(0xFF3F9E72)),
    atencao: TomRisco(texto: Color(0xFFF3C46B), fundo: Color(0xFF3A2B10), grafico: Color(0xFFB88A1E)),
    crise: TomRisco(texto: Color(0xFFF5A3B6), fundo: Color(0xFF44192A), grafico: Color(0xFFD65C78)),
    semDados: TomRisco(texto: Color(0xFFA7B3BC), fundo: Color(0xFF263038), grafico: Color(0xFF6B7A86)),
  );

  @override
  CoresApp copyWith({
    Color? fundo,
    Color? superficie,
    Color? superficieAlta,
    Color? tinta,
    Color? tintaSuave,
    Color? contorno,
    Color? divisoria,
    Color? primaria,
    Color? sobrePrimaria,
    Color? primariaSuave,
    Color? sobrePrimariaSuave,
    TomRisco? calmo,
    TomRisco? atencao,
    TomRisco? crise,
    TomRisco? semDados,
  }) {
    return CoresApp(
      fundo: fundo ?? this.fundo,
      superficie: superficie ?? this.superficie,
      superficieAlta: superficieAlta ?? this.superficieAlta,
      tinta: tinta ?? this.tinta,
      tintaSuave: tintaSuave ?? this.tintaSuave,
      contorno: contorno ?? this.contorno,
      divisoria: divisoria ?? this.divisoria,
      primaria: primaria ?? this.primaria,
      sobrePrimaria: sobrePrimaria ?? this.sobrePrimaria,
      primariaSuave: primariaSuave ?? this.primariaSuave,
      sobrePrimariaSuave: sobrePrimariaSuave ?? this.sobrePrimariaSuave,
      calmo: calmo ?? this.calmo,
      atencao: atencao ?? this.atencao,
      crise: crise ?? this.crise,
      semDados: semDados ?? this.semDados,
    );
  }

  @override
  CoresApp lerp(ThemeExtension<CoresApp>? other, double t) {
    if (other is! CoresApp) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return CoresApp(
      fundo: c(fundo, other.fundo),
      superficie: c(superficie, other.superficie),
      superficieAlta: c(superficieAlta, other.superficieAlta),
      tinta: c(tinta, other.tinta),
      tintaSuave: c(tintaSuave, other.tintaSuave),
      contorno: c(contorno, other.contorno),
      divisoria: c(divisoria, other.divisoria),
      primaria: c(primaria, other.primaria),
      sobrePrimaria: c(sobrePrimaria, other.sobrePrimaria),
      primariaSuave: c(primariaSuave, other.primariaSuave),
      sobrePrimariaSuave: c(sobrePrimariaSuave, other.sobrePrimariaSuave),
      calmo: TomRisco.lerp(calmo, other.calmo, t),
      atencao: TomRisco.lerp(atencao, other.atencao, t),
      crise: TomRisco.lerp(crise, other.crise, t),
      semDados: TomRisco.lerp(semDados, other.semDados, t),
    );
  }
}
