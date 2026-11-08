import 'package:flutter/material.dart';

import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';

/// Como uma conexao esta: ok (azul de acao), problema (texto forte) ou
/// neutra/sem informacao. Nao usa vermelho nem amarelo: essas cores ficam
/// reservadas para o nivel da crianca.
enum TomConexao { ok, problema, neutro }

/// Situacao de uma conexao (servidor, pulseira, painel/site): texto + icone.
class ConexaoInfo {
  const ConexaoInfo(this.rotulo, this.icone, this.tom);

  final String rotulo;
  final IconData icone;
  final TomConexao tom;

  bool get ok => tom == TomConexao.ok;

  static ConexaoInfo broker(BrokerStatus s) => switch (s) {
        BrokerStatus.conectado => const ConexaoInfo('conectado', Icons.cloud_done_outlined, TomConexao.ok),
        BrokerStatus.conectando => const ConexaoInfo('conectando…', Icons.cloud_sync_outlined, TomConexao.neutro),
        BrokerStatus.desconectado => const ConexaoInfo('sem conexão', Icons.cloud_off_outlined, TomConexao.problema),
        BrokerStatus.erro => const ConexaoInfo('falha ao conectar', Icons.cloud_off_outlined, TomConexao.problema),
        BrokerStatus.naoConfigurado =>
          const ConexaoInfo('não configurado', Icons.settings_outlined, TomConexao.problema),
      };

  static ConexaoInfo pulseira(Presenca p) => switch (p) {
        Presenca.online => const ConexaoInfo('conectada', Icons.watch_outlined, TomConexao.ok),
        Presenca.offline => const ConexaoInfo('desconectada', Icons.watch_off_outlined, TomConexao.problema),
        Presenca.desconhecido => const ConexaoInfo('sem status', Icons.watch_outlined, TomConexao.neutro),
      };

  static ConexaoInfo painel(bool aoVivo) => aoVivo
      ? const ConexaoInfo('ao vivo', Icons.monitor_outlined, TomConexao.ok)
      : const ConexaoInfo('sem dados', Icons.desktop_access_disabled_outlined, TomConexao.problema);

  Color cor(CoresApp cores) => switch (tom) {
        TomConexao.ok => cores.primaria,
        TomConexao.problema => cores.tinta,
        TomConexao.neutro => cores.tintaSuave,
      };
}

/// Linha de conexao da Home: fica quieta ("Tudo conectado") e so fala quando
/// algo cai. Servidor e painel fora do ar ja sao explicados pela faixa de
/// estado (com o que fazer); aqui fica so o que a faixa nao diz: a pulseira.
/// A situacao completa das tres conexoes esta em Ajustes.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key, required this.service});

  final MqttService service;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    if (service.brokerStatus != BrokerStatus.conectado) return const SizedBox.shrink();
    final itens = <(String, ConexaoInfo)>[
      if (service.pulseira != Presenca.online) ('Pulseira', ConexaoInfo.pulseira(service.pulseira)),
    ];

    if (itens.isEmpty && service.estadoAoVivo) {
      return Semantics(
        label: 'Conexões: tudo conectado. Servidor e pulseira funcionando, com os dados ao vivo.',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(Icons.cloud_done_outlined, size: 20, color: cores.primaria),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text('Tudo conectado', style: texto.bodySmall)),
          ],
        ),
      );
    }
    if (itens.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Espaco.m, vertical: Espaco.s),
      decoration: BoxDecoration(
        color: cores.superficieAlta,
        borderRadius: BorderRadius.circular(Raio.controle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (titulo, info) in itens)
            Semantics(
              label: '$titulo: ${info.rotulo}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Espaco.xs),
                child: Row(
                  children: [
                    Icon(info.icone, size: 20, color: info.cor(cores)),
                    const SizedBox(width: Espaco.s),
                    Expanded(
                      child: Text(
                        '$titulo: ${info.rotulo}',
                        style: texto.bodyMedium!.copyWith(
                          color: info.cor(cores),
                          fontWeight: info.tom == TomConexao.problema ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
