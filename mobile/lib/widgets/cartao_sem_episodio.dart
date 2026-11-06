import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'cartao_episodio.dart';
import 'nivel_visual.dart';

/// No lugar do cartao do episodio quando nao ha episodio em andamento: diz
/// isso e resume o ultimo episodio real do historico (nivel maximo, quando,
/// duracao, avaliacao). Tocar abre o detalhe do episodio. Sem sombra: nao e
/// uma peca "ao vivo".
class CartaoSemEpisodio extends StatelessWidget {
  const CartaoSemEpisodio({super.key, required this.ultimo, required this.agora, required this.onAbrir});

  /// Episodio mais recente do historico (null: nenhum ainda).
  final Episodio? ultimo;
  final DateTime agora;
  final ValueChanged<String> onAbrir;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final ep = ultimo;

    final cabecalho = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 32, child: Icon(Icons.history_rounded, size: 28, color: cores.tintaSuave)),
        const SizedBox(width: Espaco.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('Nenhum episódio agora', style: texto.titleSmall),
              ),
              const SizedBox(height: 2),
              Text(
                ep != null ? 'Último episódio: ${quandoEm(ep.inicio, agora)}.' : 'Nenhum episódio registrado ainda.',
                style: texto.bodySmall,
              ),
            ],
          ),
        ),
        if (ep != null) Icon(Icons.chevron_right_rounded, color: cores.tintaSuave),
      ],
    );

    if (ep == null) {
      return Semantics(
        container: true,
        label: 'Nenhum episódio agora. Nenhum episódio registrado ainda.',
        excludeSemantics: true,
        child: _superficie(context, cabecalho),
      );
    }

    final visual = NivelVisual.de(ep.nivelMaximo);
    final avaliacao = resumoAvaliacao(ep, cores);
    final duracaoTexto = ep.emAndamento ? 'Em andamento' : 'Duração: ${duracao(ep.duracaoS)}';
    final fala = 'Nenhum episódio agora. Último episódio: ${quandoEm(ep.inicio, agora)}, '
        'nível máximo ${visual.rotulo}. $duracaoTexto. ${avaliacao.frase}';

    void abrir() => onAbrir(ep.id);

    return Semantics(
      container: true,
      button: true,
      label: fala,
      hint: 'Toque para ver o episódio',
      excludeSemantics: true,
      onTap: abrir,
      child: _superficie(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cabecalho,
            const SizedBox(height: Espaco.m),
            Padding(
              padding: const EdgeInsets.only(left: 32 + Espaco.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Espaco.m,
                    runSpacing: Espaco.s,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SeloNivel(visual),
                      Text(duracaoTexto, style: texto.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: Espaco.s),
                  Row(
                    children: [
                      Icon(avaliacao.icone, size: 20, color: avaliacao.cor),
                      const SizedBox(width: Espaco.s),
                      Expanded(child: Text(avaliacao.frase, style: texto.bodyMedium)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: abrir,
      ),
    );
  }

  Widget _superficie(BuildContext context, Widget filho, {VoidCallback? onTap}) {
    final borda = BorderRadius.circular(Raio.secao);
    return Material(
      color: CoresApp.of(context).superficie,
      borderRadius: borda,
      child: InkWell(
        onTap: onTap,
        borderRadius: borda,
        child: Padding(padding: const EdgeInsets.fromLTRB(Espaco.l, 20, Espaco.l, 20), child: filho),
      ),
    );
  }
}
