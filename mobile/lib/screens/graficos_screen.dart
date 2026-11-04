import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../models/models.dart';
import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';

class GraficosScreen extends StatelessWidget {
  const GraficosScreen({super.key});

  static const _corAlto = Color(0xFFE53935);
  static const _corModerado = Color(0xFFFFB300);
  static const _corCalmo = Color(0xFF43A047);

  // Corpo
  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final agora = DateTime.now();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GRÁFICOS',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        color: Color(0xFF111111),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildStatsRow(service, agora),
                    const SizedBox(height: 20),
                    _buildStressBarChart(ultimos7Dias(service.historico, agora)),
                    const SizedBox(height: 24),
                    _buildHeartRateChart(service.bpmRecentes),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8F5E9),
              border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
            ),
            child: const Icon(Icons.person, size: 20, color: Color(0xFF4CAF50)),
          ),
          const SizedBox(width: 12),
          const Text(
            'PUZZLE BAND',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Color(0xFF222222),
            ),
          ),
        ],
      ),
    );
  }

  // Caixas de status
  Widget _buildStatsRow(MqttService service, DateTime agora) {
    double? media = service.estadoAoVivo ? service.estado?.mediaBpm5min : null;
    final pontos = service.bpmRecentes;
    if (media == null && pontos.isNotEmpty) {
      media = pontos.map((p) => p.bpm).reduce((a, b) => a + b) / pontos.length;
    }
    return Row(
      children: [
        _buildStatBox(label: 'MÉDIA BPM\n5 MIN', value: media != null ? media.round().toString() : '—', unit: 'bpm'),
        const SizedBox(width: 16),
        _buildStatBox(
          label: 'PICOS DE ESTRESSE\nMÊS',
          value: episodiosNoMes(service.historico, agora).toString(),
          unit: '',
        ),
      ],
    );
  }

  Widget _buildStatBox({
    required String label,
    required String value,
    required String unit,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF888888),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111111),
                    height: 1.1,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF888888),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Estado vazio amigavel (sem dados para o grafico)
  Widget _buildEmpty({required IconData icon, required String title, required String hint}) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF666666)),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Frequência Cardíaca (ao vivo, a partir do tópico estado)
  Widget _buildHeartRateChart(List<BpmPonto> pontos) {
    final maiorBpm = pontos.isEmpty ? 0.0 : pontos.map((p) => p.bpm).reduce(max);
    final maximo = max(120.0, (maiorBpm / 20).ceil() * 20.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frequência Cardíaca — Últimos 5 Minutos (ao vivo)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 4),
          if (pontos.length < 2)
            _buildEmpty(
              icon: Icons.monitor_heart_outlined,
              title: 'Aguardando leituras ao vivo',
              hint: 'O gráfico aparece quando o painel (site) estiver aberto e enviando o estado.',
            )
          else
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                margin: const EdgeInsets.only(top: 8),
                primaryXAxis: DateTimeAxis(
                  dateFormat: DateFormat('HH:mm'),
                  intervalType: DateTimeIntervalType.minutes,
                  majorGridLines: const MajorGridLines(width: 0),
                  labelStyle: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                  axisLine: const AxisLine(width: 0),
                  majorTickLines: const MajorTickLines(size: 0),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 40,
                  maximum: maximo,
                  interval: 20,
                  labelStyle: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                  majorGridLines: const MajorGridLines(
                    width: 1,
                    color: Color(0xFFEEEEEE),
                    dashArray: [4, 4],
                  ),
                  axisLine: const AxisLine(width: 0),
                  majorTickLines: const MajorTickLines(size: 0),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  format: 'point.y bpm',
                  color: const Color(0xFF222222),
                  textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                series: [
                  SplineAreaSeries<BpmPonto, DateTime>(
                    dataSource: pontos,
                    xValueMapper: (p, _) => p.hora,
                    yValueMapper: (p, _) => p.bpm,
                    color: const Color(0xFFE53935).withValues(alpha: 0.15),
                    borderColor: const Color(0xFFE53935),
                    borderWidth: 2.5,
                    splineType: SplineType.monotonic,
                    animationDuration: 0, // atualiza 1x/s: sem animar a cada ponto
                    markerSettings: MarkerSettings(
                      isVisible: pontos.length <= 30,
                      height: 6,
                      width: 6,
                      color: const Color(0xFFE53935),
                      borderColor: Colors.white,
                      borderWidth: 1.5,
                      shape: DataMarkerType.circle,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _corDoDia(DiaResumo d) => switch (d.nivelMaximo) {
        NivelRisco.altoRisco => _corAlto,
        NivelRisco.atencao => _corModerado,
        _ => _corCalmo,
      };

  // Episodios por dia (historico, ultimos 7 dias)
  Widget _buildStressBarChart(List<DiaResumo> dias) {
    final total = dias.fold<int>(0, (soma, d) => soma + d.total);
    final maior = dias.fold<int>(0, (m, d) => max(m, d.total));
    final maximo = max(4, maior + 1).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Episódios por Dia — Últimos 7 Dias',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 4),
          if (total == 0)
            _buildEmpty(
              icon: Icons.insights_outlined,
              title: 'Nenhum episódio nos últimos 7 dias',
              hint: 'Os episódios aparecem aqui quando o painel detectar sinais de atenção ou de possível crise.',
            )
          else
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                margin: const EdgeInsets.only(top: 8),
                primaryXAxis: const CategoryAxis(
                  majorGridLines: MajorGridLines(width: 0),
                  labelStyle: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                  axisLine: AxisLine(width: 0),
                  majorTickLines: MajorTickLines(size: 0),
                ),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: maximo,
                  interval: maximo > 8 ? 2 : 1,
                  labelStyle: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                  majorGridLines: const MajorGridLines(
                    width: 1,
                    color: Color(0xFFEEEEEE),
                    dashArray: [4, 4],
                  ),
                  axisLine: const AxisLine(width: 0),
                  majorTickLines: const MajorTickLines(size: 0),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  format: 'point.x  •  point.y episódio(s)',
                  color: const Color(0xFF222222),
                  textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                series: [
                  ColumnSeries<DiaResumo, String>(
                    dataSource: dias,
                    xValueMapper: (d, _) => d.rotulo,
                    yValueMapper: (d, _) => d.total,
                    pointColorMapper: (d, _) => _corDoDia(d),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    width: 0.55,
                    animationDuration: 1200,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: false,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendItem(_corAlto, 'Possível crise'),
              const SizedBox(width: 16),
              _legendItem(_corModerado, 'Atenção'),
              const SizedBox(width: 16),
              _legendItem(_corCalmo, 'Calmo'),
            ],
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Cor = nível mais alto do dia',
              style: TextStyle(fontSize: 10, color: Color(0xFFAAAAAA)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
        ),
      ],
    );
  }
}
