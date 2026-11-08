import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'botoes_adaptaveis.dart';
import 'gatilho_simples.dart';
import 'nivel_visual.dart';
import 'secao.dart';
import 'selo_avaliacao.dart';

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

/// Cartao completo de um episodio (tela de detalhe): nivel maximo, quando,
/// duracao, gatilho, alerta visto e a avaliacao ([AvaliacaoEpisodio]).
class CartaoEpisodio extends StatelessWidget {
  const CartaoEpisodio({super.key, required this.episodio, required this.agora});

  final Episodio episodio;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final ep = episodio;
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
              Text(diaRelativo(ep.inicio, agora), style: texto.titleSmall),
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
            LinhaInfo(icone: Icons.visibility_outlined, texto: 'Alerta visto pelo cuidador às ${horaMinuto(ciente)}.'),
          ],
          const SizedBox(height: Espaco.l),
          AvaliacaoEpisodio(episodio: ep),
        ],
      ),
    );
  }
}

/// Icone pequeno + frase secundaria (detalhes do episodio).
class LinhaInfo extends StatelessWidget {
  const LinhaInfo({super.key, required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icone, size: 20, color: CoresApp.of(context).tintaSuave),
        ),
        const SizedBox(width: Espaco.s),
        Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

/// Avaliacao do cuidador: a situacao em destaque, a observacao curta, por que
/// confirmar ajuda e os botoes "Confirmar gatilho" e "Descartar". O app
/// publica em `puzzleband/<id>/avaliacao` (MqttService.enviarAvaliacao). O
/// botao escolhido fica cheio e passa a dizer "Confirmado" (azul) ou
/// "Descartado" (vermelho tijolo). Os dois continuam tocaveis: o cuidador
/// pode mudar de ideia, e a avaliacao e reenviada.
class AvaliacaoEpisodio extends StatefulWidget {
  const AvaliacaoEpisodio({super.key, required this.episodio, this.chaveBotoes});

  final Episodio episodio;

  /// Chave da linha de botoes (para rolar ate ela).
  final Key? chaveBotoes;

  static const explicacao = 'Confirmar ajuda o Puzzle Band a aprender os padrões desta criança em '
      'versões futuras. Só crises confirmadas contam no calendário.';

  @override
  State<AvaliacaoEpisodio> createState() => _AvaliacaoEpisodioState();
}

class _AvaliacaoEpisodioState extends State<AvaliacaoEpisodio> {
  static const _maxObservacao = 200;

  // `_obsDoSite` guarda o ultimo valor recebido: se o cuidador nao editou, o
  // campo acompanha o historico recebido.
  late final TextEditingController _obs = TextEditingController(text: widget.episodio.observacao);
  late String _obsDoSite = widget.episodio.observacao;
  bool _obsAberta = false;

  @override
  void didUpdateWidget(AvaliacaoEpisodio antigo) {
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
                    ? 'Gatilho confirmado e enviado à pulseira.'
                    : 'Indicação descartada e enviada à pulseira.')
                : 'Sem conexão com o servidor: a avaliação não foi enviada. Tente de novo em instantes.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ep = widget.episodio;
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final rotuloConfirmar = ep.avaliacao == Avaliacao.confirmado ? 'Confirmado' : 'Confirmar gatilho';
    final rotuloDescartar = ep.avaliacao == Avaliacao.descartado ? 'Descartado' : 'Descartar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: Movimento.de(context, Movimento.curto),
          child: _LinhaAvaliacao(key: ValueKey('${ep.avaliacao}-${ep.avaliacaoEm}'), ep: ep),
        ),
        const SizedBox(height: Espaco.s),
        TamanhoAnimado(duracao: Movimento.curto, child: _observacao()),
        const SizedBox(height: Espaco.s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline_rounded, size: 20, color: cores.tintaSuave),
            ),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text(AvaliacaoEpisodio.explicacao, style: texto.bodySmall)),
          ],
        ),
        const SizedBox(height: Espaco.m),
        BotoesAdaptaveis(
          key: widget.chaveBotoes,
          rotulos: [rotuloConfirmar, rotuloDescartar],
          botoes: [
            _botao(Avaliacao.confirmado, Icons.check_rounded, rotuloConfirmar),
            _botao(Avaliacao.descartado, Icons.close_rounded, rotuloDescartar),
          ],
        ),
      ],
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

  /// O escolhido fica cheio, com o icone da avaliacao e o rotulo no passado:
  /// confirmacao visual depois de enviar.
  Widget _botao(Avaliacao avaliacao, IconData icone, String rotulo) {
    final selecionado = widget.episodio.avaliacao == avaliacao;
    final conteudo = Text(rotulo, maxLines: 1, softWrap: false);
    void tocar() => _avaliar(avaliacao);
    if (!selecionado) {
      return Semantics(
        selected: false,
        child: OutlinedButton.icon(onPressed: tocar, icon: Icon(icone, size: 20), label: conteudo),
      );
    }
    final vermelho = CoresDados.of(context).descartado;
    return Semantics(
      selected: true,
      child: FilledButton.icon(
        onPressed: tocar,
        style: avaliacao == Avaliacao.descartado
            ? FilledButton.styleFrom(backgroundColor: vermelho.fundo, foregroundColor: vermelho.texto)
            : null,
        icon: Icon(SeloAvaliacao.icone(avaliacao), size: 20),
        label: conteudo,
      ),
    );
  }
}

/// Situacao da avaliacao, em destaque. A pendente usa o vocabulario do
/// calendario ("possível crise aguardando sua confirmação").
class _LinhaAvaliacao extends StatelessWidget {
  const _LinhaAvaliacao({super.key, required this.ep});

  final Episodio ep;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final dados = CoresDados.of(context);
    final texto = Theme.of(context).textTheme;
    final frase = ep.avaliacao == Avaliacao.pendente
        ? 'Possível crise aguardando sua confirmação.'
        : resumoAvaliacao(ep, cores).frase;
    final cor = switch (ep.avaliacao) {
      Avaliacao.pendente => dados.pendente,
      Avaliacao.confirmado => cores.tinta,
      Avaliacao.descartado => dados.descartadoTinta,
    };
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
            Icon(SeloAvaliacao.icone(ep.avaliacao), color: cor),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text(frase, style: texto.titleSmall)),
          ],
        ),
      ),
    );
  }
}
