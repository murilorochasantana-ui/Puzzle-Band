import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dois botoes lado a lado quando os rotulos cabem inteiros; um embaixo do
/// outro (largura total) quando nao cabem - por exemplo com a fonte do
/// sistema ampliada. Nenhum rotulo e cortado.
class BotoesAdaptaveis extends StatelessWidget {
  const BotoesAdaptaveis({super.key, required this.rotulos, required this.botoes});

  /// Rotulos dos botoes, na mesma ordem, so para medir.
  final List<String> rotulos;
  final List<Widget> botoes;

  // icone (20) + espaco (8) + padding horizontal (2 x 20) + folga
  static const _extra = 20 + 8 + 40 + 8;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelLarge!;
    final escala = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, restricoes) {
        final larguraCada = (restricoes.maxWidth - Espaco.s * (botoes.length - 1)) / botoes.length;
        final cabem = rotulos.every((r) {
          final medida = TextPainter(
            text: TextSpan(text: r, style: estilo),
            textDirection: TextDirection.ltr,
            textScaler: escala,
            maxLines: 1,
          )..layout();
          final largura = medida.width + _extra;
          medida.dispose();
          return largura <= larguraCada;
        });
        if (cabem) {
          return Row(
            children: [
              for (var i = 0; i < botoes.length; i++) ...[
                if (i > 0) const SizedBox(width: Espaco.s),
                Expanded(child: botoes[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < botoes.length; i++) ...[
              if (i > 0) const SizedBox(height: Espaco.s),
              botoes[i],
            ],
          ],
        );
      },
    );
  }
}
