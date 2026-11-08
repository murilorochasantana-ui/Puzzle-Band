import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'cartao_episodio.dart';
import 'estado_vazio.dart';
import 'gatilho_simples.dart';
import 'lembrete.dart';
import 'nivel_visual.dart';

/// Fim do episodio: o `fim` enviado pela pulseira ou, se vier vazio num episodio
/// encerrado, inicio + duracao.
DateTime? fimDoEpisodio(Episodio ep) {
  if (ep.emAndamento) return null;
  final fim = ep.fim;
  if (fim != null) return fim;
  final segundos = ep.duracaoS;
  if (segundos == null || !segundos.isFinite) return null;
  return ep.inicio.add(Duration(milliseconds: (segundos * 1000).round()));
}

/// "Das 14:32 às 14:34" / "Desde 14:58, em andamento" / "Às 14:32"
String horarioDoEpisodio(Episodio ep) {
  if (ep.emAndamento) return 'Desde ${horaMinuto(ep.inicio)}, em andamento';
  final fim = fimDoEpisodio(ep);
  if (fim == null) return 'Às ${horaMinuto(ep.inicio)}';
  return 'Das ${horaMinuto(ep.inicio)} às ${horaMinuto(fim)}';
}

/// Botao "Hoje: X episódios" que abre ali mesmo o relatorio do dia: o
/// lembrete do dia e todos os episodios de hoje, do mais recente para o mais
/// antigo. Tocar num episodio abre o detalhe; tocar de novo no botao recolhe.
class PainelDoDia extends StatefulWidget {
  const PainelDoDia({super.key, required this.episodios, required this.agora, required this.onAbrirEpisodio});

  /// Episodios de hoje, o mais recente primeiro.
  final List<Episodio> episodios;
  final DateTime agora;
  final ValueChanged<String> onAbrirEpisodio;

  @override
  State<PainelDoDia> createState() => _PainelDoDiaState();
}

class _PainelDoDiaState extends State<PainelDoDia> {
  bool _aberto = false;

  void _alternar() => setState(() => _aberto = !_aberto);

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final rotulo = 'Hoje: ${contarEpisodios(widget.episodios.length)}';
    final borda = BorderRadius.circular(Raio.linha);

    final botao = Semantics(
      container: true,
      button: true,
      expanded: _aberto,
      label: rotulo,
      hint: _aberto ? 'Toque para recolher' : 'Toque para ver os episódios de hoje',
      excludeSemantics: true,
      onTap: _alternar,
      child: InkWell(
        onTap: _alternar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Toque.principal),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espaco.l, vertical: Espaco.m),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 28, color: cores.primaria),
                const SizedBox(width: Espaco.l),
                Expanded(child: Text(rotulo, style: texto.titleSmall)),
                const SizedBox(width: Espaco.s),
                AnimatedRotation(
                  turns: _aberto ? 0.25 : 0,
                  duration: Movimento.de(context, Movimento.medio),
                  curve: Movimento.curva,
                  child: Icon(Icons.chevron_right_rounded, color: cores.tinta),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cores.superficie,
        borderRadius: borda,
        // Controle: contorno com 3:1 sobre o fundo (WCAG 1.4.11)
        border: Border.all(color: cores.contorno),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            botao,
            TamanhoAnimado(
              child: _aberto ? _Conteudo(widget: widget) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({required this.widget});

  final PainelDoDia widget;

  @override
  Widget build(BuildContext context) {
    final preferencias = PreferenciasScope.of(context);
    final episodios = widget.episodios;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.m, Espaco.l, Espaco.m),
          child: _LembreteDoDia(
            lembrete: preferencias.lembrete(PreferenciasLocais.chaveDia(widget.agora)),
            agora: widget.agora,
          ),
        ),
        if (episodios.isEmpty) ...[
          const Divider(indent: Espaco.l, endIndent: Espaco.l),
          const EstadoVazio(
            icone: Icons.event_available_rounded,
            titulo: 'Nenhum episódio hoje',
            texto: 'Quando a pulseira detectar sinais de atenção ou de possível crise, '
                'o episódio aparece aqui.',
          ),
        ] else
          for (final ep in episodios) ...[
            const Divider(indent: Espaco.l, endIndent: Espaco.l),
            _RelatorioEpisodio(
              ep: ep,
              lembrete: preferencias.lembrete(PreferenciasLocais.chaveEpisodio(ep.id)),
              agora: widget.agora,
              onAbrir: () => widget.onAbrirEpisodio(ep.id),
            ),
          ],
      ],
    );
  }
}

/// Lembrete geral do dia: o texto (com o aviso, se houver) e "Editar", ou o
/// botao para adicionar.
class _LembreteDoDia extends StatelessWidget {
  const _LembreteDoDia({required this.lembrete, required this.agora});

  final Lembrete? lembrete;
  final DateTime agora;

  void _editar(BuildContext context) => editarLembrete(
        context,
        chave: PreferenciasLocais.chaveDia(agora),
        titulo: 'Lembrete do dia',
        tituloDoAviso: 'Lembrete do dia',
      );

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final atual = lembrete;
    if (atual == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _editar(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adicionar lembrete do dia'),
        ),
      );
    }
    final aviso = atual.avisoPendente(agora);
    final fraseAviso = aviso != null ? 'O celular avisa ${quandoEm(aviso, agora)}.' : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.xs, Espaco.xs, Espaco.m),
      decoration: BoxDecoration(
        color: cores.superficieAlta,
        borderRadius: BorderRadius.circular(Raio.controle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 20, color: cores.tintaSuave),
              const SizedBox(width: Espaco.s),
              Expanded(child: Semantics(header: true, child: Text('Lembrete do dia', style: texto.labelLarge))),
              TextButton(
                onPressed: () => _editar(context),
                child: Semantics(label: 'Editar lembrete do dia', excludeSemantics: true, child: const Text('Editar')),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, right: Espaco.s),
            child: Semantics(
              container: true,
              label: '${atual.texto}${fraseAviso != null ? '. $fraseAviso' : ''}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(atual.texto, style: texto.bodyMedium),
                  if (fraseAviso != null) ...[
                    const SizedBox(height: Espaco.xs),
                    Row(
                      children: [
                        Icon(Icons.alarm_rounded, size: 16, color: cores.tintaSuave),
                        const SizedBox(width: Espaco.xs),
                        Expanded(child: Text(fraseAviso, style: texto.bodySmall)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Relatorio curto de um episodio do dia. O item inteiro e um botao que abre
/// o detalhe (com "Confirmar gatilho", "Descartar" e o lembrete).
class _RelatorioEpisodio extends StatelessWidget {
  const _RelatorioEpisodio({required this.ep, required this.lembrete, required this.agora, required this.onAbrir});

  final Episodio ep;
  final Lembrete? lembrete;
  final DateTime agora;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final visual = NivelVisual.de(ep.nivelMaximo);
    final horario = horarioDoEpisodio(ep);
    final pecas = [
      if (!ep.emAndamento) 'Duração: ${duracao(ep.duracaoS)}',
      if (ep.probabilidadeMaxima != null) 'Probabilidade máxima: ${(ep.probabilidadeMaxima! * 100).round()}%',
    ];
    final detalhes = pecas.map((p) => '$p.').join(' ');
    final avaliacao = resumoAvaliacao(ep, cores);
    final manchete = mancheteDoGatilho(ep.gatilho, emAndamento: ep.emAndamento).manchete;
    final nota = lembrete;
    final fala = [
      '$horario.',
      'Nível máximo: ${visual.rotulo}.',
      if (detalhes.isNotEmpty) detalhes,
      '$manchete.',
      avaliacao.frase,
      if (nota != null) 'Lembrete: ${nota.texto}.',
    ].join(' ');

    return Semantics(
      container: true,
      button: true,
      label: fala,
      hint: 'Toque para abrir o episódio',
      excludeSemantics: true,
      onTap: onAbrir,
      child: InkWell(
        onTap: onAbrir,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.m, Espaco.s, Espaco.l),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Espaco.m,
                      runSpacing: Espaco.s,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SeloNivel(visual),
                        Text(horario, style: texto.titleSmall),
                      ],
                    ),
                    // Cada peca desce inteira quando nao cabe na linha
                    if (pecas.isNotEmpty) ...[
                      const SizedBox(height: Espaco.s),
                      Wrap(
                        spacing: Espaco.l,
                        runSpacing: 2,
                        children: [for (final p in pecas) Text(p, style: texto.bodySmall)],
                      ),
                    ],
                    const SizedBox(height: Espaco.m),
                    GatilhoSimples(gatilho: ep.gatilho, emAndamento: ep.emAndamento),
                    const SizedBox(height: Espaco.m),
                    // Mesma coluna de icone do gatilho (24 + 12)
                    Row(
                      children: [
                        SizedBox(width: 24, child: Icon(avaliacao.icone, size: 20, color: avaliacao.cor)),
                        const SizedBox(width: Espaco.m),
                        Expanded(child: Text(avaliacao.frase, style: texto.bodyMedium)),
                      ],
                    ),
                    if (nota != null) ...[
                      const SizedBox(height: Espaco.s),
                      LinhaLembrete(lembrete: nota, agora: agora),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Espaco.xs),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(Icons.chevron_right_rounded, color: cores.tintaSuave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
