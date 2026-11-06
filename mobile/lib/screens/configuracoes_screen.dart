import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cabecalho.dart';
import '../widgets/connection_bar.dart';
import '../widgets/secao.dart';

/// Ajustes: crianca monitorada, conexoes (com o erro, se houver), alertas
/// sonoros e "sobre".
class ConfiguracoesScreen extends StatelessWidget {
  const ConfiguracoesScreen({super.key});

  static const versao = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    return EstruturaTela(
      children: [
        const TituloTela('Ajustes'),
        const SizedBox(height: Espaco.xl),
        _Grupo(
          titulo: 'Criança monitorada',
          itens: [
            ListTile(
              leading: const Icon(Icons.child_care_rounded),
              title: Text('Identificação: ${service.config.childId}'),
              subtitle: const Text('Definida no env.json (CHILD_ID). Precisa ser a mesma do painel.'),
            ),
          ],
        ),
        const SizedBox(height: Espaco.l),
        _Grupo(titulo: 'Conexões', itens: _conexoes(context, service)),
        const SizedBox(height: Espaco.l),
        _Grupo(
          titulo: 'Alertas',
          itens: [
            SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('Alertas sonoros'),
              subtitle: const Text('Desligado: a notificação de atenção ou possível crise aparece sem som e sem vibração.'),
              value: service.alertasSonoros,
              onChanged: (v) => service.definirAlertasSonoros(v),
            ),
          ],
        ),
        const SizedBox(height: Espaco.l),
        _Grupo(
          titulo: 'Sobre',
          itens: [
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('Puzzle Band $versao'),
              subtitle: Text(
                'Demonstração (TCC). Indicação de apoio ao cuidador, sem valor diagnóstico. '
                'Sem login real: qualquer usuário entra.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Licenças de software'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(context: context, applicationName: 'Puzzle Band', applicationVersion: versao),
            ),
          ],
        ),
        const SizedBox(height: Espaco.xl),
        OutlinedButton.icon(
          onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sair'),
        ),
      ],
    );
  }

  List<Widget> _conexoes(BuildContext context, MqttService service) {
    final cores = CoresApp.of(context);
    final broker = ConexaoInfo.broker(service.brokerStatus);
    final pulseira = ConexaoInfo.pulseira(service.pulseira);
    final painel = ConexaoInfo.painel(service.estadoAoVivo);
    final erro = service.ultimoErro;
    final host = service.config.host.isEmpty ? 'Servidor não configurado' : service.config.host;

    Widget linha(String titulo, ConexaoInfo info, String explicacao) => Semantics(
          container: true,
          label: '$titulo: ${info.rotulo}. $explicacao',
          excludeSemantics: true,
          child: ListTile(
            leading: Icon(info.icone, color: info.cor(cores)),
            title: Text('$titulo: ${info.rotulo}'),
            subtitle: Text(explicacao),
          ),
        );

    return [
      linha('Servidor', broker, erro ?? '$host, porta ${service.config.port} (MQTT com TLS).'),
      linha('Pulseira', pulseira, switch (service.pulseira) {
        Presenca.online => 'A pulseira está enviando os sinais.',
        Presenca.offline => 'A pulseira avisou que desligou ou perdeu a conexão.',
        Presenca.desconhecido => 'Ainda sem notícia da pulseira. Com o simulador manual, isso é normal.',
      }),
      linha('Painel (site)', painel, 'O modelo roda no site: ele precisa estar aberto.'),
    ];
  }
}

/// Grupo de itens com titulo, numa superficie, separados por divisorias.
class _Grupo extends StatelessWidget {
  const _Grupo({required this.titulo, required this.itens});

  final String titulo;
  final List<Widget> itens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Espaco.xs, bottom: Espaco.s),
          child: TituloSecao(titulo),
        ),
        Secao(
          padding: const EdgeInsets.symmetric(vertical: Espaco.xs),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (var i = 0; i < itens.length; i++) ...[
                  if (i > 0) const Divider(indent: 56, endIndent: Espaco.l),
                  itens[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
