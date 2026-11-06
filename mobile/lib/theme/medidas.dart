// Espacamentos, raios, areas de toque e movimento (tokens do tema).

import 'package:flutter/widgets.dart';

/// Espacamentos em multiplos de 4 dp.
abstract final class Espaco {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Margem lateral das telas.
  static const double tela = 20;

  /// Entre os blocos principais da tela Inicio (faixa, cartao, linhas).
  static const double bloco = 20;

  /// Largura maxima do conteudo (tablet / celular deitado).
  static const double larguraMaxima = 560;
}

/// Raios em hierarquia (modelo do Figma, docs/figma/home.md): as linhas
/// tocaveis da Inicio sao as pecas mais "macias"; faixa e cartoes, 16.
abstract final class Raio {
  static const double linha = 20;
  static const double faixa = 16;
  static const double secao = 16;
  static const double controle = 12;
  static const double selo = 999;

  /// Logo grande do Login.
  static const double logoGrande = 28;
}

/// Areas de toque (Material / WCAG 2.5.5).
abstract final class Toque {
  static const double minimo = 48;

  /// Acao principal ("Estou ciente").
  static const double principal = 56;
}

/// Movimento: curto e so como resposta a uma mudanca. Com "remover
/// animacoes" ligado no sistema, todas as duracoes viram zero.
abstract final class Movimento {
  static const Duration curto = Duration(milliseconds: 200);
  static const Duration medio = Duration(milliseconds: 300);
  static const Duration entrada = Duration(milliseconds: 400);
  static const Curve curva = Curves.easeOutCubic;

  static bool reduzido(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration de(BuildContext context, Duration duracao) => reduzido(context) ? Duration.zero : duracao;
}

/// AnimatedSize que respeita "remover animacoes": sem movimento, o filho
/// aparece direto (AnimatedSize com duracao zero falha no layout).
class TamanhoAnimado extends StatelessWidget {
  const TamanhoAnimado({super.key, required this.child, this.duracao = Movimento.medio});

  final Widget child;
  final Duration duracao;

  @override
  Widget build(BuildContext context) {
    if (Movimento.reduzido(context)) return child;
    return AnimatedSize(
      duration: duracao,
      curve: Movimento.curva,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
