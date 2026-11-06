import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

enum TipoNivel { calmo, atencao, crise, semDados }

/// Rotulo e icone de cada nivel - sempre texto + icone, nunca so cor. Os
/// icones tem formatos diferentes (circulo com check, triangulo, circulo
/// cheio com "!"), para o nivel ser reconhecido tambem sem a cor.
class NivelVisual {
  const NivelVisual._(this.tipo, this.rotulo, this.icone);

  final TipoNivel tipo;
  final String rotulo;
  final IconData icone;

  static const calmo = NivelVisual._(TipoNivel.calmo, 'Calmo', Icons.check_circle_outline_rounded);
  static const atencao = NivelVisual._(TipoNivel.atencao, 'Atenção', Icons.warning_amber_rounded);
  static const possivelCrise = NivelVisual._(TipoNivel.crise, 'Possível crise', Icons.error_rounded);
  static const semDados = NivelVisual._(TipoNivel.semDados, 'Sem dados', Icons.sensors_off_rounded);

  static NivelVisual de(NivelRisco nivel) => switch (nivel) {
        NivelRisco.baixoRisco => calmo,
        NivelRisco.atencao => atencao,
        NivelRisco.altoRisco => possivelCrise,
      };

  /// Cores do nivel no tema atual (claro ou escuro).
  TomRisco tom(BuildContext context) {
    final cores = CoresApp.of(context);
    return switch (tipo) {
      TipoNivel.calmo => cores.calmo,
      TipoNivel.atencao => cores.atencao,
      TipoNivel.crise => cores.crise,
      TipoNivel.semDados => cores.semDados,
    };
  }
}

/// Selo em pilula com icone + nome do nivel (historico, legendas).
class SeloNivel extends StatelessWidget {
  const SeloNivel(this.visual, {super.key});

  final NivelVisual visual;

  @override
  Widget build(BuildContext context) {
    final tom = visual.tom(context);
    return Semantics(
      container: true,
      label: 'Nível: ${visual.rotulo}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: 6),
        decoration: ShapeDecoration(color: tom.fundo, shape: const StadiumBorder()),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(visual.icone, size: 20, color: tom.texto),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                visual.rotulo,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(color: tom.texto),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
