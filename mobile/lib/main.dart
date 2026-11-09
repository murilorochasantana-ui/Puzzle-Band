import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/graficos_screen.dart';
import 'screens/historico_screen.dart';
import 'screens/configuracoes_screen.dart';
import 'screens/configurar_alertas_screen.dart';
import 'services/app_scope.dart';
import 'services/aviso_de_lembrete.dart';
import 'services/configuracao_de_alertas.dart';
import 'services/monitor_segundo_plano.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'services/preferencias_locais.dart';
import 'services/sistema_android.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Licenca OFL da fonte empacotada (aparece em Ajustes > Licencas de software)
  LicenseRegistry.addLicense(() async* {
    final texto = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Atkinson Hyperlegible Next'], texto);
  });
  final prefs = await SharedPreferences.getInstance();
  final notificacoes = NotificationService();
  await notificacoes.init();
  // Servico em primeiro plano (alertas com o app fechado): opcoes e a porta
  // de comunicacao com a tarefa (monitor_segundo_plano.dart)
  MonitorSegundoPlano.configurar();

  // Nome da crianca e lembretes: so neste celular (nao vao para o MQTT)
  final config = AppConfig.fromEnvironment();
  final preferencias = PreferenciasLocais(
    prefs: prefs,
    nomePadrao: config.childId,
    aviso: AvisoDeLembreteLocal(),
  );

  // Conexao MQTT das telas, viva enquanto o processo do app estiver vivo. A
  // ordem de reset (npm run resetar) tambem apaga os lembretes e, com
  // --tudo, o nome e a aparencia (preferencias.apagarDados). Com o servico
  // em primeiro plano rodando, quem notifica e ele (definirServicoRodando).
  final service = MqttService(
    config: config,
    prefs: prefs,
    notificacoes: notificacoes,
    aoApagarDados: preferencias.apagarDados,
  );

  // Configuracao dos alertas com o app fechado (tela "Configurar alertas"):
  // a permissao de notificacao e pedida la, num passo explicado
  final configuracao = ConfiguracaoDeAlertas(
    prefs: prefs,
    sistema: SistemaAndroidReal(notificacoes: notificacoes),
    nomeCrianca: () => preferencias.nomeCrianca,
    mqtt: service,
  );

  runApp(AppScope(
    service: service,
    child: PreferenciasScope(
      preferencias: preferencias,
      child: ConfiguracaoScope(configuracao: configuracao, child: const PuzzleBandApp()),
    ),
  ));

  // Primeiro descobre se o servico ja roda (aberto depois de fechado, ou
  // religado no boot): so entao conecta, ja sabendo quem notifica
  await configuracao.atualizar();
  configuracao.retomar();
  unawaited(service.iniciar());
}

class PuzzleBandApp extends StatefulWidget {
  const PuzzleBandApp({super.key, this.rotaInicial = '/'});

  /// Tela de abertura ('/' = Inicio, passando antes por "Configurar alertas"
  /// na primeira abertura; o app nao tem login). Os testes abrem direto em
  /// outra aba.
  final String rotaInicial;

  @override
  State<PuzzleBandApp> createState() => _PuzzleBandAppState();
}

class _PuzzleBandAppState extends State<PuzzleBandApp> with WidgetsBindingObserver {
  // SnackBar de qualquer tela (o aviso do reset chega pelo servico, nao por
  // um toque do cuidador)
  final _mensageiro = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _avisos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _avisos ??= AppScope.read(context).avisos.listen(_mostrarAviso);
  }

  /// Discreto: some sozinho, sem acao.
  void _mostrarAviso(String texto) {
    _mensageiro.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 6)));
  }

  @override
  void dispose() {
    _avisos?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = AppScope.read(context);
    final configuracao = ConfiguracaoScope.read(context);
    if (state == AppLifecycleState.resumed) {
      service.retomar(); // voltou do segundo plano: reconecta se caiu
      configuracao?.retomar(); // confere o servico e as permissoes
    } else if (state == AppLifecycleState.paused) {
      configuracao?.pausar();
    } else if (state == AppLifecycleState.detached) {
      configuracao?.pausar();
      service.parar(); // saida normal: "offline" so se as telas forem as donas da presenca
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ajustes > Aparencia: seguir o sistema (padrao), claro ou escuro. Trocar
    // reconstroi daqui (PreferenciasScope) e o tema muda na hora.
    final aparencia = PreferenciasScope.of(context).aparencia;
    return MaterialApp(
      title: 'Puzzle Band',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _mensageiro,
      // Tema unico (lib/theme/): claro e escuro
      theme: AppTheme.claro(),
      darkTheme: AppTheme.escuro(),
      themeMode: aparencia.themeMode,
      // Barra de status e de navegacao do Android acompanham o tema que esta
      // valendo (o escolhido ou o do sistema)
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.barrasDoSistema(Theme.of(context).brightness),
        child: child!,
      ),
      initialRoute: widget.rotaInicial,
      routes: {
        // Abre direto (sem login): na primeira abertura, "Configurar alertas"
        // antes do Inicio. Tocar numa notificacao tambem abre aqui.
        '/': (context) => const PortaoDosAlertas(child: MainNavigation(initialIndex: 0)),
        '/graficos': (context) => const MainNavigation(initialIndex: 1),
        '/historico': (context) => const MainNavigation(initialIndex: 2),
        '/configuracoes': (context) => const MainNavigation(initialIndex: 3),
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({super.key, this.initialIndex = 0});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    GraficosScreen(),
    HistoricoScreen(),
    ConfiguracoesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      // Rotulos sempre visiveis; o nome da aba e o titulo da tela
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: CoresApp.of(context).divisoria)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          animationDuration: Movimento.de(context, Movimento.medio),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Início',
            ),
            NavigationDestination(
              icon: Icon(Icons.insert_chart_outlined_rounded),
              selectedIcon: Icon(Icons.insert_chart_rounded),
              label: 'Gráficos',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'Histórico',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}
