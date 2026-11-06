import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/models.dart';
import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/nivel_visual.dart';
import '../widgets/secao.dart';

/// Graficos: BPM dos ultimos 5 minutos (ao vivo) e episodios por dia nos
/// ultimos 7 dias. Marcas finas, grade em linha fina solida, texto sempre nas
/// cores de texto (a cor fica so nas marcas).
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
        _SecaoBpm(service: service),
        const SizedBox(height: Espaco.l),
        _SecaoEpisodios(service: service, agora: agora),
      ],
    );
  }
}

TextStyle _estiloEixo(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(fontFeatures: Tipografia.tabular);

// ---------------------------------------------------------------------------
// Frequencia cardiaca (ultimos 5 minutos)
// ---------------------------------------------------------------------------

class _SecaoBpm extends StatelessWidget {
  const _SecaoBpm({required this.service});

  final MqttService service;

  @override
  Widget build(BuildContext context) {
    final pontos = service.bpmRecentes;
    double? media = service.estadoAoVivo ? service.estado?.mediaBpm5min : null;
    if (media == null && pontos.isNotEmpty) {
      media = pontos.map((p) => p.bpm).reduce((a, b) => a + b) / pontos.length;
    }
    final String apoio;
    if (service.estadoAoVivo) {
      apoio = 'Últimos 5 minutos, ao vivo.${media != null ? ' Média: ${media.round()} bpm.' : ''}';
    } else {
      apoio = 'Últimos 5 minutos recebidos. Sem leitura ao vivo agora.';
    }
    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TituloSecao('Frequência cardíaca', apoio: apoio),
          const SizedBox(height: Espaco.l),
          if (pontos.length < 2)
            const EstadoVazio(
              icone: Icons.monitor_heart_outlined,
              titulo: 'Aguardando leituras ao vivo',
              texto: 'O gráfico aparece quando o painel (site) estiver aberto e enviando o estado.',
            )
          else
            _GraficoBpm(pontos: pontos),
        ],
      ),
    );
  }
}

class _GraficoBpm extends StatelessWidget {
  const _GraficoBpm({required this.pontos});

  final List<BpmPonto> pontos;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final eixo = _estiloEixo(context);
    final valores = pontos.map((p) => p.bpm);
    final menor = valores.reduce(min);
    final maior = valores.reduce(max);
    final minimo = min(40.0, (menor / 20).floor() * 20.0);
    final maximo = max(120.0, (maior / 20).ceil() * 20.0);
    final ultimo = pontos.last;

    return Semantics(
      container: true,
      label: 'Gráfico da frequência cardíaca nos últimos 5 minutos: mínima ${menor.round()}, '
          'máxima ${maior.round()}, última leitura ${ultimo.bpm.round()} batimentos por minuto, '
          'às ${horaMinuto(ultimo.hora)}.',
      excludeSemantics: true,
      child: SizedBox(
        height: 220,
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          margin: EdgeInsets.zero,
          primaryXAxis: DateTimeAxis(
            dateFormat: DateFormat('HH:mm'),
            intervalType: DateTimeIntervalType.minutes,
            interval: 1,
            // Janela de 5 min terminando um pouco depois da ultima leitura
            // (folga para o ponto final e o valor nao encostarem na borda).
            minimum: ultimo.hora.subtract(MqttService.janelaBpm),
            maximum: ultimo.hora.add(const Duration(seconds: 20)),
            majorGridLines: const MajorGridLines(width: 0),
            axisLine: AxisLine(width: 1, color: cores.divisoria),
            majorTickLines: const MajorTickLines(size: 0),
            labelStyle: eixo,
          ),
          primaryYAxis: NumericAxis(
            minimum: minimo,
            maximum: maximo,
            interval: 20,
            title: AxisTitle(text: 'bpm', textStyle: eixo),
            labelStyle: eixo,
            majorGridLines: MajorGridLines(width: 1, color: cores.divisoria),
            axisLine: const AxisLine(width: 0),
            majorTickLines: const MajorTickLines(size: 0),
          ),
          trackballBehavior: TrackballBehavior(
            enable: true,
            activationMode: ActivationMode.singleTap,
            tooltipDisplayMode: TrackballDisplayMode.nearestPoint,
            lineColor: cores.tintaSuave,
            lineWidth: 1,
            markerSettings: TrackballMarkerSettings(
              markerVisibility: TrackballVisibilityMode.visible,
              color: cores.primaria,
              borderColor: cores.superficie,
              borderWidth: 2,
              width: 10,
              height: 10,
            ),
            tooltipSettings: InteractiveTooltip(
              format: 'point.y bpm',
              decimalPlaces: 0,
              color: cores.tinta,
              borderWidth: 0,
              textStyle: texto.labelMedium!.copyWith(color: cores.fundo),
            ),
          ),
          series: <CartesianSeries<BpmPonto, DateTime>>[
            SplineAreaSeries<BpmPonto, DateTime>(
              dataSource: pontos,
              xValueMapper: (p, _) => p.hora,
              yValueMapper: (p, _) => p.bpm,
              color: cores.primaria.withValues(alpha: 0.10),
              borderColor: cores.primaria,
              borderWidth: 2,
              splineType: SplineType.monotonic,
              animationDuration: 0, // atualiza 1x/s: sem animar a cada ponto
            ),
            // Ponto final: a leitura mais recente
            ScatterSeries<BpmPonto, DateTime>(
              dataSource: [ultimo],
              xValueMapper: (p, _) => p.hora,
              yValueMapper: (p, _) => p.bpm,
              color: cores.primaria,
              borderColor: cores.superficie,
              borderWidth: 2,
              markerSettings: const MarkerSettings(width: 10, height: 10, shape: DataMarkerType.circle),
              animationDuration: 0,
              enableTooltip: false,
            ),
          ],
          // Valor no fim da linha. Anotacao em vez de dataLabelSettings: os
          // rotulos de dados do Syncfusion 28 falham ao desmontar no Flutter 3.47.
          annotations: [
            CartesianChartAnnotation(
              coordinateUnit: CoordinateUnit.point,
              x: ultimo.hora,
              y: ultimo.bpm,
              horizontalAlignment: ChartAlignment.far,
              verticalAlignment: ChartAlignment.far,
              widget: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${ultimo.bpm.round()}', style: texto.labelMedium!.copyWith(color: cores.tinta)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episodios por dia (ultimos 7 dias)
// ---------------------------------------------------------------------------

class _SecaoEpisodios extends StatelessWidget {
  const _SecaoEpisodios({required this.service, required this.agora});

  final MqttService service;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final dias = ultimos7Dias(service.historico, agora);
    final total = dias.fold<int>(0, (soma, d) => soma + d.total);
    final inicio = dias.first.dia;
    final crises = service.historico
        .where((e) => !e.inicio.isBefore(inicio) && e.nivelMaximo == NivelRisco.altoRisco)
        .length;
    final noMes = episodiosNoMes(service.historico, agora);
    final mes = 'Em ${nomeDoMes(agora.month)}: ${contarEpisodios(noMes)}.';
    final resumo = total == 0
        ? mes
        : '${_maiuscula(contarEpisodios(total))} nos últimos 7 dias'
            '${crises > 0 ? ', ${crises == 1 ? '1 de possível crise' : '$crises de possível crise'}' : ''}. $mes';

    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao(
            'Episódios por dia',
            apoio: 'Últimos 7 dias. A cor mostra o nível mais alto do dia.',
          ),
          const SizedBox(height: Espaco.m),
          Text(resumo, style: texto.bodyMedium),
          const SizedBox(height: Espaco.l),
          if (total == 0)
            const EstadoVazio(
              icone: Icons.insights_outlined,
              titulo: 'Nenhum episódio nos últimos 7 dias',
              texto: 'Os episódios aparecem aqui quando o painel detectar sinais de atenção ou de possível crise.',
            )
          else ...[
            _GraficoEpisodios(dias: dias),
            const SizedBox(height: Espaco.m),
            const _Legenda(),
          ],
        ],
      ),
    );
  }

  static String _maiuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

String _rotuloDia(List<DiaResumo> dias, int i) => i == dias.length - 1 ? 'Hoje' : dias[i].rotulo;

class _GraficoEpisodios extends StatelessWidget {
  const _GraficoEpisodios({required this.dias});

  final List<DiaResumo> dias;

  Color _corDoDia(BuildContext context, DiaResumo d) {
    final cores = CoresApp.of(context);
    return switch (d.nivelMaximo) {
      NivelRisco.altoRisco => cores.crise.grafico,
      NivelRisco.atencao => cores.atencao.grafico,
      _ => cores.calmo.grafico, // dia sem episodio: barra de altura zero
    };
  }

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final maior = dias.fold<int>(0, (m, d) => max(m, d.total));
    final fala = [
      for (var i = 0; i < dias.length; i++)
        '${_rotuloDia(dias, i)}, ${contarEpisodios(dias[i].total)}'
            '${dias[i].nivelMaximo != null ? ' (${NivelVisual.de(dias[i].nivelMaximo!).rotulo})' : ''}',
    ].join('; ');

    return Semantics(
      container: true,
      label: 'Gráfico de episódios por dia: $fala.',
      excludeSemantics: true,
      child: SizedBox(
        height: 200,
        child: SfCartesianChart(
          plotAreaBorderWidth: 0,
          margin: EdgeInsets.zero,
          primaryXAxis: CategoryAxis(
            majorGridLines: const MajorGridLines(width: 0),
            axisLine: AxisLine(width: 1, color: cores.divisoria),
            majorTickLines: const MajorTickLines(size: 0),
            labelStyle: _estiloEixo(context),
          ),
          // Todo valor diferente de zero tem rotulo na ponta da barra: o eixo Y
          // seria repeticao.
          primaryYAxis: NumericAxis(
            isVisible: false,
            minimum: 0,
            maximum: max(1, maior) * 1.3,
            majorGridLines: const MajorGridLines(width: 0),
          ),
          tooltipBehavior: TooltipBehavior(
            enable: true,
            builder: (dado, ponto, serie, indice, _) {
              final d = dado as DiaResumo;
              final nivel = d.nivelMaximo != null ? '\nNível mais alto: ${NivelVisual.de(d.nivelMaximo!).rotulo}' : '';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.s),
                decoration: BoxDecoration(color: cores.tinta, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${_rotuloDia(dias, indice)}: ${contarEpisodios(d.total)}$nivel',
                  style: texto.labelMedium!.copyWith(color: cores.fundo),
                ),
              );
            },
          ),
          series: <CartesianSeries<DiaResumo, String>>[
            ColumnSeries<DiaResumo, String>(
              dataSource: dias,
              xValueMapper: (d, i) => _rotuloDia(dias, i),
              yValueMapper: (d, _) => d.total,
              pointColorMapper: (d, _) => _corDoDia(context, d),
              width: 0.5,
              spacing: 0,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              animationDuration: Movimento.de(context, Movimento.medio).inMilliseconds.toDouble(),
            ),
          ],
          // Valor na ponta de cada barra (anotacao: ver o grafico de BPM).
          annotations: [
            for (var i = 0; i < dias.length; i++)
              if (dias[i].total > 0)
                CartesianChartAnnotation(
                  coordinateUnit: CoordinateUnit.point,
                  x: _rotuloDia(dias, i),
                  y: dias[i].total,
                  verticalAlignment: ChartAlignment.far,
                  widget: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${dias[i].total}', style: texto.labelMedium!.copyWith(color: cores.tinta)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Legenda: amostra da cor + nome do nivel (texto na cor de texto). Episodio
/// sempre comeca em Atencao, por isso "Calmo" nao aparece aqui.
class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    Widget item(NivelVisual visual) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: visual.tom(context).grafico, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(visual.rotulo, style: texto.bodySmall),
          ],
        );
    return ExcludeSemantics(
      child: Wrap(
        spacing: Espaco.l,
        runSpacing: Espaco.s,
        children: [item(NivelVisual.atencao), item(NivelVisual.possivelCrise)],
      ),
    );
  }
}
