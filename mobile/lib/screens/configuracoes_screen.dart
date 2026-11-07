import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../widgets/cabecalho.dart';
import '../widgets/connection_bar.dart';
import '../widgets/secao.dart';

/// Ajustes: crianca monitorada (nome mostrado no Inicio, so neste celular),
/// conexoes (com o erro, se houver), alertas sonoros, aparencia (tema),
/// "Apagar dados deste aparelho" e "sobre".
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
            // Recomeca (com o nome salvo) quando os dados sao apagados
            _CampoNome(key: ValueKey('nome-${PreferenciasScope.of(context).geracao}')),
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
        const _Grupo(titulo: 'Aparência', itens: [_EscolhaDeAparencia()]),
        const SizedBox(height: Espaco.l),
        const _Grupo(titulo: 'Dados deste aparelho', itens: [_ApagarDados()]),
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

/// "Nome da criança": aparece no cabecalho do Inicio. Salvo no
/// shared_preferences a cada mudanca; vazio, vale o CHILD_ID. Nao vai para
/// o MQTT.
class _CampoNome extends StatefulWidget {
  const _CampoNome({super.key});

  @override
  State<_CampoNome> createState() => _CampoNomeState();
}

class _CampoNomeState extends State<_CampoNome> {
  late final PreferenciasLocais _preferencias = PreferenciasScope.read(context);
  late final TextEditingController _nome = TextEditingController(text: _preferencias.nomeDigitado);

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.m, Espaco.l, Espaco.xs),
      child: TextField(
        controller: _nome,
        maxLength: PreferenciasLocais.maxNome,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: _preferencias.definirNomeCrianca,
        decoration: InputDecoration(
          labelText: 'Nome da criança',
          hintText: _preferencias.nomePadrao,
          prefixIcon: const Icon(Icons.badge_outlined),
          helperText: 'Aparece no Início. Fica só neste celular: não vai para o painel. '
              'Vazio, o app mostra ${_preferencias.nomePadrao}.',
          helperMaxLines: 3,
        ),
      ),
    );
  }
}

/// Aparencia: seguir o sistema (padrao), claro ou escuro. A escolha fica so
/// neste celular e vale na hora. Lista de radio (e nao botoes segmentados):
/// com a fonte ampliada, "Seguir o sistema" nao caberia num segmento. Cada
/// opcao ocupa a linha inteira (56 dp).
class _EscolhaDeAparencia extends StatelessWidget {
  const _EscolhaDeAparencia();

  static const _opcoes = [
    (Aparencia.sistema, Icons.brightness_auto_outlined, 'Seguir o sistema', 'Usa o tema escolhido no Android.'),
    (Aparencia.claro, Icons.light_mode_outlined, 'Claro', null),
    (Aparencia.escuro, Icons.dark_mode_outlined, 'Escuro', 'Menos brilho à noite, no quarto da criança.'),
  ];

  @override
  Widget build(BuildContext context) {
    final preferencias = PreferenciasScope.of(context);
    return RadioGroup<Aparencia>(
      groupValue: preferencias.aparencia,
      onChanged: (a) {
        if (a != null) preferencias.definirAparencia(a);
      },
      child: Column(
        children: [
          for (final (i, (aparencia, icone, titulo, apoio)) in _opcoes.indexed) ...[
            if (i > 0) const Divider(indent: 56, endIndent: Espaco.l),
            RadioListTile<Aparencia>(
              key: ValueKey('aparencia-${aparencia.codigo}'),
              value: aparencia,
              secondary: Icon(icone),
              title: Text(titulo),
              subtitle: apoio == null ? null : Text(apoio),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ],
        ],
      ),
    );
  }
}

/// "Apagar dados deste aparelho": a mesma limpeza local da ordem do terminal
/// (npm run resetar), util sem computador. Pede confirmacao num dialogo; as
/// preferencias (nome, aparencia, alertas sonoros) so saem se o cuidador
/// marcar. Nao publica nada: o historico da pulseira continua la.
class _ApagarDados extends StatelessWidget {
  const _ApagarDados();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('apagar-dados'),
      leading: const Icon(Icons.delete_sweep_outlined),
      title: const Text('Apagar dados deste aparelho'),
      subtitle: const Text('Histórico salvo, alertas, lembretes e gráficos deste celular. Útil antes de uma nova apresentação.'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _confirmar(context),
    );
  }

  static Future<void> _confirmar(BuildContext context) async {
    final mensageiro = ScaffoldMessenger.of(context);
    final service = AppScope.read(context);
    // null = cancelou; true/false = tambem apagar as preferencias
    final apagarPreferencias = await showDialog<bool>(
      context: context,
      builder: (_) => const _DialogoApagarDados(),
    );
    if (apagarPreferencias == null) return;
    await service.apagarDadosLocais(manterPreferencias: !apagarPreferencias);
    mensageiro
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Dados deste aparelho apagados.')));
  }
}

class _DialogoApagarDados extends StatefulWidget {
  const _DialogoApagarDados();

  @override
  State<_DialogoApagarDados> createState() => _DialogoApagarDadosState();
}

class _DialogoApagarDadosState extends State<_DialogoApagarDados> {
  bool _preferencias = false;

  @override
  Widget build(BuildContext context) {
    final vermelho = CoresDados.of(context).descartado;
    return AlertDialog(
      title: const Text('Apagar dados deste aparelho?'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apaga deste celular a cópia do histórico, os alertas já recebidos, os lembretes '
            '(e os avisos agendados deles) e os gráficos. Não dá para desfazer.',
          ),
          const SizedBox(height: Espaco.s),
          const Text(
            'Os episódios guardados na pulseira não mudam: voltam a aparecer quando ela publicar de novo. '
            'Para zerar tudo, use "npm run resetar" no computador.',
          ),
          const SizedBox(height: Espaco.s),
          CheckboxListTile(
            key: const ValueKey('apagar-preferencias'),
            value: _preferencias,
            onChanged: (v) => setState(() => _preferencias = v ?? false),
            title: const Text('Também voltar as preferências ao padrão'),
            subtitle: const Text('Nome da criança, aparência e alertas sonoros.'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const ValueKey('confirmar-apagar'),
          onPressed: () => Navigator.pop(context, _preferencias),
          style: FilledButton.styleFrom(backgroundColor: vermelho.fundo, foregroundColor: vermelho.texto),
          child: const Text('Apagar'),
        ),
      ],
    );
  }
}
