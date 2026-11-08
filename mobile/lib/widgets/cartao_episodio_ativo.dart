import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'gatilho_simples.dart';
import 'nivel_visual.dart';

/// Cartao do episodio em andamento (logo abaixo da faixa): desde quando, o
/// nivel mais alto, o provavel gatilho e o "Estou ciente".
///
/// "Estou ciente": o toque publica o ack (MqttService.enviarCiente) e mostra
/// "Ciente às HH:MM" por [tempoDaConfirmacao]; depois a confirmacao some (fade
/// curto, ou sem animacao com "reduzir movimento") e o botao nao volta para o
/// mesmo episodio. Num episodio novo, o botao aparece de novo. O horario fica
/// registrado no historico do episodio ("Alerta visto pelo cuidador às").
class CartaoEpisodioAtivo extends StatefulWidget {
  const CartaoEpisodioAtivo({
    super.key,
    required this.service,
    required this.ativo,
    required this.estado,
    required this.onCiente,
  });

  final MqttService service;
  final EpisodioAtivo ativo;
  final EstadoAtual estado;

  /// Envia o "Estou ciente"; devolve true se foi enviado.
  final bool Function(String episodioId) onCiente;

  static const tempoDaConfirmacao = Duration(seconds: 5);

  @override
  State<CartaoEpisodioAtivo> createState() => _CartaoEpisodioAtivoState();
}

class _CartaoEpisodioAtivoState extends State<CartaoEpisodioAtivo> {
  Timer? _timer;

  // Episodio cuja confirmacao ainda esta na tela.
  String? _confirmando;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tocarCiente() {
    final id = widget.ativo.id;
    if (!widget.onCiente(id)) return;
    _timer?.cancel();
    setState(() => _confirmando = id);
    _timer = Timer(CartaoEpisodioAtivo.tempoDaConfirmacao, () {
      if (mounted) setState(() => _confirmando = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final ativo = widget.ativo;
    final inicio = ativo.inicio;
    final maximoAcima = ativo.nivelMaximo.rank > widget.estado.nivel.rank;
    final titulo = inicio != null ? 'Episódio em andamento desde ${horaMinuto(inicio)}' : 'Episódio em andamento';
    final ciente = widget.service.cienteEm(ativo.id);
    final curto = Movimento.de(context, Movimento.curto);

    final Widget acao;
    if (ciente == null) {
      acao = Padding(
        key: const ValueKey('botao'),
        padding: const EdgeInsets.only(top: Espaco.bloco),
        child: Semantics(
          hint: 'Avisa a pulseira que você viu o alerta',
          child: FilledButton.icon(
            onPressed: _tocarCiente,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Toque.principal)),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Estou ciente'),
          ),
        ),
      );
    } else if (_confirmando == ativo.id) {
      acao = Padding(
        key: const ValueKey('ciente'),
        padding: const EdgeInsets.only(top: Espaco.bloco),
        child: Semantics(
          container: true,
          liveRegion: true,
          label: 'Aviso enviado. Ciente às ${horaMinuto(ciente)}.',
          excludeSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: Toque.principal),
            padding: const EdgeInsets.symmetric(horizontal: Espaco.l, vertical: Espaco.m),
            decoration: BoxDecoration(
              // Azul de acao (nao o verde de Calmo: a crianca pode estar em crise)
              color: cores.primariaSuave,
              borderRadius: BorderRadius.circular(Raio.controle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: cores.sobrePrimariaSuave),
                const SizedBox(width: Espaco.s),
                Flexible(
                  child: Text(
                    'Ciente às ${horaMinuto(ciente)}',
                    style: texto.titleSmall!.copyWith(color: cores.sobrePrimariaSuave),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      acao = const SizedBox(key: ValueKey('reconhecido'), width: double.infinity);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(Espaco.l, 20, Espaco.l, 20),
      decoration: BoxDecoration(
        color: cores.superficie,
        borderRadius: BorderRadius.circular(Raio.secao),
        boxShadow: cores.sombraElevada,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 32, child: Icon(Icons.schedule_rounded, size: 28, color: cores.tinta)),
                const SizedBox(width: Espaco.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(titulo, style: texto.titleSmall),
                      ),
                      if (maximoAcima) ...[
                        const SizedBox(height: 2),
                        Text('Nível mais alto: ${NivelVisual.de(ativo.nivelMaximo).rotulo}.', style: texto.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaco.bloco),
          GatilhoSimples(gatilho: widget.estado.gatilho, emAndamento: true, larguraDoIcone: 32),
          TamanhoAnimado(
            duracao: Movimento.curto,
            child: AnimatedSwitcher(duration: curto, child: acao),
          ),
          const SizedBox(height: Espaco.m),
          Text('Indicação de apoio ao cuidador, sem valor diagnóstico.', style: texto.bodySmall),
        ],
      ),
    );
  }
}
