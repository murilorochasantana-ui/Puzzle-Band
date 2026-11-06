import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Linha informativa (nao tocavel) da probabilidade estimada pelo modelo e da
/// fonte do dado (pulseira ou simulador). Fundo azulado com borda clara,
/// como no modelo do Figma.
class LinhaProbabilidade extends StatelessWidget {
  const LinhaProbabilidade({super.key, required this.estado});

  final EstadoAtual estado;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final prob = estado.probabilidade;
    final titulo = prob != null ? 'Probabilidade estimada: ${(prob * 100).round()}%' : 'Analisando os primeiros 30 s';
    final fonte = 'Fonte: ${rotuloFonte(estado.fonte).toLowerCase()}';
    return Semantics(
      container: true,
      label: '$titulo. $fonte.',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: Toque.principal),
        padding: const EdgeInsets.symmetric(horizontal: Espaco.l, vertical: Espaco.m),
        decoration: BoxDecoration(
          color: cores.informativo,
          borderRadius: BorderRadius.circular(Raio.linha),
          border: Border.all(color: cores.informativoBorda),
        ),
        child: Row(
          children: [
            Icon(Icons.bar_chart_rounded, size: 28, color: cores.primaria),
            const SizedBox(width: Espaco.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: texto.titleSmall),
                  Text(fonte, style: texto.bodyMedium!.copyWith(color: cores.tintaSuave)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
