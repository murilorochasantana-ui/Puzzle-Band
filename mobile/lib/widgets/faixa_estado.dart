import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'gatilho_simples.dart';
import 'nivel_visual.dart';

/// O que a Home consegue mostrar agora.
enum SituacaoEstado { configuracao, conectando, semConexao, painelParado, aguardando, aoVivo }

SituacaoEstado situacaoDe(MqttService service) {
  if (service.brokerStatus == BrokerStatus.naoConfigurado) return SituacaoEstado.configuracao;
  if (service.estadoAoVivo && service.estado != null) return SituacaoEstado.aoVivo;
  return switch (service.brokerStatus) {
    BrokerStatus.conectando => SituacaoEstado.conectando,
    BrokerStatus.desconectado || BrokerStatus.erro => SituacaoEstado.semConexao,
    _ => _recebeuAlgumDia(service) ? SituacaoEstado.painelParado : SituacaoEstado.aguardando,
  };
}

// Mensagem retida sem horario fica com data 1970: nao conta como recebida.
bool _recebeuAlgumDia(MqttService service) {
  final recebido = service.estadoRecebidoEm;
  return recebido != null && recebido.year > 2000;
}

/// Faixa de estado: o elemento principal da Home. Nivel (icone + palavra +
/// cor), BPM ao vivo e, durante um episodio, o provavel gatilho e o botao
/// "Estou ciente". Sem estado ao vivo, diz por que e o que fazer.
class FaixaEstado extends StatelessWidget {
  const FaixaEstado({super.key, required this.service, required this.onCiente});

  final MqttService service;
  final ValueChanged<String> onCiente;

  @override
  Widget build(BuildContext context) {
    final situacao = situacaoDe(service);
    final estado = service.estado;
    final visual = situacao == SituacaoEstado.aoVivo ? NivelVisual.de(estado!.nivel) : NivelVisual.semDados;
    final tom = visual.tom(context);
    final duracao = Movimento.de(context, Movimento.medio);
    return AnimatedContainer(
      duration: duracao,
      curve: Movimento.curva,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(Raio.faixa),
      ),
      child: TamanhoAnimado(
        child: situacao == SituacaoEstado.aoVivo
            ? _AoVivo(service: service, estado: estado!, visual: visual, tom: tom, onCiente: onCiente)
            : _SemEstadoAoVivo(service: service, situacao: situacao, tom: tom),
      ),
    );
  }
}

class _AoVivo extends StatelessWidget {
  const _AoVivo({
    required this.service,
    required this.estado,
    required this.visual,
    required this.tom,
    required this.onCiente,
  });

  final MqttService service;
  final EstadoAtual estado;
  final NivelVisual visual;
  final TomRisco tom;
  final ValueChanged<String> onCiente;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final curto = Movimento.de(context, Movimento.curto);
    final bpm = estado.leituras?.bpm;
    final media = estado.mediaBpm5min;
    final ativo = service.episodioAtivo;

    final String linhaBpm;
    final String falaBpm;
    if (bpm == null) {
      linhaBpm = 'Sem leitura de batimentos agora.';
      falaBpm = 'Frequência cardíaca: sem leitura agora.';
    } else {
      linhaBpm = media != null ? 'Ao vivo. Média de 5 min: ${media.round()} bpm.' : 'Ao vivo.';
      falaBpm = 'Frequência cardíaca: ${bpm.round()} batimentos por minuto, ao vivo.'
          '${media != null ? ' Média de 5 minutos: ${media.round()}.' : ''}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nivel: so este no e anunciado sozinho pelo leitor de tela, e so
        // quando o nivel muda (nunca a cada BPM).
        AnimatedSwitcher(
          duration: curto,
          child: Semantics(
            key: ValueKey(visual.tipo),
            container: true,
            liveRegion: true,
            label: 'Estado da criança: ${visual.rotulo}',
            excludeSemantics: true,
            child: Row(
              children: [
                Icon(visual.icone, size: 40, color: tom.texto),
                const SizedBox(width: Espaco.m),
                Expanded(
                  child: Text(visual.rotulo, style: texto.displaySmall!.copyWith(color: tom.texto)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espaco.l),
        Semantics(
          container: true,
          label: falaBpm,
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Icon(Icons.favorite_rounded, size: 28, color: cores.tintaSuave),
                  const SizedBox(width: Espaco.s),
                  Text(bpm != null ? '${bpm.round()}' : '—', style: texto.displayMedium),
                  const SizedBox(width: 6),
                  Text('bpm', style: texto.titleMedium!.copyWith(color: cores.tintaSuave)),
                ],
              ),
              const SizedBox(height: Espaco.xs),
              Text(linhaBpm, style: texto.bodySmall),
            ],
          ),
        ),
        if (ativo != null) ..._episodio(context, ativo),
      ],
    );
  }

  List<Widget> _episodio(BuildContext context, EpisodioAtivo ativo) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final ciente = service.cienteEm(ativo.id);
    final inicio = ativo.inicio;
    final maximoAcima = ativo.nivelMaximo.rank > estado.nivel.rank;
    final titulo = inicio != null ? 'Episódio em andamento desde ${horaMinuto(inicio)}' : 'Episódio em andamento';
    return [
      const SizedBox(height: Espaco.l),
      Divider(color: tom.texto.withValues(alpha: 0.25)),
      const SizedBox(height: Espaco.l),
      Semantics(
        container: true,
        liveRegion: true,
        child: Text(titulo, style: texto.titleSmall),
      ),
      if (maximoAcima) ...[
        const SizedBox(height: 2),
        Text('Nível mais alto: ${NivelVisual.de(ativo.nivelMaximo).rotulo}.', style: texto.bodySmall),
      ],
      const SizedBox(height: Espaco.m),
      GatilhoSimples(gatilho: estado.gatilho, emAndamento: true),
      const SizedBox(height: Espaco.l),
      AnimatedSwitcher(
        duration: Movimento.de(context, Movimento.curto),
        child: ciente != null
            ? Semantics(
                key: const ValueKey('ciente'),
                container: true,
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Espaco.m),
                  decoration: BoxDecoration(
                    color: cores.superficie,
                    borderRadius: BorderRadius.circular(Raio.controle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: cores.calmo.texto),
                      const SizedBox(width: Espaco.s),
                      Expanded(
                        child: Text(
                          'Você avisou que está ciente às ${horaMinuto(ciente)}.',
                          style: texto.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Semantics(
                key: const ValueKey('botao'),
                hint: 'Avisa o painel que você viu o alerta',
                child: FilledButton.icon(
                  onPressed: () => onCiente(ativo.id),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Toque.principal)),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Estou ciente'),
                ),
              ),
      ),
      const SizedBox(height: Espaco.s),
      Text('Indicação de apoio ao cuidador, sem valor diagnóstico.', style: texto.bodySmall),
    ];
  }
}

class _SemEstadoAoVivo extends StatelessWidget {
  const _SemEstadoAoVivo({required this.service, required this.situacao, required this.tom});

  final MqttService service;
  final SituacaoEstado situacao;
  final TomRisco tom;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final recebido = _recebeuAlgumDia(service) ? service.estadoRecebidoEm : null;
    final (IconData icone, String titulo, String explicacao, String? detalhe) = switch (situacao) {
      SituacaoEstado.configuracao => (
          Icons.settings_outlined,
          'Configuração incompleta',
          'Falta preencher no env.json: ${service.config.problems.join(', ')}.',
          'Rode o app com --dart-define-from-file=env.json (veja docs/app.md).',
        ),
      SituacaoEstado.conectando => (
          Icons.cloud_sync_outlined,
          'Conectando…',
          'Ligando ao servidor de mensagens. O estado da criança aparece em instantes.',
          null,
        ),
      SituacaoEstado.semConexao => (
          Icons.cloud_off_outlined,
          'Sem conexão',
          'O app tenta reconectar sozinho. Confira se o celular está com internet.',
          recebido != null ? 'Último dado recebido às ${horaMinutoSegundo(recebido)}.' : null,
        ),
      SituacaoEstado.painelParado => (
          Icons.sensors_off_rounded,
          'Sem dados ao vivo',
          'O painel (site) parou de enviar às ${horaMinuto(recebido!)}. '
              'Ele precisa estar aberto para analisar os sinais.',
          null,
        ),
      _ => (
          Icons.hourglass_empty_rounded,
          'Aguardando o painel',
          'Abra o painel (site) no computador. É ele que analisa os sinais da pulseira.',
          null,
        ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Estado da criança: $titulo. $explicacao${detalhe != null ? ' $detalhe' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 32, color: tom.texto),
              const SizedBox(width: Espaco.m),
              Expanded(child: Text(titulo, style: texto.headlineSmall!.copyWith(color: tom.texto))),
            ],
          ),
          const SizedBox(height: Espaco.m),
          Text(explicacao, style: texto.bodyMedium),
          if (detalhe != null) ...[
            const SizedBox(height: Espaco.s),
            Text(detalhe, style: texto.bodySmall),
          ],
        ],
      ),
    );
  }
}
