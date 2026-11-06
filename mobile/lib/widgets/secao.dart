import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Superficie de uma secao: tom sobre o fundo, sem sombra nem borda.
class Secao extends StatelessWidget {
  const Secao({super.key, required this.child, this.padding = const EdgeInsets.all(Espaco.l)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: CoresApp.of(context).superficie,
        borderRadius: BorderRadius.circular(Raio.secao),
      ),
      child: child,
    );
  }
}

/// Titulo de secao (caixa normal) com frase de apoio opcional.
class TituloSecao extends StatelessWidget {
  const TituloSecao(this.titulo, {super.key, this.apoio});

  final String titulo;
  final String? apoio;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(titulo, style: texto.titleMedium)),
        if (apoio != null) ...[
          const SizedBox(height: 2),
          Text(apoio!, style: texto.bodySmall),
        ],
      ],
    );
  }
}
