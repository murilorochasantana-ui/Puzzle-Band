import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Indicador pequeno da avaliacao do cuidador no cartao resumido do
/// Historico. Nunca se confunde com o selo do NIVEL do modelo (pilula cheia,
/// tingida, "Atenção" / "Possível crise"):
///   - pendente: pilula so com contorno azul, ampulheta e o texto
///     "Possível crise · a confirmar" (nunca "Possível crise" sozinho);
///   - confirmado: icone + "Confirmado", sem pilula, na cor do texto (o azul
///     fica so para o que ainda pede acao);
///   - descartado: pilula cheia vermelho tijolo com icone + "Descartado",
///     como o botao escolhido.
/// Tres formas diferentes, para nao depender so da cor (nem no escuro).
class SeloAvaliacao extends StatelessWidget {
  const SeloAvaliacao({super.key, required this.avaliacao, this.onConfirmar});

  final Avaliacao avaliacao;

  /// So no pendente: tocar abre o cartao ja nos botoes de avaliacao.
  final VoidCallback? onConfirmar;

  static const textoPendente = 'Possível crise · a confirmar';

  /// Frase para o leitor de tela.
  static String fala(Avaliacao a) => switch (a) {
        Avaliacao.pendente => 'Possível crise aguardando sua confirmação',
        Avaliacao.confirmado => 'Crise confirmada',
        Avaliacao.descartado => 'Descartado',
      };

  static IconData icone(Avaliacao a) => switch (a) {
        Avaliacao.pendente => Icons.hourglass_top_rounded,
        Avaliacao.confirmado => Icons.check_circle_rounded,
        Avaliacao.descartado => Icons.block_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final dados = CoresDados.of(context);
    final estilo = Theme.of(context).textTheme.labelMedium!;

    Widget conteudo(Color cor, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone(avaliacao), size: 18, color: cor),
            const SizedBox(width: Espaco.xs),
            Flexible(child: Text(texto, style: estilo.copyWith(color: cor))),
          ],
        );

    const preenchimento = EdgeInsets.symmetric(horizontal: 10, vertical: Espaco.xs);
    final Widget selo = switch (avaliacao) {
      Avaliacao.pendente => Container(
          padding: preenchimento,
          decoration: ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: dados.pendente, width: 1.5)),
          ),
          child: conteudo(dados.pendente, textoPendente),
        ),
      Avaliacao.confirmado => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espaco.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone(avaliacao), size: 18, color: cores.tinta),
              const SizedBox(width: Espaco.xs),
              Flexible(child: Text('Confirmado', style: estilo.copyWith(color: cores.tinta))),
            ],
          ),
        ),
      Avaliacao.descartado => Container(
          padding: preenchimento,
          decoration: ShapeDecoration(color: dados.descartado.fundo, shape: const StadiumBorder()),
          child: conteudo(dados.descartado.texto, 'Descartado'),
        ),
    };

    final toque = onConfirmar;
    return Semantics(
      container: true,
      label: 'Avaliação: ${fala(avaliacao)}',
      excludeSemantics: true,
      child: toque == null || avaliacao != Avaliacao.pendente
          ? selo
          : Material(
              type: MaterialType.transparency,
              child: InkWell(customBorder: const StadiumBorder(), onTap: toque, child: selo),
            ),
    );
  }
}
