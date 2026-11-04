import 'package:flutter/material.dart';

import '../services/mqtt_service.dart';

/// Situacao de uma conexao (broker, pulseira, painel/site): texto + icone + cor.
class ConexaoInfo {
  const ConexaoInfo(this.rotulo, this.icone, this.cor);

  final String rotulo;
  final IconData icone;
  final Color cor;

  static const _verde = Color(0xFF2E7D32);
  static const _amarelo = Color(0xFFB26A00);
  static const _vermelho = Color(0xFFC62828);
  static const _cinza = Color(0xFF757575);

  static ConexaoInfo broker(BrokerStatus s) => switch (s) {
        BrokerStatus.conectado => const ConexaoInfo('conectado', Icons.cloud_done, _verde),
        BrokerStatus.conectando => const ConexaoInfo('conectando…', Icons.cloud_sync, _amarelo),
        BrokerStatus.desconectado => const ConexaoInfo('desconectado', Icons.cloud_off, _vermelho),
        BrokerStatus.erro => const ConexaoInfo('erro', Icons.cloud_off, _vermelho),
        BrokerStatus.naoConfigurado => const ConexaoInfo('não configurado', Icons.cloud_off, _vermelho),
      };

  static ConexaoInfo pulseira(Presenca p) => switch (p) {
        Presenca.online => const ConexaoInfo('online', Icons.watch, _verde),
        Presenca.offline => const ConexaoInfo('offline', Icons.watch_off, _vermelho),
        Presenca.desconhecido => const ConexaoInfo('sem status', Icons.watch_off, _cinza),
      };

  static ConexaoInfo painel(bool aoVivo) => aoVivo
      ? const ConexaoInfo('ao vivo', Icons.monitor, _verde)
      : const ConexaoInfo('sem dados', Icons.desktop_access_disabled, _cinza);
}

/// Linha de "chips" de conexao usada na Home.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key, required this.service});

  final MqttService service;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('Broker', ConexaoInfo.broker(service.brokerStatus)),
        _chip('Pulseira', ConexaoInfo.pulseira(service.pulseira)),
        _chip('Painel', ConexaoInfo.painel(service.estadoAoVivo)),
      ],
    );
  }

  Widget _chip(String titulo, ConexaoInfo info) {
    return Semantics(
      label: '$titulo: ${info.rotulo}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: info.cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: info.cor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icone, size: 14, color: info.cor),
            const SizedBox(width: 6),
            Text(
              '$titulo: ${info.rotulo}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF444444)),
            ),
          ],
        ),
      ),
    );
  }
}
