import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/models.dart';
import '../models/resumo.dart';
import '../models/sinais.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/faixa_estado.dart';
import '../widgets/nivel_visual.dart';
import '../widgets/secao.dart';

/// Graficos: os sinais dos ultimos 5 minutos (ao vivo, uma metrica por vez,
/// com o balao de todas as metricas no instante tocado) e as crises por dia
/// nos ultimos 7 dias, pela avaliacao do cuidador. Marcas finas, grade em
/// linha fina solida, texto sempre nas cores de texto (a cor fica so nas
/// marcas).
class GraficosScreen extends StatelessWidget {
  const GraficosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final agora = relogio();
    return EstruturaTela(
      children: [
        const TituloTela('Gráficos'),
        const SizedBox(height: Espaco.xl),
        SecaoSinais(service: service),
        const SizedBox(height: Espaco.l),
        _SecaoSeteDias(service: service, agora: agora),
      ],
    );
  }
}

TextStyle _estiloEixo(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(fontFeatures: Tipografia.tabular);

/// "128 bpm" / "9,4 µS" / "0,12" / "81%" / "—"
String valorComUnidade(Metrica m, double? v) {
  if (v == null) return '—';
  final numero = numeroBr(v, m.casas);
  if (m.unidade.isEmpty) return numero;
  if (m.unidade == '%') return '$numero%';
  return '$numero ${m.unidade}';
}

Color corDaMetrica(BuildContext context, Metrica m) => CoresDados.of(context).metricas[m.index];

/// Balao dos graficos: inverso no claro; superficie elevada com contorno no
/// escuro (sem bloco claro a noite).
BoxDecoration _decoracaoDoBalao(CoresApp cores) => BoxDecoration(
  color: cores.balao.fundo,
  borderRadius: BorderRadius.circular(Raio.controle),
  border: Border.all(color: cores.balaoBorda),
);

// ---------------------------------------------------------------------------
// Sinais ao vivo (ultimos 5 minutos)
// ---------------------------------------------------------------------------

/// Cartao dos sinais ao vivo: seletor de metrica, grafico, faixas de nivel e
/// resumo da metrica escolhida.
class SecaoSinais extends StatefulWidget {
  const SecaoSinais({super.key, required this.service});

  final MqttService service;

  @override
  State<SecaoSinais> createState() => _SecaoSinaisState();
}

class _SecaoSinaisState extends State<SecaoSinais> {
  Metrica _metrica = Metrica.bpm;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final amostras = service.sinaisRecentes;
    final situacao = situacaoDe(service);
    final aoVivo = situacao == SituacaoEstado.aoVivo;
    final ultima = amostras.isEmpty ? null : amostras.last.hora;
    final semConexao = service.brokerStatus != BrokerStatus.conectado;

    final String apoio =
        aoVivo
            ? 'Últimos 5 minutos, ao vivo. Toque ou arraste no gráfico para ver todos os sinais de um instante.'
            : 'Últimos 5 minutos recebidos.';
    final (IconData, String)? aviso =
        aoVivo || ultima == null
            ? null
            : semConexao
            ? (
              Icons.cloud_off_outlined,
              'Sem conexão com o servidor. O gráfico está parado na última leitura, das ${horaMinuto(ultima)}.',
            )
            : (
              Icons.sensors_off_rounded,
              'A pulseira parou de enviar às ${horaMinuto(ultima)}. '
                  'O gráfico mostra os últimos 5 minutos recebidos.',
            );
    final temValor = amostras.any((a) => _metrica.valor(a) != null);

    final Widget corpo;
    if (amostras.length < 2) {
      corpo =
          service.brokerStatus == BrokerStatus.conectando
              ? const EstadoVazio(
                icone: Icons.cloud_sync_outlined,
                titulo: 'Conectando ao servidor…',
                texto: 'O gráfico aparece quando as leituras da pulseira chegarem.',
              )
              : semConexao
              ? const EstadoVazio(
                icone: Icons.cloud_off_outlined,
                titulo: 'Sem conexão com o servidor',
                texto: 'O app tenta reconectar sozinho. O gráfico aparece quando as leituras voltarem a chegar.',
              )
              : const EstadoVazio(
                icone: Icons.monitor_heart_outlined,
                titulo: 'Aguardando leituras ao vivo',
                texto: 'O gráfico aparece quando a pulseira estiver ligada e enviando o estado.',
              );
    } else if (!temValor) {
      corpo = EstadoVazio(
        icone: Icons.sensors_off_rounded,
        titulo: 'Sem leituras de ${_metrica.nome.toLowerCase()}',
        texto: 'Nenhuma leitura desta métrica nos últimos 5 minutos. Escolha outra métrica acima.',
      );
    } else {
      final trechos = trechosDeNivel(amostras);
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GraficoSinais(amostras: amostras, metrica: _metrica, trechos: trechos),
          if (trechos.isNotEmpty) ...[
            const SizedBox(height: Espaco.s),
            _LegendaFaixas(niveis: {for (final t in trechos) t.nivel}),
          ],
          const SizedBox(height: Espaco.l),
          _ResumoMetrica(metrica: _metrica, estatistica: EstatisticaSinal.de(amostras, _metrica)!),
        ],
      );
    }

    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TituloSecao('Sinais da criança', apoio: apoio),
          if (aviso != null) ...[const SizedBox(height: Espaco.m), _Aviso(icone: aviso.$1, texto: aviso.$2)],
          const SizedBox(height: Espaco.m),
          SeletorMetrica(selecionada: _metrica, onSelecionar: (m) => setState(() => _metrica = m)),
          const SizedBox(height: Espaco.m),
          corpo,
        ],
      ),
    );
  }
}

/// Aviso de dados congelados (painel parado ou sem conexao).
class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Espaco.m),
        decoration: BoxDecoration(color: cores.superficieAlta, borderRadius: BorderRadius.circular(Raio.controle)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 20, color: cores.tinta),
            const SizedBox(width: Espaco.s),
            Expanded(
              child: Text(
                texto,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cores.tinta, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seletor da metrica: chips rolaveis com o nome por extenso, a unidade e
/// uma bolinha na cor da serie. O escolhido tem fundo e contorno mais grosso.
class SeletorMetrica extends StatelessWidget {
  const SeletorMetrica({super.key, required this.selecionada, required this.onSelecionar});

  final Metrica selecionada;
  final ValueChanged<Metrica> onSelecionar;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final m in Metrica.values) ...[
            if (m.index > 0) const SizedBox(width: Espaco.s),
            ChoiceChip(
              key: ValueKey('metrica-${m.name}'),
              selected: m == selecionada,
              onSelected: (_) => onSelecionar(m),
              avatar: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: corDaMetrica(context, m), shape: BoxShape.circle),
              ),
              label: Text(m.rotulo),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grafico ao vivo de uma metrica: area leve + linha, faixas de fundo nos
/// momentos de Atencao e Possivel crise, o ultimo valor no fim da linha e o
/// trackball (toque ou arraste) com o balao de todas as metricas.
class GraficoSinais extends StatefulWidget {
  const GraficoSinais({super.key, required this.amostras, required this.metrica, required this.trechos});

  final List<AmostraSinais> amostras;
  final Metrica metrica;
  final List<TrechoNivel> trechos;

  @override
  State<GraficoSinais> createState() => _GraficoSinaisState();
}

class _GraficoSinaisState extends State<GraficoSinais> {
  // O estado chega 1x/s: o trackball fica guardado aqui para a linha e o
  // marcador nao sumirem a cada leitura. So e recriado quando a metrica ou o
  // tema mudam.
  TrackballBehavior? _trackball;
  (Metrica, Color)? _chave;
  ChartSeriesController<AmostraSinais, DateTime>? _controle;

  // Balao: desenhado aqui, no canto oposto ao dedo. (O modelo do trackball
  // do Syncfusion some quando passa de metade da altura do grafico, e o
  // balao tem uma linha por metrica.) Fica num ValueNotifier: mover o dedo
  // redesenha so o balao, nao o grafico (o que apagaria a linha do
  // trackball).
  final _balao = ValueNotifier<({AmostraSinais amostra, bool dedoADireita})?>(null);
  Timer? _esconder;

  @override
  void dispose() {
    _esconder?.cancel();
    _balao.dispose();
    super.dispose();
  }

  /// Leitura mais perto do dedo (posicao no grafico).
  void _acompanhar(Offset local, double largura) {
    final ms = _controle?.pixelToPoint(local).xValue;
    if (ms == null || widget.amostras.isEmpty) return;
    var perto = widget.amostras.first;
    for (final a in widget.amostras) {
      if ((a.hora.millisecondsSinceEpoch - ms).abs() < (perto.hora.millisecondsSinceEpoch - ms).abs()) perto = a;
    }
    _esconder?.cancel();
    _balao.value = (amostra: perto, dedoADireita: local.dx > largura / 2);
  }

  /// Dedo fora da tela: o balao fica mais alguns segundos para a leitura.
  void _soltar() {
    _esconder?.cancel();
    _esconder = Timer(Grafico.balaoVisivel, () => _balao.value = null);
  }

  TrackballBehavior _trackballPara(BuildContext context, Color cor) {
    final chave = (widget.metrica, cor);
    if (_trackball != null && _chave == chave) return _trackball!;
    final cores = CoresApp.of(context);
    _chave = chave;
    return _trackball = TrackballBehavior(
      enable: true,
      activationMode: ActivationMode.singleTap,
      tooltipDisplayMode: TrackballDisplayMode.nearestPoint,
      hideDelay: Grafico.balaoVisivel.inMilliseconds.toDouble(),
      lineColor: cores.tintaSuave,
      lineWidth: 1,
      // Modelo vazio: o Syncfusion desenha so a linha e o marcador; o balao
      // e o deste widget.
      builder: (_, _) => const SizedBox.shrink(),
      tooltipSettings: const InteractiveTooltip(arrowLength: 0, arrowWidth: 0, borderWidth: 0),
      markerSettings: TrackballMarkerSettings(
        markerVisibility: TrackballVisibilityMode.visible,
        color: cor,
        borderColor: cores.superficie,
        borderWidth: 2,
        width: Grafico.marcador,
        height: Grafico.marcador,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context);
    final metrica = widget.metrica;
    final amostras = widget.amostras;
    final cor = corDaMetrica(context, metrica);
    final valores = amostras.map(metrica.valor).whereType<double>();
    final faixa = metrica.faixa.ajustada(valores);
    final casasEixo = faixa.intervalo < 1 ? 2 : 0;
    AmostraSinais? ultima;
    for (final a in amostras.reversed) {
      if (metrica.valor(a) != null) {
        ultima = a;
        break;
      }
    }
    final fim = amostras.last.hora;
    final est = EstatisticaSinal.de(amostras, metrica)!;
    // O balao (9 linhas) precisa caber inteiro na area do grafico
    final altura = max(Grafico.aoVivo, escala.scale(18.2) * 9 + 64);

    final faixasFala = [
      for (final t in widget.trechos)
        'Nível ${NivelVisual.de(t.nivel).rotulo} das ${horaMinuto(t.inicio)} às ${horaMinuto(t.fim)}.',
    ].join(' ');

    final grafico = _grafico(context, cor, faixa, casasEixo, ultima, fim);
    return Semantics(
      container: true,
      label:
          'Gráfico de ${metrica.nome.toLowerCase()} nos últimos 5 minutos: '
          'atual ${valorComUnidade(metrica, est.atual)}, mínima ${valorComUnidade(metrica, est.minima)}, '
          'máxima ${valorComUnidade(metrica, est.maxima)}, média ${valorComUnidade(metrica, est.media)}.'
          '${faixasFala.isEmpty ? '' : ' $faixasFala'}',
      excludeSemantics: true,
      child: SizedBox(
        height: altura,
        child: LayoutBuilder(
          builder:
              (context, restricoes) => Listener(
                onPointerDown: (e) => _acompanhar(e.localPosition, restricoes.maxWidth),
                onPointerMove: (e) => _acompanhar(e.localPosition, restricoes.maxWidth),
                onPointerUp: (_) => _soltar(),
                onPointerCancel: (_) => _soltar(),
                child: Stack(
                  children: [
                    Positioned.fill(child: grafico),
                    ValueListenableBuilder(
                      valueListenable: _balao,
                      builder: (context, balao, _) {
                        if (balao == null) return const SizedBox.shrink();
                        return Positioned(
                          top: 0,
                          // Longe do dedo; do lado esquerdo, depois dos rotulos do eixo
                          left: balao.dedoADireita ? Grafico.margemDoBalao : null,
                          right: balao.dedoADireita ? null : 0,
                          child: IgnorePointer(child: BalaoSinais(amostra: balao.amostra, destaque: metrica)),
                        );
                      },
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _grafico(
    BuildContext context,
    Color cor,
    FaixaEixo faixa,
    int casasEixo,
    AmostraSinais? ultima,
    DateTime fim,
  ) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final eixo = _estiloEixo(context);
    final metrica = widget.metrica;
    return SfCartesianChart(
      // Um grafico por metrica: com a mesma lista de dados, o Syncfusion nao
      // refaz a serie quando so o yValueMapper muda.
      key: ValueKey(metrica),
      plotAreaBorderWidth: 0,
      margin: EdgeInsets.zero,
      primaryXAxis: DateTimeAxis(
        dateFormat: DateFormat('HH:mm'),
        intervalType: DateTimeIntervalType.minutes,
        interval: 1,
        // Janela de 5 min terminando um pouco depois da ultima leitura
        // (folga para o ponto final e o valor nao encostarem na borda).
        minimum: fim.subtract(MqttService.janelaSinais),
        maximum: fim.add(const Duration(seconds: 20)),
        majorGridLines: const MajorGridLines(width: 0),
        axisLine: AxisLine(width: 1, color: cores.divisoria),
        majorTickLines: const MajorTickLines(size: 0),
        labelStyle: eixo,
        plotBands: [
          for (final t in widget.trechos)
            PlotBand(start: t.inicio, end: t.fim, color: NivelVisual.de(t.nivel).tom(context).fundo, borderWidth: 0),
        ],
      ),
      primaryYAxis: NumericAxis(
        minimum: faixa.minimo,
        maximum: faixa.maximo,
        interval: faixa.intervalo,
        title: AxisTitle(text: metrica.unidadeExtensa ?? metrica.unidade, textStyle: eixo),
        labelStyle: eixo,
        axisLabelFormatter: (args) => ChartAxisLabel(numeroBr(args.value.toDouble(), casasEixo), eixo),
        majorGridLines: MajorGridLines(width: 1, color: cores.divisoria),
        axisLine: const AxisLine(width: 0),
        majorTickLines: const MajorTickLines(size: 0),
      ),
      trackballBehavior: _trackballPara(context, cor),
      series: <CartesianSeries<AmostraSinais, DateTime>>[
        SplineAreaSeries<AmostraSinais, DateTime>(
          onRendererCreated: (controle) => _controle = controle,
          dataSource: widget.amostras,
          xValueMapper: (a, _) => a.hora,
          yValueMapper: (a, _) => metrica.valor(a),
          color: cor.withValues(alpha: 0.12),
          borderColor: cor,
          borderWidth: Grafico.linha,
          splineType: SplineType.monotonic,
          emptyPointSettings: const EmptyPointSettings(mode: EmptyPointMode.gap),
          animationDuration: 0, // atualiza 1x/s: sem animar a cada ponto
        ),
      ],
      // Ultima leitura: ponto + valor no fim da linha. Anotacoes em vez de
      // dataLabelSettings: os rotulos de dados do Syncfusion 28 falham ao
      // desmontar no Flutter 3.47.
      annotations: [
        if (ultima != null) ...[
          CartesianChartAnnotation(
            coordinateUnit: CoordinateUnit.point,
            x: ultima.hora,
            y: metrica.valor(ultima),
            widget: Container(
              width: Grafico.marcador,
              height: Grafico.marcador,
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
                border: Border.all(color: cores.superficie, width: 2),
              ),
            ),
          ),
          CartesianChartAnnotation(
            coordinateUnit: CoordinateUnit.point,
            x: ultima.hora,
            y: metrica.valor(ultima),
            horizontalAlignment: ChartAlignment.far,
            verticalAlignment: ChartAlignment.far,
            widget: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                numeroBr(metrica.valor(ultima)!, metrica.casas),
                style: texto.labelMedium!.copyWith(color: cores.tinta, fontFeatures: Tipografia.tabular),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Balao do trackball: horario, nivel e TODAS as metricas do instante. A
/// metrica do grafico vem em destaque, com um traco da cor da serie.
class BalaoSinais extends StatelessWidget {
  const BalaoSinais({super.key, required this.amostra, required this.destaque});

  final AmostraSinais amostra;
  final Metrica destaque;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final visual = NivelVisual.de(amostra.nivel);
    final tinta = cores.balao.texto;
    final rotulo = texto.labelSmall!.copyWith(color: tinta, fontSize: 13);
    final valor = texto.labelMedium!.copyWith(color: tinta, fontFeatures: Tipografia.tabular);
    return Container(
      padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.s, Espaco.m, Espaco.s),
      decoration: _decoracaoDoBalao(cores),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(horaMinutoSegundo(amostra.hora), style: valor.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: Espaco.s),
              Icon(visual.icone, size: 16, color: tinta),
              const SizedBox(width: Espaco.xs),
              Text(visual.rotulo, style: valor),
            ],
          ),
          const SizedBox(height: Espaco.xs),
          Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final m in Metrica.values)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: Espaco.m),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            color: m == destaque ? corDaMetrica(context, m) : Colors.transparent,
                          ),
                          const SizedBox(width: Espaco.xs),
                          Text(m.curto, style: m == destaque ? rotulo.copyWith(fontWeight: FontWeight.w700) : rotulo),
                        ],
                      ),
                    ),
                    Text(
                      valorComUnidade(m, m.valor(amostra)),
                      textAlign: TextAlign.end,
                      style: m == destaque ? valor.copyWith(fontWeight: FontWeight.w700) : valor,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Legenda das faixas de fundo: amostra + icone + nome do nivel.
class _LegendaFaixas extends StatelessWidget {
  const _LegendaFaixas({required this.niveis});

  final Set<NivelRisco> niveis;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    Widget item(NivelVisual visual) {
      final tom = visual.tom(context);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 14,
            decoration: BoxDecoration(
              color: tom.fundo,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: tom.grafico),
            ),
          ),
          const SizedBox(width: 6),
          Icon(visual.icone, size: 16, color: tom.texto),
          const SizedBox(width: Espaco.xs),
          Flexible(child: Text('Momentos em ${visual.rotulo}', style: texto.bodySmall)),
        ],
      );
    }

    return ExcludeSemantics(
      child: Wrap(
        spacing: Espaco.l,
        runSpacing: Espaco.xs,
        children: [
          if (niveis.contains(NivelRisco.atencao)) item(NivelVisual.atencao),
          if (niveis.contains(NivelRisco.altoRisco)) item(NivelVisual.possivelCrise),
        ],
      ),
    );
  }
}

/// Atual, minima, maxima e media dos 5 min da metrica escolhida. Quatro
/// colunas; duas por linha quando os valores nao cabem (fonte ampliada).
class _ResumoMetrica extends StatelessWidget {
  const _ResumoMetrica({required this.metrica, required this.estatistica});

  final Metrica metrica;
  final EstatisticaSinal estatistica;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final escala = MediaQuery.textScalerOf(context);
    final estiloValor = texto.titleSmall!.copyWith(fontFeatures: Tipografia.tabular);
    final itens = [
      ('Atual', estatistica.atual),
      ('Mínima', estatistica.minima),
      ('Máxima', estatistica.maxima),
      ('Média', estatistica.media),
    ];
    return LayoutBuilder(
      builder: (context, restricoes) {
        double largura(String s, TextStyle estilo) {
          final medida = TextPainter(
            text: TextSpan(text: s, style: estilo),
            textDirection: TextDirection.ltr,
            textScaler: escala,
            maxLines: 1,
          )..layout();
          final w = medida.width;
          medida.dispose();
          return w;
        }

        final maior = itens.map((i) => largura(valorComUnidade(metrica, i.$2), estiloValor)).reduce(max);
        final colunas = (maior + Espaco.s) * 4 <= restricoes.maxWidth ? 4 : 2;
        final larguraItem = restricoes.maxWidth / colunas;
        return Wrap(
          runSpacing: Espaco.m,
          children: [
            for (final (rotulo, valor) in itens)
              SizedBox(
                width: larguraItem,
                child: Semantics(
                  container: true,
                  label: '$rotulo: ${valorComUnidade(metrica, valor)}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rotulo, style: texto.bodySmall),
                      Text(valorComUnidade(metrica, valor), style: estiloValor),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Crises por dia (ultimos 7 dias), pela avaliacao do cuidador
// ---------------------------------------------------------------------------

class _SecaoSeteDias extends StatelessWidget {
  const _SecaoSeteDias({required this.service, required this.agora});

  final MqttService service;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final dias = ultimos7Dias(service.historico, agora);
    final confirmadas = dias.fold<int>(0, (s, d) => s + d.contagem.confirmadas);
    final pendentes = dias.fold<int>(0, (s, d) => s + d.contagem.pendentes);
    final noMes = contagemNoMes(contagemPorDia(service.historico), agora.year, agora.month);
    final mes = 'Em ${nomeDoMes(agora.month)}: ${contarConfirmadas(noMes.confirmadas)}.';
    final resumo =
        confirmadas + pendentes == 0
            ? 'Nenhuma crise confirmada ou aguardando confirmação nos últimos 7 dias. $mes'
            : 'Nos últimos 7 dias: ${contarConfirmadas(confirmadas)}'
                '${pendentes > 0 ? ' e $pendentes aguardando sua confirmação' : ''}. $mes';

    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao(
            'Crises nos últimos 7 dias',
            apoio: 'Contadas pela sua avaliação. Episódios descartados não entram.',
          ),
          const SizedBox(height: Espaco.m),
          Text(resumo, style: texto.bodyMedium),
          const SizedBox(height: Espaco.l),
          if (confirmadas + pendentes == 0)
            const EstadoVazio(
              icone: Icons.insights_outlined,
              titulo: 'Nenhuma crise nos últimos 7 dias',
              texto: 'Os episódios que você confirmar, e os que aguardam sua confirmação, aparecem aqui.',
            )
          else ...[
            GraficoSeteDias(dias: dias),
            const SizedBox(height: Espaco.m),
            const _LegendaSeteDias(),
          ],
        ],
      ),
    );
  }
}

String _rotuloDia(List<DiaResumo> dias, int i) => i == dias.length - 1 ? 'Hoje' : dias[i].rotulo;

/// Listras diagonais de "aguardando confirmacao" (barras e legenda).
Shader listrasPendentes(Rect area, CoresDados dados) => ui.Gradient.linear(
  area.topLeft,
  area.topLeft + const Offset(Grafico.listra, Grafico.listra),
  [dados.barraPendente, dados.barraPendente, dados.barraPendenteListra, dados.barraPendenteListra],
  [0, 0.6, 0.6, 1],
  TileMode.repeated,
);

/// Barras empilhadas por dia: crises confirmadas (cor solida, embaixo) e
/// possiveis crises aguardando confirmacao (clara com listras, em cima).
/// Descartados nao entram. Tocar numa barra mostra os totais e a duracao
/// somada do dia.
class GraficoSeteDias extends StatelessWidget {
  const GraficoSeteDias({super.key, required this.dias});

  final List<DiaResumo> dias;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final dados = CoresDados.of(context);
    final texto = Theme.of(context).textTheme;
    final maior = dias.fold<int>(0, (m, d) => max(m, d.contagem.total));
    String falaDia(DiaResumo d) {
      final c = d.contagem;
      if (c.total == 0) return 'nenhuma';
      return [
        if (c.confirmadas > 0) contarConfirmadas(c.confirmadas),
        if (c.pendentes > 0) contarPendentes(c.pendentes),
      ].join(' e ');
    }

    final fala = [for (var i = 0; i < dias.length; i++) '${_rotuloDia(dias, i)}, ${falaDia(dias[i])}'].join('; ');

    return Semantics(
      container: true,
      label: 'Gráfico de crises por dia: $fala.',
      excludeSemantics: true,
      child: SizedBox(
        height: Grafico.seteDias,
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          margin: EdgeInsets.zero,
          primaryXAxis: CategoryAxis(
            majorGridLines: const MajorGridLines(width: 0),
            axisLine: AxisLine(width: 1, color: cores.divisoria),
            majorTickLines: const MajorTickLines(size: 0),
            labelStyle: _estiloEixo(context),
          ),
          // O total de cada dia esta na ponta da barra: o eixo Y seria
          // repeticao.
          primaryYAxis: NumericAxis(
            isVisible: false,
            minimum: 0,
            maximum: max(1, maior) * 1.3,
            majorGridLines: const MajorGridLines(width: 0),
          ),
          tooltipBehavior: TooltipBehavior(
            enable: true,
            animationDuration: Movimento.de(context, Movimento.curto).inMilliseconds,
            builder: (dado, ponto, serie, indice, _) {
              final d = dado as DiaResumo;
              final c = d.contagem;
              final linhas = [
                indice == dias.length - 1 ? 'Hoje, ${dataCurta(d.dia)}' : dataCurta(d.dia),
                contarConfirmadas(c.confirmadas),
                c.pendentes == 0 ? 'Nenhuma aguardando confirmação' : '${c.pendentes} aguardando confirmação',
                if (c.duracaoS > 0) 'Duração somada: ${duracao(c.duracaoS)}',
              ];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.s),
                decoration: _decoracaoDoBalao(cores),
                child: Text(linhas.join('\n'), style: texto.labelMedium!.copyWith(color: cores.balao.texto)),
              );
            },
          ),
          series: <CartesianSeries<DiaResumo, String>>[
            StackedColumnSeries<DiaResumo, String>(
              dataSource: dias,
              xValueMapper: (d, i) => _rotuloDia(dias, i),
              yValueMapper: (d, _) => d.contagem.confirmadas == 0 ? null : d.contagem.confirmadas,
              color: dados.barraConfirmada,
              // Respiro de 2 dp entre os segmentos (cor da superficie)
              borderColor: cores.superficie,
              borderWidth: 2,
              width: 0.5,
              spacing: 0,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              animationDuration: Movimento.de(context, Movimento.medio).inMilliseconds.toDouble(),
            ),
            StackedColumnSeries<DiaResumo, String>(
              dataSource: dias,
              xValueMapper: (d, i) => _rotuloDia(dias, i),
              yValueMapper: (d, _) => d.contagem.pendentes == 0 ? null : d.contagem.pendentes,
              color: dados.barraPendente,
              onCreateShader: (detalhes) => listrasPendentes(detalhes.rect, dados),
              borderColor: cores.superficie,
              borderWidth: 2,
              width: 0.5,
              spacing: 0,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              animationDuration: Movimento.de(context, Movimento.medio).inMilliseconds.toDouble(),
            ),
          ],
          // Total na ponta de cada barra (anotacao: ver o grafico ao vivo).
          annotations: [
            for (var i = 0; i < dias.length; i++)
              if (dias[i].contagem.total > 0)
                CartesianChartAnnotation(
                  coordinateUnit: CoordinateUnit.point,
                  x: _rotuloDia(dias, i),
                  y: dias[i].contagem.total,
                  verticalAlignment: ChartAlignment.far,
                  widget: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${dias[i].contagem.total}', style: texto.labelMedium!.copyWith(color: cores.tinta)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _LegendaSeteDias extends StatelessWidget {
  const _LegendaSeteDias();

  @override
  Widget build(BuildContext context) {
    final dados = CoresDados.of(context);
    final texto = Theme.of(context).textTheme;
    Widget item(Widget amostra, String rotulo) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [amostra, const SizedBox(width: 6), Flexible(child: Text(rotulo, style: texto.bodySmall))],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: Espaco.l,
        runSpacing: Espaco.s,
        children: [
          item(
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: dados.barraConfirmada, borderRadius: BorderRadius.circular(3)),
            ),
            'Crise confirmada',
          ),
          item(
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(size: const Size(14, 14), painter: _Listras(dados)),
            ),
            'Possível crise aguardando confirmação',
          ),
        ],
      ),
    );
  }
}

class _Listras extends CustomPainter {
  const _Listras(this.dados);

  final CoresDados dados;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(area, Paint()..shader = listrasPendentes(area, dados));
  }

  @override
  bool shouldRepaint(_Listras antigo) => antigo.dados != dados;
}
