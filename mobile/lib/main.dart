import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/graficos_screen.dart';
import 'screens/historico_screen.dart';
import 'screens/configuracoes_screen.dart';
import 'services/app_scope.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final notificacoes = NotificationService();
  await notificacoes.init();

  // Servico MQTT unico, vivo enquanto o processo do app estiver vivo
  final service = MqttService(
    config: AppConfig.fromEnvironment(),
    prefs: prefs,
    notificacoes: notificacoes,
  );

  runApp(AppScope(service: service, child: const PuzzleBandApp()));

  unawaited(service.iniciar());
  // Android 13+: permissao de notificacao na primeira abertura
  WidgetsBinding.instance.addPostFrameCallback((_) {
    notificacoes.pedirPermissaoNaPrimeiraAbertura(prefs);
  });
}

class PuzzleBandApp extends StatefulWidget {
  const PuzzleBandApp({super.key});

  @override
  State<PuzzleBandApp> createState() => _PuzzleBandAppState();
}

class _PuzzleBandAppState extends State<PuzzleBandApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = AppScope.read(context);
    if (state == AppLifecycleState.resumed) {
      service.retomar(); // voltou do segundo plano: reconecta se caiu
    } else if (state == AppLifecycleState.detached) {
      service.parar(); // saida normal: publica "offline" (senao vale o Last Will)
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puzzle Band',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/home': (context) => const MainNavigation(initialIndex: 0),
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

  // A tela de GPS (vazia) saiu da navegacao: "em breve" (screens/gps_screen.dart)
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFE91E63),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Gráficos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'Histórico',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.manage_accounts_outlined),
            activeIcon: Icon(Icons.manage_accounts),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
