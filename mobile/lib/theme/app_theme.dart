// ThemeData unico do app (claro e escuro). As telas nao definem cores nem
// tamanhos proprios: usam o ColorScheme, o TextTheme, os temas de componente
// daqui e as cores de `CoresApp`.

import 'package:flutter/material.dart';

import 'cores.dart';
import 'medidas.dart';
import 'tipografia.dart';

export 'cores.dart';
export 'medidas.dart';
export 'tipografia.dart';

abstract final class AppTheme {
  static ThemeData claro() => _tema(Brightness.light, CoresApp.claro);

  static ThemeData escuro() => _tema(Brightness.dark, CoresApp.escuro);

  static ThemeData _tema(Brightness brilho, CoresApp c) {
    final texto = Tipografia.textTheme(tinta: c.tinta, suave: c.tintaSuave);
    final controle = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raio.controle));
    const tamanhoMinimo = Size(Toque.minimo, Toque.minimo);
    const preenchimento = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

    final esquema = ColorScheme(
      brightness: brilho,
      primary: c.primaria,
      onPrimary: c.sobrePrimaria,
      primaryContainer: c.primariaSuave,
      onPrimaryContainer: c.sobrePrimariaSuave,
      secondary: c.tintaSuave,
      onSecondary: c.superficie,
      secondaryContainer: c.superficieAlta,
      onSecondaryContainer: c.tinta,
      tertiary: c.primaria,
      onTertiary: c.sobrePrimaria,
      error: c.crise.texto,
      onError: c.superficie,
      errorContainer: c.crise.fundo,
      onErrorContainer: c.tinta,
      surface: c.fundo,
      onSurface: c.tinta,
      onSurfaceVariant: c.tintaSuave,
      surfaceDim: c.fundo,
      surfaceBright: c.superficie,
      surfaceContainerLowest: c.superficie,
      surfaceContainerLow: c.superficie,
      surfaceContainer: c.superficie,
      surfaceContainerHigh: c.superficieAlta,
      surfaceContainerHighest: c.superficieAlta,
      outline: c.contorno,
      outlineVariant: c.divisoria,
      inverseSurface: c.tinta,
      onInverseSurface: c.fundo,
      inversePrimary: c.primariaSuave,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    OutlineInputBorder borda(Color cor, double largura) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Raio.controle),
          borderSide: BorderSide(color: cor, width: largura),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brilho,
      colorScheme: esquema,
      extensions: [c],
      fontFamily: Tipografia.familia,
      fontFamilyFallback: Tipografia.fallback,
      textTheme: texto,
      scaffoldBackgroundColor: c.fundo,
      canvasColor: c.fundo,
      // Ondulacao simples no toque (sem o efeito "brilho" do InkSparkle)
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: TransicaoCalma(),
          TargetPlatform.iOS: TransicaoCalma(),
          TargetPlatform.linux: TransicaoCalma(),
          TargetPlatform.macOS: TransicaoCalma(),
          TargetPlatform.windows: TransicaoCalma(),
          TargetPlatform.fuchsia: TransicaoCalma(),
        },
      ),
      iconTheme: IconThemeData(color: c.tintaSuave, size: 24),
      dividerTheme: DividerThemeData(color: c.divisoria, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: c.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raio.secao)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primaria,
          foregroundColor: c.sobrePrimaria,
          minimumSize: tamanhoMinimo,
          padding: preenchimento,
          shape: controle,
          textStyle: texto.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.tinta,
          side: BorderSide(color: c.contorno),
          minimumSize: tamanhoMinimo,
          padding: preenchimento,
          shape: controle,
          textStyle: texto.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primaria,
          minimumSize: tamanhoMinimo,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: controle,
          textStyle: texto.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: borda(c.contorno, 1),
        enabledBorder: borda(c.contorno, 1),
        focusedBorder: borda(c.primaria, 2),
        labelStyle: texto.bodyLarge!.copyWith(color: c.tintaSuave),
        floatingLabelStyle: texto.bodyLarge!.copyWith(color: c.primaria),
        hintStyle: texto.bodyLarge!.copyWith(color: c.tintaSuave),
        helperStyle: texto.bodySmall,
        counterStyle: texto.bodySmall,
        prefixIconColor: c.tintaSuave,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Espaco.l),
        minVerticalPadding: Espaco.m,
        minTileHeight: 56,
        iconColor: c.tintaSuave,
        titleTextStyle: texto.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: texto.bodySmall,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.sobrePrimaria : c.contorno,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primaria : c.superficieAlta,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primaria : c.contorno,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.superficie,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 80,
        indicatorColor: c.primariaSuave,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => texto.labelMedium!.copyWith(
            color: s.contains(WidgetState.selected) ? c.tinta : c.tintaSuave,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 24,
            color: s.contains(WidgetState.selected) ? c.sobrePrimariaSuave : c.tintaSuave,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.tinta,
        contentTextStyle: texto.bodyMedium!.copyWith(color: c.fundo),
        actionTextColor: c.primariaSuave,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Raio.controle)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primaria),
      // Editor de lembrete
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.superficie,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.contorno,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Raio.secao)),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.superficie,
        dialBackgroundColor: c.superficieAlta,
        hourMinuteColor: c.superficieAlta,
        hourMinuteTextColor: c.tinta,
        helpTextStyle: texto.labelLarge,
      ),
    );
  }
}

/// Troca de tela com um fade curto; sem animacao se o sistema pede para
/// reduzir movimento.
class TransicaoCalma extends PageTransitionsBuilder {
  const TransicaoCalma();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Movimento.reduzido(context)) return child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Movimento.curva),
      child: child,
    );
  }
}
