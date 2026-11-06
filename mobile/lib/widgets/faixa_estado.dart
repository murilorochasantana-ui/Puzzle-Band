import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'nivel_visual.dart';

/// Divisoria entre o BPM e a coluna "Ao vivo" (testes de posicao).
const chaveDivisoriaBpm = ValueKey('divisoria-bpm');

/// Area a esquerda da divisoria, o grupo coracao + numero + "bpm", o coracao
/// e o numero (testes de posicao).
const chaveAreaBpm = ValueKey('area-bpm');
const chaveGrupoBpm = ValueKey('grupo-bpm');
const chaveCoracaoBpm = ValueKey('coracao-bpm');
const chaveNumeroBpm = ValueKey('numero-bpm');

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

//// BPM ao vivo (esquerda) | "Ao vivo" + media de 5 min (direita), como no
/// modelo. O BPM usa o maior tamanho que deixa as duas colunas lado a lado
/// (60 ou 48 sp, conforme a largura). Quando nem assim cabem (celular
/// estreito, fonte ampliada), "Ao vivo" desce para baixo do BPM, que volta a
/// 60 sp.
///
/// Coracao, numero e "bpm" sao um grupo so: o coracao fica a 8 dp do
/// primeiro algarismo, centrado na altura dos algarismos (cerca de 55% dela),
/// e "bpm" fica na linha de base do numero, sem espaco vazio por dentro, com
/// 1, 2 ou 3 digitos ou "—". O grupo fica centrado numa area de largura fixa
/// (a do grupo com "000", medida na fonte e na escala atuais, com algarismos
/// de mesma largura). Assim a divisoria e a coluna "Ao vivo" nunca se mexem;
/// o grupo so se recentra quando o numero ganha ou perde um digito.
class _LinhaBpm extends StatelessWidget {
  const _LinhaBpm({required this.estado, required this.tom});

  final EstadoAtual estado;
  final TomRisco tom;

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
    final numero = bpm != null ? '${bpm.round()}' : '—';

    final falaBpm = bpm == null ? 'Batimentos: sem leitura agora' : 'Batimentos: $numero bpm';
    final falaAoVivo = bpm == null
        ? 'Ao vivo. Sem leitura de batimentos agora.'
        : 'Ao vivo.${media != null ? ' Média de 5 minutos: ${media.round()} bpm.' : ''}';

    final estiloUnidade = texto.titleSmall!.copyWith(color: cores.tintaSuave);
    final estiloMedia = texto.bodyMedium!.copyWith(color: cores.tintaSuave);
    final valorMedia = texto.titleSmall!.copyWith(fontFeatures: Tipografia.tabular);
    final larguraUnidade = _largura('bpm', estiloUnidade, escala);

    // Medidas do grupo para um tamanho de numero: tudo sai da fonte e da
    // escala atuais, nada depende do valor mostrado.
    ({TextStyle estilo, double icone, double larguraCoracao, double topoCoracao, double area}) medir(
      TextStyle base,
    ) {
      final estilo = base.copyWith(fontFeatures: Tipografia.tabular);
      final pintor = TextPainter(
        text: TextSpan(text: '000', style: estilo),
        textDirection: TextDirection.ltr,
        textScaler: escala,
        maxLines: 1,
      )..layout();
      final linhaDeBase = pintor.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final larguraTres = pintor.width;
      pintor.dispose();
      final algarismos = escala.scale(estilo.fontSize!) * Tipografia.alturaDosAlgarismos;
      final icone = algarismos * FaixaBpm.proporcaoCoracao / FaixaBpm.coracaoAltura;
      final larguraCoracao = icone * FaixaBpm.coracaoLargura;
      return (
        estilo: estilo,
        icone: icone,
        larguraCoracao: larguraCoracao,
        // Centro do coracao na metade da altura dos algarismos
        topoCoracao: linhaDeBase - algarismos / 2 - icone / 2,
        area: larguraCoracao + FaixaBpm.espacoCoracao + larguraTres + FaixaBpm.espacoUnidade + larguraUnidade,
      );
    }

    Widget grupo(TextStyle base) {
      final m = medir(base);
      return Semantics(
        container: true,
        label: falaBpm,
        excludeSemantics: true,
        child: Row(
          key: chaveGrupoBpm,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: m.topoCoracao),
              // A caixa tem a largura do desenho: o espaco ate o numero e
              // o de FaixaBpm.espacoCoracao, sem a margem do icone.
              child: SizedBox(
                key: chaveCoracaoBpm,
                width: m.larguraCoracao,
                height: m.icone,
                child: OverflowBox(
                  maxWidth: m.icone,
                  maxHeight: m.icone,
                  child: Icon(Icons.favorite_rounded, size: m.icone, color: cores.tintaSuave),
                ),
              ),
            ),
            const SizedBox(width: FaixaBpm.espacoCoracao),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(numero, key: chaveNumeroBpm, style: m.estilo, maxLines: 1, softWrap: false),
                const SizedBox(width: FaixaBpm.espacoUnidade),
                Text('bpm', style: estiloUnidade),
              ],
            ),
          ],
        ),
      );
    }

    final aoVivo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.ssid_chart_rounded, size: FaixaBpm.iconeAoVivo, color: cores.tinta),
        const SizedBox(width: FaixaBpm.espacoAoVivo),
        Flexible(child: Text('Ao vivo', style: texto.titleSmall)),
        const SizedBox(width: Espaco.s),
        // Ponto parado (nunca pisca), no azul de "conectado"
        Container(
          width: FaixaBpm.pontoAoVivo,
          height: FaixaBpm.pontoAoVivo,
          decoration: BoxDecoration(color: cores.primaria, shape: BoxShape.circle),
        ),
      ],
    );

    // Lado a lado: coluna como no modelo ("Ao vivo" / "Média de 5 min:" /
    // "96 bpm"). As duas linhas abaixo de "Ao vivo" ocupam sempre a altura
    // da versao completa (a referencia invisivel), com ou sem leitura.
    final direita = Semantics(
      container: true,
      label: falaAoVivo,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          aoVivo,
          const SizedBox(height: FaixaBpm.entreLinhas),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text('Média de 5 min:', style: estiloMedia), Text('000 bpm', style: valorMedia)],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bpm == null)
                      Text('Sem leitura agora.', style: estiloMedia)
                    else if (media != null) ...[
                      Text('Média de 5 min:', style: estiloMedia),
                      Text('${media.round()} bpm', style: valorMedia),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Empilhado: "Ao vivo" e a media centrados embaixo do grupo
    final abaixo = Semantics(
      container: true,
      label: falaAoVivo,
      excludeSemantics: true,
      child: Column(
        children: [
          aoVivo,
          const SizedBox(height: FaixaBpm.entreLinhas),
          if (bpm == null)
            Text('Sem leitura de batimentos agora.', style: estiloMedia, textAlign: TextAlign.center)
          else if (media != null)
            Text.rich(
              TextSpan(
                text: 'Média de 5 min: ',
                style: estiloMedia,
                children: [TextSpan(text: '${media.round()} bpm', style: valorMedia)],
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, restricoes) {
        final larguraMedia = _largura('Média de 5 min:', estiloMedia, escala);
        final larguraAoVivo = FaixaBpm.iconeAoVivo +
            FaixaBpm.espacoAoVivo +
            _largura('Ao vivo', texto.titleSmall!, escala) +
            Espaco.s +
            FaixaBpm.pontoAoVivo;
        final larguraDireita = larguraMedia > larguraAoVivo ? larguraMedia : larguraAoVivo;
        // A disposicao depende so da largura e da fonte, nunca do valor
        bool cabe(TextStyle base) =>
            medir(base).area + FaixaBpm.respiro * 2 + FaixaBpm.divisoria + larguraDireita <= restricoes.maxWidth;

        final ladoALado = [texto.displayLarge!, texto.displayMedium!].where(cabe).firstOrNull;
        if (ladoALado == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(key: chaveAreaBpm, child: Center(child: grupo(texto.displayLarge!))),
              const SizedBox(height: Espaco.s),
              abaixo,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(key: chaveAreaBpm, width: medir(ladoALado).area, child: Center(child: grupo(ladoALado))),
              const SizedBox(width: FaixaBpm.respiro),
              Container(
                key: chaveDivisoriaBpm,
                width: FaixaBpm.divisoria,
                color: tom.texto.withValues(alpha: 0.3),
              ),
              const SizedBox(width: FaixaBpm.respiro),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: direita)),
            ],
          ),
        );
      },
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
