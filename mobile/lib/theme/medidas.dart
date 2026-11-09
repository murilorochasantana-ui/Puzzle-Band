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

/// Linha do BPM na faixa de estado da tela Inicio (widgets/faixa_estado.dart).
abstract final class FaixaBpm {
  /// Entre o coracao e o primeiro algarismo: o mesmo com 1, 2 ou 3 digitos
  /// ou "—".
  static const double espacoCoracao = Espaco.s;

  /// Entre o numero e "bpm".
  static const double espacoUnidade = 6;

  /// Altura do desenho do coracao em relacao a altura dos algarismos.
  static const double proporcaoCoracao = 0.55;

  /// Quanto do quadro do icone (24 x 24) o desenho do coracao ocupa
  /// (Icons.favorite_rounded: 18,35 de altura e 20 de largura).
  static const double coracaoAltura = 18.35 / 24;
  static const double coracaoLargura = 20 / 24;

  /// Entre a area do BPM, a divisoria e a coluna "Ao vivo".
  static const double respiro = Espaco.l;
  static const double divisoria = 1;

  /// Linha "Ao vivo": icone, espaco e o ponto parado.
  static const double iconeAoVivo = 20;
  static const double espacoAoVivo = 6;
  static const double pontoAoVivo = 8;

  /// Entre as linhas da coluna "Ao vivo".
  static const double entreLinhas = 2;
}

/// Calendario do Historico.
abstract final class Calendario {
  /// Lado minimo de um dia (area de toque). Em 393 dp de largura, cada dia
  /// tem 48 dp; num celular de 360 dp, cerca de 45 dp.
  static const double dia = 48;

  /// Bolinha azul de "possivel crise aguardando confirmacao".
  static const double bolinha = 8;

  /// Contorno do dia de hoje e do dia escolhido.
  static const double contornoHoje = 2;
  static const double contornoEscolhido = 3;

  /// Respiro lateral do cartao do calendario (o resto da largura vai para
  /// os dias).
  static const double margem = Espaco.xs;
}

/// Graficos.
abstract final class Grafico {
  /// Altura minima do grafico ao vivo (cresce para o balao caber inteiro).
  static const double aoVivo = 240;

  /// Altura do grafico de 7 dias.
  static const double seteDias = 200;

  /// Linha da serie e marcador do ultimo valor.
  static const double linha = 2;
  static const double marcador = 10;

  /// Periodo das listras de "aguardando confirmacao" (em dp).
  static const double listra = 6;

  /// Distancia do balao ate a borda esquerda do grafico (passa dos rotulos
  /// do eixo Y, que o Syncfusion nao amplia com a fonte).
  static const double margemDoBalao = 56;

  /// Quanto tempo o balao fica na tela depois de tirar o dedo.
  static const Duration balaoVisivel = Duration(seconds: 4);
}
