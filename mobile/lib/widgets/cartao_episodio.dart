import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'botoes_adaptaveis.dart';
import 'gatilho_simples.dart';
import 'nivel_visual.dart';
import 'secao.dart';

/// Icone, cor e frase da avaliacao do cuidador ("Avaliação pendente." etc.).
({IconData icone, Color cor, String frase}) resumoAvaliacao(Episodio ep, CoresApp cores) {
  final quem = ep.avaliacaoOrigem == 'app' ? 'por você' : 'no painel';
  final quando = ep.avaliacaoEm != null ? ' às ${horaMinuto(ep.avaliacaoEm!)}' : '';
  return switch (ep.avaliacao) {
    Avaliacao.confirmado => (
        icone: Icons.check_circle_rounded,
        cor: cores.primaria,
        frase: 'Gatilho confirmado $quem$quando.',
      ),
    Avaliacao.descartado => (
        icone: Icons.remove_circle_outline_rounded,
        cor: cores.tinta,
        frase: 'Indicação descartada $quem$quando.',
      ),
    Avaliacao.pendente => (
        icone: Icons.radio_button_unchecked_rounded,
        cor: cores.tintaSuave,
        frase: 'Avaliação pendente.',
      ),
  };
}

/// Cartao de um episodio do historico: nivel maximo, quando, duracao,
/// gatilho, alerta visto, avaliacao e os botoes "Confirmar gatilho" e
/// "Descartar" (com uma observacao curta). O app publica a avaliacao em
/// `puzzleband/<id>/avaliacao` (MqttService.enviarAvaliacao). Usado no
/// Historico e no detalhe do episodio.
class CartaoEpisodio extends StatefulWidget {
  const CartaoEpisodio({super.key, required this.episodio, required this.agora});

  final Episodio episodio;
  final DateTime agora;

  @override
  State<CartaoEpisodio> createState() => _CartaoEpisodioState();
}

class _CartaoEpisodioState extends State<CartaoEpisodio> {
  static const _maxObservacao = 200;

  // `_obsDoSite` guarda o ultimo valor recebido: se o cuidador nao editou, o
  // campo acompanha o site.
  late final TextEditingController _obs = TextEditingController(text: widget.episodio.observacao);
  late String _obsDoSite = widget.episodio.observacao;
  bool _obsAberta = false;

  @override
  void didUpdateWidget(CartaoEpisodio antigo) {
    super.didUpdateWidget(antigo);
    final novo = widget.episodio.observacao;
    if (novo != _obsDoSite) {
      if (_obs.text == _obsDoSite) _obs.text = novo;
      _obsDoSite = novo;
    }
  }

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  void _avaliar(Avaliacao avaliacao) {
    FocusScope.of(context).unfocus();
    final ep = widget.episodio;
    final service = AppScope.read(context);
    final texto = _obs.text;
    final enviado = service.enviarAvaliacao(ep, avaliacao, texto);
    if (enviado) {
      _obsDoSite = texto.trim();
      setState(() => _obsAberta = false);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            enviado
                ? (avaliacao == Avaliacao.confirmado
                    ? 'Gatilho confirmado e enviado ao painel.'
                    : 'Indicação descartada e enviada ao painel.')
                : 'Sem conexão com o servidor: a avaliação não foi enviada. Tente de novo em instantes.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final ep = widget.episodio;
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final visual = NivelVisual.de(ep.nivelMaximo);
    final ciente = ep.vistoEm ?? service.cienteEm(ep.id);
    final duracaoTexto = ep.emAndamento ? 'Em andamento' : 'Duração: ${duracao(ep.duracaoS)}';
    final detalhes = [
      if (ep.probabilidadeMaxima != null) 'Probabilidade máxima: ${(ep.probabilidadeMaxima! * 100).round()}%.',
      'Fonte: ${rotuloFonte(ep.fonte).toLowerCase()}.',
    ].join(' ');

    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Nivel maximo + quando
          Wrap(
            spacing: Espaco.m,
            runSpacing: Espaco.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SeloNivel(visual),
              Text(diaRelativo(ep.inicio, widget.agora), style: texto.titleSmall),
            ],
          ),
          const SizedBox(height: Espaco.m),
          Row(
            children: [
              Icon(ep.emAndamento ? Icons.timelapse_rounded : Icons.schedule_rounded, size: 20, color: cores.tintaSuave),
              const SizedBox(width: Espaco.s),
              Expanded(
                child: Text(
                  ep.encerramento == 'interrompido' ? '$duracaoTexto. Interrompido.' : duracaoTexto,
                  style: texto.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(detalhes, style: texto.bodySmall),
          const SizedBox(height: Espaco.l),
          GatilhoSimples(gatilho: ep.gatilho),
          if (ciente != null) ...[
            const SizedBox(height: Espaco.m),
            Row(
              children: [
                Icon(Icons.visibility_outlined, size: 20, color: cores.tintaSuave),
                const SizedBox(width: Espaco.s),
                Expanded(child: Text('Alerta visto pelo cuidador às ${horaMinuto(ciente)}.', style: texto.bodySmall)),
              ],
            ),
          ],
          const SizedBox(height: Espaco.l),
          AnimatedSwitcher(
            duration: Movimento.de(context, Movimento.curto),
            child: _LinhaAvaliacao(key: ValueKey('${ep.avaliacao}-${ep.avaliacaoEm}'), ep: ep),
          ),
          const SizedBox(height: Espaco.s),
          TamanhoAnimado(duracao: Movimento.curto, child: _observacao()),
          const SizedBox(height: Espaco.s),
          BotoesAdaptaveis(
            rotulos: const ['Confirmar gatilho', 'Descartar'],
            botoes: [
              _botaoAvaliacao(Avaliacao.confirmado, Icons.check_rounded, 'Confirmar gatilho'),
              _botaoAvaliacao(Avaliacao.descartado, Icons.close_rounded, 'Descartar'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _observacao() {
    final texto = Theme.of(context).textTheme;
    if (_obsAberta) {
      return Padding(
        padding: const EdgeInsets.only(top: Espaco.s),
        child: TextField(
          controller: _obs,
          maxLength: _maxObservacao,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Observação (opcional)',
            hintText: 'Ex.: a sirene da escola tocou antes',
            helperText: 'Vai junto quando você confirmar ou descartar.',
          ),
        ),
      );
    }
    final atual = _obs.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (atual.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Espaco.s),
            child: Text('Observação: $atual', style: texto.bodyMedium),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _obsAberta = true),
            icon: Icon(atual.isEmpty ? Icons.add_rounded : Icons.edit_outlined),
            label: Text(atual.isEmpty ? 'Adicionar observação' : 'Editar observação'),
          ),
        ),
      ],
    );
  }

  Widget _botaoAvaliacao(Avaliacao avaliacao, IconData icone, String rotulo) {
    final selecionado = widget.episodio.avaliacao == avaliacao;
    final conteudo = Text(rotulo, maxLines: 1, softWrap: false);
    // O escolhido fica cheio e com check: confirmacao visual depois de enviar.
    return Semantics(
      selected: selecionado,
      child: selecionado
          ? FilledButton.icon(
              onPressed: () => _avaliar(avaliacao),
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: conteudo,
            )
          : OutlinedButton.icon(
              onPressed: () => _avaliar(avaliacao),
              icon: Icon(icone, size: 20),
              label: conteudo,
            ),
    );
  }
}

/// Situacao da avaliacao, em destaque.
class _LinhaAvaliacao extends StatelessWidget {
  const _LinhaAvaliacao({super.key, required this.ep});

  final Episodio ep;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final (:icone, :cor, :frase) = resumoAvaliacao(ep, cores);
    return Semantics(
      container: true,
      liveRegion: true,
      label: frase,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Espaco.m),
        decoration: BoxDecoration(color: cores.superficieAlta, borderRadius: BorderRadius.circular(Raio.controle)),
        child: Row(
          children: [
            Icon(icone, color: cor),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text(frase, style: texto.titleSmall)),
          ],
        ),
      ),
    );
  }
}
