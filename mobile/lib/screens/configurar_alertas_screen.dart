import 'package:flutter/material.dart';

import '../services/configuracao_de_alertas.dart';
import '../theme/app_theme.dart';
import '../widgets/cabecalho.dart';
import '../widgets/secao.dart';

/// "Configurar alertas": passos numerados para os alertas chegarem com o app
/// fechado (docs/app.md, "Configuracao na primeira abertura"). Cada botao
/// abre a janela certa do sistema; ao voltar para o app, a tela confere de
/// novo e marca o passo com ✓. "Comecar" fica destacado quando tudo esta ✓;
/// "Continuar sem isso" entra assim mesmo (com um aviso).
///
/// [aoConcluir]: na primeira abertura, troca para o Inicio. Sem ele (aberta
/// pelos Ajustes ou pelo aviso do Inicio), volta para a tela anterior.
class ConfigurarAlertasScreen extends StatefulWidget {
  const ConfigurarAlertasScreen({super.key, this.aoConcluir});

  final VoidCallback? aoConcluir;

  @override
  State<ConfigurarAlertasScreen> createState() => _ConfigurarAlertasScreenState();
}

class _ConfigurarAlertasScreenState extends State<ConfigurarAlertasScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ConfiguracaoScope.read(context)?.atualizar();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou das janelas do sistema: confere de novo (onResume)
    if (state == AppLifecycleState.resumed) ConfiguracaoScope.read(context)?.atualizar();
  }

  void _sair() {
    final concluir = widget.aoConcluir;
    if (concluir != null) {
      concluir();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _comecar(ConfiguracaoDeAlertas c) async {
    await c.comecar();
    if (mounted) _sair();
  }

  Future<void> _continuarSemIsso(ConfiguracaoDeAlertas c) async {
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continuar sem configurar?'),
        content: const Text(
          'Sem esses passos, os alertas só chegam com o app aberto. '
          'Você pode terminar depois em Ajustes → Configurar alertas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar mesmo assim')),
        ],
      ),
    );
    if (continuar != true || !mounted) return;
    await c.continuarSemIsso();
    if (mounted) _sair();
  }

  @override
  Widget build(BuildContext context) {
    final c = ConfiguracaoScope.maybeOf(context);
    if (c == null) return const SizedBox.shrink();
    var numero = 0;
    final pronto = c.tudoConcedido;
    return EstruturaTela(
      children: [
        const TituloTela(
          'Configurar alertas',
          apoio: 'Para o Puzzle Band avisar você mesmo com o app fechado, faça estes passos. '
              'Cada botão abre a janela certa do celular.',
        ),
        const SizedBox(height: Espaco.xl),
        _Passo(
          numero: ++numero,
          titulo: 'Permitir notificações',
          texto: 'Sem isso, o celular não mostra os alertas de atenção e de possível crise.',
          feito: c.notificacoesPermitidas,
          botao: 'Permitir notificações',
          aoTocar: c.pedirNotificacoes,
        ),
        const SizedBox(height: Espaco.m),
        _Passo(
          numero: ++numero,
          titulo: 'Rodar sem restrição de bateria',
          texto: 'O Android pode fechar o app para economizar bateria. Na janela que abrir, toque em “Permitir”.',
          feito: c.semRestricaoDeBateria,
          botao: 'Liberar a bateria',
          aoTocar: c.pedirSemRestricaoDeBateria,
        ),
        if (c.ehSamsung) ...[
          const SizedBox(height: Espaco.m),
          _Passo(
            numero: ++numero,
            titulo: 'Tirar dos “Apps em suspensão” (Samsung)',
            texto: 'Abra Configurações → Bateria → Limites de uso em segundo plano e retire o Puzzle Band de '
                '“Apps em suspensão”. Depois, volte aqui e toque em “Já fiz”.',
            feito: c.samsungConfirmado,
            botao: 'Abrir os ajustes do app',
            aoTocar: c.abrirDetalhesDoApp,
            confirmar: c.confirmarSamsung,
          ),
        ],
        const SizedBox(height: Espaco.m),
        _Passo(
          numero: ++numero,
          opcional: true,
          titulo: 'Receber alertas mesmo no Não perturbe',
          texto: 'Um alerta de crise pode chegar à noite ou numa reunião, com o “Não perturbe” ligado. '
              'Na tela que abrir, ative o Puzzle Band para os alertas tocarem mesmo assim.'
              '${c.ehSamsung ? ' Nos celulares Samsung, também dá para pôr o app nas exceções: '
                  'Configurações → Notificações → Não perturbe → Apps.' : ''}',
          aviso: 'No modo silencioso ou vibrar, o alerta aparece mas não toca. '
              'Deixe o volume de notificações ligado enquanto a criança estiver com a pulseira.',
          feito: c.naoPerturbeLiberado,
          botao: 'Abrir o “Não perturbe”',
          aoTocar: c.pedirNaoPerturbe,
        ),
        const SizedBox(height: Espaco.xl),
        FilledButton(
          onPressed: pronto ? () => _comecar(c) : null,
          child: const Text('Começar'),
        ),
        if (!pronto)
          Padding(
            padding: const EdgeInsets.only(top: Espaco.s),
            child: Text(
              'O botão “Começar” fica disponível quando todos os passos estiverem feitos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: CoresApp.of(context).tintaSuave),
            ),
          ),
        const SizedBox(height: Espaco.s),
        Center(
          child: TextButton(
            onPressed: () => _continuarSemIsso(c),
            child: const Text('Continuar sem isso'),
          ),
        ),
      ],
    );
  }
}

/// Um passo: numero (ou ✓ verde quando concedido), titulo, explicacao e o
/// botao que abre a janela do sistema. `confirmar`: passo que o app nao
/// consegue verificar (o tutor toca em "Ja fiz").
class _Passo extends StatelessWidget {
  const _Passo({
    required this.numero,
    required this.titulo,
    required this.texto,
    required this.feito,
    required this.botao,
    required this.aoTocar,
    this.confirmar,
    this.opcional = false,
    this.aviso,
  });

  final int numero;
  final String titulo;
  final String texto;
  final bool feito;
  final String botao;
  final Future<void> Function() aoTocar;
  final Future<void> Function()? confirmar;

  /// Nao conta para o "Comecar".
  final bool opcional;

  /// Destaque abaixo da explicacao (icone de informacao).
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final estilo = Theme.of(context).textTheme;
    final verde = cores.calmo;
    return Semantics(
      container: true,
      label: 'Passo $numero${opcional ? ' (opcional)' : ''}: $titulo. ${feito ? 'Feito.' : 'Pendente.'}',
      child: Secao(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: feito ? verde.fundo : cores.primariaSuave,
                ),
                child: feito
                    ? Icon(Icons.check_rounded, color: verde.texto, size: 22)
                    : Text('$numero', style: estilo.titleMedium!.copyWith(color: cores.sobrePrimariaSuave)),
              ),
            ),
            const SizedBox(width: Espaco.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (opcional)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Espaco.xs),
                      child: Text('OPCIONAL', style: estilo.labelSmall!.copyWith(color: cores.tintaSuave, letterSpacing: 1)),
                    ),
                  Text(titulo, style: estilo.titleMedium),
                  const SizedBox(height: Espaco.xs),
                  Text(texto, style: estilo.bodyMedium!.copyWith(color: cores.tintaSuave)),
                  if (aviso != null) ...[
                    const SizedBox(height: Espaco.s),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.volume_up_outlined, size: 20, color: cores.tinta),
                        ),
                        const SizedBox(width: Espaco.s),
                        Expanded(child: Text(aviso!, style: estilo.bodyMedium)),
                      ],
                    ),
                  ],
                  const SizedBox(height: Espaco.m),
                  if (feito)
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: verde.texto, size: 20),
                        const SizedBox(width: Espaco.xs),
                        Text('Feito', style: estilo.labelLarge!.copyWith(color: verde.texto)),
                      ],
                    )
                  else
                    Wrap(
                      spacing: Espaco.s,
                      runSpacing: Espaco.s,
                      children: [
                        OutlinedButton(onPressed: aoTocar, child: Text(botao)),
                        if (confirmar != null) TextButton(onPressed: confirmar, child: const Text('Já fiz')),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primeira abertura (e depois de perder uma permissao): mostra "Configurar
/// alertas" antes do Inicio. A decisao e tomada uma vez, quando a
/// configuracao termina de carregar. Sem ConfiguracaoScope, so o Inicio.
class PortaoDosAlertas extends StatefulWidget {
  const PortaoDosAlertas({super.key, required this.child});

  final Widget child;

  @override
  State<PortaoDosAlertas> createState() => _PortaoDosAlertasState();
}

class _PortaoDosAlertasState extends State<PortaoDosAlertas> {
  bool? _mostrarConfiguracao;

  @override
  Widget build(BuildContext context) {
    final c = ConfiguracaoScope.maybeOf(context);
    if (c == null) return widget.child;
    if (_mostrarConfiguracao == null) {
      if (!c.carregado) return const Scaffold(body: SizedBox.shrink());
      _mostrarConfiguracao = c.precisaConfigurar;
    }
    if (_mostrarConfiguracao!) {
      return ConfigurarAlertasScreen(aoConcluir: () => setState(() => _mostrarConfiguracao = false));
    }
    return widget.child;
  }
}

/// Aviso fixo no Inicio enquanto os alertas com o app fechado nao estao
/// funcionando (o tutor pulou, ou algo se perdeu).
class AvisoMonitoramento extends StatelessWidget {
  const AvisoMonitoramento({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ConfiguracaoScope.maybeOf(context);
    if (c == null || !c.mostrarAvisoNoInicio) return const SizedBox.shrink();
    final cores = CoresApp.of(context);
    final estilo = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaco.m),
      child: Material(
        color: cores.superficieAlta,
        borderRadius: BorderRadius.circular(Raio.secao),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Espaco.l, Espaco.s, Espaco.s, Espaco.s),
          child: Row(
            children: [
              Icon(Icons.notifications_off_outlined, color: cores.tinta),
              const SizedBox(width: Espaco.m),
              Expanded(child: Text('Alertas com o app fechado desativados', style: estilo.bodyMedium)),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ConfigurarAlertasScreen()),
                ),
                child: const Text('Corrigir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
