import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Manchete em linguagem simples a partir do `gatilho.tipo` que o site ja
/// envia (docs/gatilho.md). O texto tecnico do site aparece logo abaixo. A
/// manchete sempre diz "provavel": a regra nao afirma causa.
({IconData icone, String manchete}) mancheteDoGatilho(Gatilho? gatilho, {bool emAndamento = false}) {
  if (gatilho == null) {
    return (
      icone: Icons.hourglass_empty_rounded,
      manchete: emAndamento ? 'Gatilho ainda em cálculo' : 'Gatilho não calculado',
    );
  }
  return switch (gatilho.tipo) {
    'ruido' => (icone: Icons.volume_up_outlined, manchete: 'Provável gatilho: barulho'),
    'luminosidade' => (icone: Icons.light_mode_outlined, manchete: 'Provável gatilho: luz forte ou piscando'),
    'ruido_e_luminosidade' => (icone: Icons.volume_up_outlined, manchete: 'Provável gatilho: barulho e luz'),
    'nenhum_ambiental' => (icone: Icons.do_not_disturb_on_outlined, manchete: 'Som e luz não mudaram'),
    _ => (icone: Icons.info_outline_rounded, manchete: 'Provável gatilho'),
  };
}

/// Icone + manchete + texto tecnico do gatilho.
class GatilhoSimples extends StatelessWidget {
  const GatilhoSimples({super.key, required this.gatilho, this.emAndamento = false, this.larguraDoIcone = 24});

  final Gatilho? gatilho;
  final bool emAndamento;

  /// Coluna do icone (o icone fica centrado nela): alinha o texto com outras
  /// linhas de icone + texto do mesmo cartao.
  final double larguraDoIcone;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final (:icone, :manchete) = mancheteDoGatilho(gatilho, emAndamento: emAndamento);
    final detalhe = gatilho?.texto.trim() ?? '';
    return Semantics(
      container: true,
      label: detalhe.isEmpty ? manchete : '$manchete. $detalhe',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SizedBox(width: larguraDoIcone, child: Icon(icone, size: 24, color: cores.tinta)),
          ),
          const SizedBox(width: Espaco.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manchete, style: texto.titleSmall),
                if (detalhe.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detalhe, style: texto.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
