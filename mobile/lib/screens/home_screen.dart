import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../utils/formatters.dart';
import '../widgets/connection_bar.dart';
import '../widgets/nivel_visual.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

// Define animação
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final ativo = service.episodioAtivo;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TELA INICIAL',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Color(0xFF222222),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConnectionBar(service: service),
                    const SizedBox(height: 20),
                    if (ativo != null) ...[
                      _buildAlertCard(service, ativo),
                      const SizedBox(height: 16),
                    ],
                    _buildStatusCard(service),
                    const SizedBox(height: 16),
                    _buildHeartRateCard(service),
                    const SizedBox(height: 16),
                    _buildQuickStatsCard(service),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

//  Header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              color: const Color(0xFFFFF2D0),
              border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
            ),
            child: const Icon(Icons.person, size: 20, color: Color(0xFF4CAF50)),
          ),
          const SizedBox(width: 12),
          const Text(
            'PUZZLE BAND',
            style: TextStyle(
              fontFamily: 'Inter',
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

//  Alerta (episódio em andamento)
  Widget _buildAlertCard(MqttService service, EpisodioAtivo ativo) {
    final nivelAtual = service.estado?.nivel;
    final visual = NivelVisual.de(nivelAtual != null && nivelAtual.isAlerta ? nivelAtual : ativo.nivelMaximo);
    final critico = identical(visual, NivelVisual.possivelCrise);
    final gatilho = service.estado?.gatilho?.texto ?? '';
    final ciente = service.cienteEm(ativo.id);
    final inicio = ativo.inicio;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: visual.fundo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: visual.cor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(visual.icone, color: visual.cor, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    critico ? 'Possível crise em andamento' : 'Atenção: episódio em andamento',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: visual.cor,
                    ),
                  ),
                ),
              ],
            ),
            if (inicio != null) ...[
              const SizedBox(height: 4),
              Text(
                'Desde ${horaMinuto(inicio)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              gatilho.isNotEmpty ? gatilho : 'Gatilho ainda não calculado.',
              style: const TextStyle(fontSize: 14, height: 1.35, color: Color(0xFF222222)),
            ),
            const SizedBox(height: 14),
            if (ciente != null)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Você avisou que está ciente às ${horaMinuto(ciente)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmarCiente(ativo.id),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text(
                    'Estou ciente',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: visual.cor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Indicação de apoio ao cuidador, sem valor diagnóstico.',
              style: TextStyle(fontSize: 11, color: Color(0xFF757575)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarCiente(String episodioId) {
    final enviado = AppScope.read(context).enviarCiente(episodioId);
    if (!enviado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem conexão com o broker. Tente de novo em instantes.')),
      );
    }
  }

//  Estado Atual
  Widget _buildStatusCard(MqttService service) {
    final estado = service.estado;
    final aoVivo = service.estadoAoVivo && estado != null;
    final visual = aoVivo ? NivelVisual.de(estado.nivel) : NivelVisual.semDados;
    final recebido = service.estadoRecebidoEm;
    final String detalhe;
    if (aoVivo) {
      final prob = estado.probabilidade;
      detalhe = [
        if (prob != null) 'Probabilidade estimada: ${(prob * 100).round()}%' else 'Analisando os primeiros 30 s',
        rotuloFonte(estado.fonte),
      ].join(' · ');
    } else if (recebido != null && recebido.year > 2000) {
      detalhe = 'Última atualização às ${horaMinutoSegundo(recebido)}. O painel (site) está aberto?';
    } else {
      detalhe = 'Aguardando o painel (site), que roda o modelo.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estado Atual',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        visual.rotulo,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: visual.cor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnim.value,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: visual.cor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detalhe,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: visual.fundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              visual.icone,
              size: 36,
              color: visual.cor,
              semanticLabel: visual.rotulo,
            ),
          ),
        ],
      ),
    );
  }

//  Frequência Cardíaca
  Widget _buildHeartRateCard(MqttService service) {
    final bpm = service.estadoAoVivo ? service.estado?.leituras?.bpm : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frequência Cardíaca',
            style: TextStyle(fontSize: 13, color: Color(0xFF9E9E9E)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnim.value,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.favorite,
                    color: Color(0xFFE53935),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                bpm != null ? bpm.round().toString() : '—',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF222222),
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'bpm',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          Text(
            bpm != null ? 'Batimentos por minuto (ao vivo)' : 'Batimentos por minuto · sem leitura ao vivo',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9E9E9E),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

//  Resumo do Dia
  Widget _buildQuickStatsCard(MqttService service) {
    final media = service.estadoAoVivo ? service.estado?.mediaBpm5min : null;
    final hoje = episodiosNoDia(service.historico, DateTime.now());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo do Dia',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildStatItem(
                icon: Icons.monitor_heart_outlined,
                color: const Color(0xFFE53935),
                label: 'Média BPM\n(últimos 5 min)',
                value: media != null ? media.round().toString() : '—',
              ),
              _buildDivider(),
              _buildStatItem(
                icon: Icons.warning_amber_outlined,
                color: const Color(0xFFFFB300),
                label: 'Episódios hoje',
                value: hoje.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

//  Resumo do Dia Itens
  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF222222),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF9E9E9E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 50,
      color: const Color(0xFFEEEEEE),
    );
  }
}
