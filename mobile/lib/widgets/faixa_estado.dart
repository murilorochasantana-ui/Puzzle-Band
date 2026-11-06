import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
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
/// cor) e BPM ao vivo, com a media de 5 min ao lado (modelo do Figma,
/// docs/figma/home.md). O episodio em andamento fica no cartao logo abaixo
/// (cartao_episodio_ativo.dart). Sem estado ao vivo, diz por que e o que
/// fazer.
class FaixaEstado extends StatelessWidget {
  const FaixaEstado({super.key, required this.service});

  final MqttService service;

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
      padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.l, Espaco.l, 20),
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(Raio.faixa),
        boxShadow: CoresApp.of(context).sombraElevada,
      ),
      child: TamanhoAnimado(
        child: situacao == SituacaoEstado.aoVivo
            ? _AoVivo(estado: estado!, visual: visual, tom: tom)
            : _SemEstadoAoVivo(service: service, situacao: situacao, tom: tom),
      ),
    );
  }
}

class _AoVivo extends StatelessWidget {
  const _AoVivo({required this.estado, required this.visual, required this.tom});

  final EstadoAtual estado;
  final NivelVisual visual;
  final TomRisco tom;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final curto = Movimento.de(context, Movimento.curto);
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
        const SizedBox(height: Espaco.m),
        _LinhaBpm(estado: estado, tom: tom),
      ],
    );
  }
}

/// BPM ao vivo (esquerda) | "Ao vivo" + media de 5 min (direita), como no
/// modelo. O BPM usa o maior tamanho que deixa as duas colunas lado a lado
/// (60 sp a partir de ~410 dp de largura, 48 sp num celular de 393 dp).
/// Quando nem assim cabem (celular estreito, fonte ampliada), a coluna da
/// direita desce para baixo do BPM, que volta a 60 sp.
class _LinhaBpm extends StatelessWidget {
  const _LinhaBpm({required this.estado, required this.tom});

  final EstadoAtual estado;
  final TomRisco tom;

  static const _icone = 32.0;
  static const _respiro = Espaco.l;

  static double _largura(String texto, TextStyle estilo, TextScaler escala) {
    final medida = TextPainter(
      text: TextSpan(text: texto, style: estilo),
      textDirection: TextDirection.ltr,
      textScaler: escala,
      maxLines: 1,
    )..layout();
    final largura = medida.width;
    medida.dispose();
    return largura;
  }

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final escala = MediaQuery.textScalerOf(context);
    final bpm = estado.leituras?.bpm;
    final media = estado.mediaBpm5min;

    final String fala;
    if (bpm == null) {
      fala = 'Frequência cardíaca: sem leitura agora.';
    } else {
      fala = 'Frequência cardíaca: ${bpm.round()} batimentos por minuto, ao vivo.'
          '${media != null ? ' Média de 5 minutos: ${media.round()}.' : ''}';
    }

    final estiloUnidade = texto.titleSmall!.copyWith(color: cores.tintaSuave);
    final estiloMedia = texto.bodyMedium!.copyWith(color: cores.tintaSuave);

    Widget esquerda(TextStyle estiloBpm) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(Icons.favorite_rounded, size: _icone, color: cores.tintaSuave),
            const SizedBox(width: Espaco.s),
            Text(bpm != null ? '${bpm.round()}' : '—', style: estiloBpm),
            const SizedBox(width: 6),
            Text('bpm', style: estiloUnidade),
          ],
        );

    final aoVivo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.ssid_chart_rounded, size: 20, color: cores.tinta),
        const SizedBox(width: 6),
        Flexible(child: Text('Ao vivo', style: texto.titleSmall)),
        const SizedBox(width: Espaco.s),
        // Ponto parado (nunca pisca), no azul de "conectado"
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: cores.primaria, shape: BoxShape.circle),
        ),
      ],
    );

    // Lado a lado: coluna como no modelo ("Ao vivo" / "Média de 5 min:" /
    // "96 bpm"). Empilhado: "Ao vivo" e a media na mesma linha, que quebra
    // so se precisar.
    final direita = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        aoVivo,
        if (bpm == null) ...[
          const SizedBox(height: 2),
          Text('Sem leitura de batimentos agora.', style: estiloMedia),
        ] else if (media != null) ...[
          const SizedBox(height: 2),
          Text('Média de 5 min:', style: estiloMedia),
          Text('${media.round()} bpm', style: texto.titleSmall),
        ],
      ],
    );
    final abaixo = Wrap(
      spacing: Espaco.l,
      runSpacing: Espaco.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        aoVivo,
        if (bpm == null)
          Text('Sem leitura de batimentos agora.', style: estiloMedia)
        else if (media != null)
          Text.rich(
            TextSpan(
              text: 'Média de 5 min: ',
              style: estiloMedia,
              children: [TextSpan(text: '${media.round()} bpm', style: texto.titleSmall)],
            ),
          ),
      ],
    );

    return Semantics(
      container: true,
      label: fala,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, restricoes) {
          final larguraMedia = _largura('Média de 5 min:', estiloMedia, escala);
          final larguraAoVivo = 20 + 6 + _largura('Ao vivo', texto.titleSmall!, escala) + Espaco.s + 8;
          final larguraDireita = larguraMedia > larguraAoVivo ? larguraMedia : larguraAoVivo;
          // Mede com "888" (3 algarismos largos): a disposicao nao muda
          // quando o BPM passa de 99 para 100.
          bool cabe(TextStyle estiloBpm) {
            final larguraEsquerda =
                _icone + Espaco.s + _largura('888', estiloBpm, escala) + 6 + _largura('bpm', estiloUnidade, escala);
            return larguraEsquerda + _respiro * 2 + 1 + larguraDireita <= restricoes.maxWidth;
          }

          final ladoALado = [texto.displayLarge!, texto.displayMedium!].where(cabe).firstOrNull;
          if (ladoALado == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [esquerda(texto.displayLarge!), const SizedBox(height: Espaco.s), abaixo],
            );
          }
          return IntrinsicHeight(
            child: Row(
              children: [
                esquerda(ladoALado),
                const SizedBox(width: _respiro),
                Container(width: 1, color: tom.texto.withValues(alpha: 0.3)),
                const SizedBox(width: _respiro),
                Expanded(child: direita),
              ],
            ),
          );
        },
      ),
    );
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
