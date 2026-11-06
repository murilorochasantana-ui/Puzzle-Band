import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/botoes_adaptaveis.dart';
import '../widgets/cabecalho.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/gatilho_simples.dart';
import '../widgets/nivel_visual.dart';
import '../widgets/secao.dart';

/// Episodios recebidos do site (`puzzleband/<id>/historico`). O cuidador
/// confirma ou descarta o gatilho, com uma observacao curta, e o app publica
/// em `puzzleband/<id>/avaliacao`. A ultima copia fica salva para ver offline.
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  static const _maxObservacao = 200;

  // Um campo de observacao por episodio. `_obsDoSite` guarda o ultimo valor
  // recebido: se o cuidador nao editou, o campo acompanha o site.
  final Map<String, TextEditingController> _obs = {};
  final Map<String, String> _obsDoSite = {};

  // Episodios com o campo de observacao aberto.
  final Set<String> _obsAberta = {};

  @override
  void dispose() {
    for (final c in _obs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerPara(Episodio ep) {
    final existente = _obs[ep.id];
    if (existente == null) {
      _obsDoSite[ep.id] = ep.observacao;
      return _obs[ep.id] = TextEditingController(text: ep.observacao);
    }
    final anterior = _obsDoSite[ep.id];
    if (anterior != ep.observacao) {
      if (existente.text == anterior) existente.text = ep.observacao;
      _obsDoSite[ep.id] = ep.observacao;
    }
    return existente;
  }

  void _avaliar(Episodio ep, Avaliacao avaliacao) {
    FocusScope.of(context).unfocus();
    final service = AppScope.read(context);
    final texto = _obs[ep.id]?.text ?? ep.observacao;
    final enviado = service.enviarAvaliacao(ep, avaliacao, texto);
    if (enviado) {
      _obsDoSite[ep.id] = texto.trim();
      setState(() => _obsAberta.remove(ep.id));
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
    final episodios = service.historico;
    final agora = relogio();
    return EstruturaTela(
      children: [
        const TituloTela(
          'Histórico',
          apoio: 'Episódios detectados pelo painel. Confirme ou descarte o provável gatilho.',
        ),
        const SizedBox(height: Espaco.m),
        _FonteDosDados(service: service),
        const SizedBox(height: Espaco.l),
        if (episodios.isEmpty)
          const Secao(
            child: EstadoVazio(
              icone: Icons.history_rounded,
              titulo: 'Nenhum episódio ainda',
              texto: 'Quando o painel (site) detectar sinais de atenção ou de possível crise, '
                  'o episódio aparece aqui para você avaliar.',
            ),
          )
        else
          for (final ep in episodios) ...[
            _cartao(service, ep, agora),
            const SizedBox(height: Espaco.m),
          ],
      ],
    );
  }

  Widget _cartao(MqttService service, Episodio ep, DateTime agora) {
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
          TamanhoAnimado(duracao: Movimento.curto, child: _observacao(ep)),
          const SizedBox(height: Espaco.s),
          BotoesAdaptaveis(
            rotulos: const ['Confirmar gatilho', 'Descartar'],
            botoes: [
              _botaoAvaliacao(ep, Avaliacao.confirmado, Icons.check_rounded, 'Confirmar gatilho'),
              _botaoAvaliacao(ep, Avaliacao.descartado, Icons.close_rounded, 'Descartar'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _observacao(Episodio ep) {
    final texto = Theme.of(context).textTheme;
    if (_obsAberta.contains(ep.id)) {
      return Padding(
        padding: const EdgeInsets.only(top: Espaco.s),
        child: TextField(
          controller: _controllerPara(ep),
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
    final controller = _controllerPara(ep);
    final atual = controller.text.trim();
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
            onPressed: () => setState(() => _obsAberta.add(ep.id)),
            icon: Icon(atual.isEmpty ? Icons.add_rounded : Icons.edit_outlined),
            label: Text(atual.isEmpty ? 'Adicionar observação' : 'Editar observação'),
          ),
        ),
      ],
    );
  }

  Widget _botaoAvaliacao(Episodio ep, Avaliacao avaliacao, IconData icone, String rotulo) {
    final selecionado = ep.avaliacao == avaliacao;
    final conteudo = Text(rotulo, maxLines: 1, softWrap: false);
    // O escolhido fica cheio e com check: confirmacao visual depois de enviar.
    return Semantics(
      selected: selecionado,
      child: selecionado
          ? FilledButton.icon(
              onPressed: () => _avaliar(ep, avaliacao),
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: conteudo,
            )
          : OutlinedButton.icon(
              onPressed: () => _avaliar(ep, avaliacao),
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
    final quem = ep.avaliacaoOrigem == 'app' ? 'por você' : 'no painel';
    final quando = ep.avaliacaoEm != null ? ' às ${horaMinuto(ep.avaliacaoEm!)}' : '';
    final (IconData icone, Color cor, String frase) = switch (ep.avaliacao) {
      Avaliacao.confirmado => (Icons.check_circle_rounded, cores.primaria, 'Gatilho confirmado $quem$quando.'),
      Avaliacao.descartado => (Icons.remove_circle_outline_rounded, cores.tinta, 'Indicação descartada $quem$quando.'),
      Avaliacao.pendente => (Icons.radio_button_unchecked_rounded, cores.tintaSuave, 'Avaliação pendente.'),
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
            Icon(icone, color: cor),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text(frase, style: texto.titleSmall)),
          ],
        ),
      ),
    );
  }
}

/// De onde vem a lista: ao vivo ou a copia salva no celular.
class _FonteDosDados extends StatelessWidget {
  const _FonteDosDados({required this.service});

  final MqttService service;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final aoVivo = service.historicoAoVivo;
    final recebido = service.historicoRecebidoEm;
    final String frase;
    if (aoVivo) {
      frase = 'Atualizado pelo painel${recebido != null ? ' às ${horaMinuto(recebido)}' : ''}.';
    } else if (recebido != null) {
      frase = 'Sem conexão: mostrando a última cópia salva, de ${diaHora(recebido)}.';
    } else {
      frase = 'Sem conexão e sem cópia salva ainda.';
    }
    return Row(
      children: [
        Icon(aoVivo ? Icons.sync_rounded : Icons.cloud_off_outlined,
            size: 20, color: aoVivo ? cores.primaria : cores.tinta),
        const SizedBox(width: Espaco.s),
        Expanded(
          child: Text(
            frase,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: aoVivo ? cores.tintaSuave : cores.tinta,
                  fontWeight: aoVivo ? FontWeight.w400 : FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
