import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import 'cartao_episodio.dart';
import 'gatilho_simples.dart';
import 'lembrete.dart';
import 'nivel_visual.dart';
import 'painel_do_dia.dart';
import 'selo_avaliacao.dart';

/// "14:32–14:34" / "Desde 14:58" / "14:32" (sem fim conhecido).
String faixaDeHorario(Episodio ep) {
  if (ep.emAndamento) return 'Desde ${horaMinuto(ep.inicio)}';
  final fim = fimDoEpisodio(ep);
  return fim == null ? horaMinuto(ep.inicio) : '${horaMinuto(ep.inicio)}–${horaMinuto(fim)}';
}

/// Cartao do Historico. Resumido por padrao, em duas linhas: horario, nivel
/// (icone + texto) e duracao; gatilho em linguagem simples e a avaliacao.
/// Tocar expande no lugar (sem animacao com "reduzir movimento") e mostra o
/// texto tecnico do gatilho, a probabilidade maxima, o "Estou ciente", o
/// lembrete, a observacao e os botoes de avaliacao.
class CartaoEpisodioResumido extends StatelessWidget {
  const CartaoEpisodioResumido({
    super.key,
    required this.episodio,
    required this.expandido,
    required this.onAlternar,
    required this.onConfirmar,
    this.chaveBotoes,
  });

  final Episodio episodio;
  final bool expandido;
  final VoidCallback onAlternar;

  /// Selo "Possível crise · a confirmar": abre o cartao ja nos botoes.
  final VoidCallback onConfirmar;

  /// Chave da linha de botoes quando expandido (para rolar ate ela).
  final Key? chaveBotoes;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final ep = episodio;
    final visual = NivelVisual.de(ep.nivelMaximo);
    final duracaoTexto = ep.emAndamento ? 'em andamento' : duracao(ep.duracaoS);
    final (:icone, :manchete) = mancheteDoGatilho(ep.gatilho, emAndamento: ep.emAndamento);
    final fala = [
      '${horarioDoEpisodio(ep)}.',
      'Nível: ${visual.rotulo}.',
      if (!ep.emAndamento) 'Duração: $duracaoTexto.',
      '$manchete.',
      'Avaliação: ${SeloAvaliacao.fala(ep.avaliacao)}.',
    ].join(' ');

    final resumo = Semantics(
      container: true,
      button: true,
      expanded: expandido,
      label: fala,
      hint: expandido ? 'Toque para recolher' : 'Toque para ver os detalhes e avaliar',
      excludeSemantics: true,
      onTap: onAlternar,
      child: InkWell(
        onTap: onAlternar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.m, Espaco.s, Espaco.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Espaco.m,
                      runSpacing: Espaco.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(faixaDeHorario(ep), style: texto.titleSmall!.copyWith(fontFeatures: Tipografia.tabular)),
                        SeloNivel(visual),
                        Text(duracaoTexto, style: texto.bodySmall),
                      ],
                    ),
                    const SizedBox(height: Espaco.s),
                    Wrap(
                      spacing: Espaco.m,
                      runSpacing: Espaco.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icone, size: 20, color: cores.tintaSuave),
                            const SizedBox(width: Espaco.s),
                            Flexible(child: Text(manchete, style: texto.bodyMedium)),
                          ],
                        ),
                        SeloAvaliacao(avaliacao: ep.avaliacao, onConfirmar: onConfirmar),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espaco.xs),
              AnimatedRotation(
                turns: expandido ? 0.5 : 0,
                duration: Movimento.de(context, Movimento.medio),
                curve: Movimento.curva,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.expand_more_rounded, color: cores.tinta),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: cores.superficie, borderRadius: BorderRadius.circular(Raio.secao)),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            resumo,
            TamanhoAnimado(
              child: expandido
                  ? _Detalhes(ep: ep, chaveBotoes: chaveBotoes)
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detalhes extends StatelessWidget {
  const _Detalhes({required this.ep, this.chaveBotoes});

  final Episodio ep;
  final Key? chaveBotoes;

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final preferencias = PreferenciasScope.of(context);
    final ciente = ep.vistoEm ?? service.cienteEm(ep.id);
    final chave = PreferenciasLocais.chaveEpisodio(ep.id);
    final lembrete = preferencias.lembrete(chave);
    final interrompido = ep.encerramento == 'interrompido';

    void abrirEditor() => editarLembrete(
          context,
          chave: chave,
          titulo: 'Lembrete deste episódio',
          tituloDoAviso: 'Lembrete do episódio das ${horaMinuto(ep.inicio)}',
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaco.l, 0, Espaco.l, Espaco.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: Espaco.m),
          GatilhoSimples(gatilho: ep.gatilho, emAndamento: ep.emAndamento),
          const SizedBox(height: Espaco.m),
          if (ep.probabilidadeMaxima != null) ...[
            LinhaInfo(
              icone: Icons.insights_rounded,
              texto: 'Probabilidade máxima: ${(ep.probabilidadeMaxima! * 100).round()}%.',
            ),
            const SizedBox(height: Espaco.xs),
          ],
          LinhaInfo(
            icone: Icons.sensors_rounded,
            texto: 'Fonte: ${rotuloFonte(ep.fonte).toLowerCase()}.${interrompido ? ' Interrompido.' : ''}',
          ),
          const SizedBox(height: Espaco.xs),
          LinhaInfo(
            icone: Icons.visibility_outlined,
            texto: ciente != null
                ? 'Alerta visto pelo cuidador às ${horaMinuto(ciente)}.'
                : 'O alerta não foi marcado com "Estou ciente".',
          ),
          const SizedBox(height: Espaco.s),
          if (lembrete != null) ...[
            LinhaLembrete(lembrete: lembrete, agora: relogio()),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: abrirEditor,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar lembrete'),
              ),
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: abrirEditor,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar lembrete'),
              ),
            ),
          const SizedBox(height: Espaco.s),
          AvaliacaoEpisodio(episodio: ep, chaveBotoes: chaveBotoes),
        ],
      ),
    );
  }
}
