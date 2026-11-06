import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Estado vazio: diz o que ainda nao chegou e o que fazer para chegar.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio({super.key, required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final estilos = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$titulo. $texto',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Espaco.xl, horizontal: Espaco.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: cores.superficieAlta, shape: BoxShape.circle),
              child: Icon(icone, size: 28, color: cores.tintaSuave),
            ),
            const SizedBox(height: Espaco.m),
            Text(titulo, textAlign: TextAlign.center, style: estilos.titleSmall),
            const SizedBox(height: Espaco.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(texto, textAlign: TextAlign.center, style: estilos.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
