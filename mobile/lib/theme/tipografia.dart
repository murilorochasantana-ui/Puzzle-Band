// Atkinson Hyperlegible Next (Braille Institute, licenca OFL), empacotada em
// assets/fonts/ - o app nao depende de internet para a fonte. Escala classica
// (The Elements of Typographic Style): 12, 14, 16, 18, 21, 24, 36, 48, 60.

import 'package:flutter/material.dart';

abstract final class Tipografia {
  static const familia = 'AtkinsonHyperlegibleNext';

  /// Glifos que a fonte nao tem (ex.: a seta "→" do texto do gatilho) vem
  /// da fonte do sistema.
  static const fallback = ['Roboto'];

  static TextTheme textTheme({required Color tinta, required Color suave}) {
    TextStyle s(double tamanho, FontWeight peso, double altura, {Color? cor}) => TextStyle(
          fontFamily: familia,
          fontFamilyFallback: fallback,
          fontSize: tamanho,
          fontWeight: peso,
          height: altura,
          letterSpacing: 0,
          color: cor ?? tinta,
        );

    return TextTheme(
      // BPM ao vivo (o modelo do Figma usa 64; 60 e o degrau da escala)
      displayLarge: s(60, FontWeight.w600, 1.05),
      // BPM ao vivo quando as duas colunas da faixa nao cabem com 60
      displayMedium: s(48, FontWeight.w600, 1.05),
      // Nome do nivel na faixa de estado
      displaySmall: s(36, FontWeight.w700, 1.15),
      headlineLarge: s(36, FontWeight.w700, 1.15),
      headlineMedium: s(24, FontWeight.w700, 1.25),
      // Titulo de tela
      headlineSmall: s(24, FontWeight.w700, 1.25),
      titleLarge: s(21, FontWeight.w600, 1.3),
      // Titulo de secao
      titleMedium: s(18, FontWeight.w600, 1.3),
      titleSmall: s(16, FontWeight.w600, 1.4),
      // Corpo: 16 sp (o padrao do Material 3 e 14)
      bodyLarge: s(16, FontWeight.w400, 1.45),
      bodyMedium: s(16, FontWeight.w400, 1.45),
      // Menor tamanho para texto de leitura
      bodySmall: s(14, FontWeight.w400, 1.4, cor: suave),
      labelLarge: s(16, FontWeight.w600, 1.25),
      labelMedium: s(14, FontWeight.w600, 1.3),
      // So para eixos de grafico
      labelSmall: s(12, FontWeight.w500, 1.3, cor: suave),
    );
  }

  /// Logotipo "PUZZLE BAND" (a unica caixa alta do app: e identidade).
  static TextStyle logotipo(Color cor, {double tamanho = 16}) => TextStyle(
        fontFamily: familia,
        fontSize: tamanho,
        fontWeight: FontWeight.w700,
        letterSpacing: tamanho * 0.16,
        height: 1.2,
        color: cor,
      );

  /// Algarismos de mesma largura, para numeros alinhados em coluna (eixos).
  static const tabular = [FontFeature.tabularFigures()];
}
