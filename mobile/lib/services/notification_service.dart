// Notificacoes locais dos alertas (atencao / possivel crise). So funcionam com
// o processo do app vivo (aberto ou em segundo plano recente): notificacao
// com o app fechado exigiria push (FCM) e um servidor sempre ligado - ver
// docs/app.md, "Limitacoes".

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _pronto = false;

  // No Android o som de um canal nao pode mudar depois de criado: por isso
  // ha dois canais, e a opcao "Alertas sonoros" escolhe qual usar.
  static const _canalSom = AndroidNotificationChannel(
    'puzzleband_alertas',
    'Alertas de crise',
    description: 'Atenção e possível crise, com som e vibração',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _canalSilencioso = AndroidNotificationChannel(
    'puzzleband_alertas_silenciosos',
    'Alertas sem som',
    description: 'Atenção e possível crise, sem som (opção "Alertas sonoros" desligada)',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );

  static const _chavePermissaoPedida = 'notificacao_permissao_pedida';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _android?.createNotificationChannel(_canalSom);
      await _android?.createNotificationChannel(_canalSilencioso);
      _pronto = true;
    } catch (e) {
      // Plataforma sem suporte (testes, desktop): o app segue sem notificacao
      debugPrint('Notificacoes indisponiveis: $e');
    }
  }

  /// Android 13+: pede POST_NOTIFICATIONS so na primeira abertura do app.
  Future<void> pedirPermissaoNaPrimeiraAbertura(SharedPreferences prefs) async {
    if (!_pronto || (prefs.getBool(_chavePermissaoPedida) ?? false)) return;
    await prefs.setBool(_chavePermissaoPedida, true);
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Falha ao pedir permissao de notificacao: $e');
    }
  }

  /// `atualizacao`: o episodio ja foi notificado e so subiu de nivel - a
  /// mesma notificacao (mesmo id) e atualizada, sem tocar de novo.
  Future<void> mostrarAlerta({
    required int id,
    required String titulo,
    required String texto,
    required bool comSom,
    required bool atualizacao,
    String? payload,
  }) async {
    if (!_pronto) return;
    final canal = comSom ? _canalSom : _canalSilencioso;
    final detalhes = AndroidNotificationDetails(
      canal.id,
      canal.name,
      channelDescription: canal.description,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(texto),
      ticker: titulo,
      silent: atualizacao,
      onlyAlertOnce: atualizacao,
    );
    try {
      await _plugin.show(
        id: id,
        title: titulo,
        body: texto,
        notificationDetails: NotificationDetails(android: detalhes),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Falha ao mostrar notificacao: $e');
    }
  }
}

/// Id estavel (31 bits) de notificacao a partir do id do episodio (FNV-1a).
int idDeNotificacao(String chave) {
  var hash = 0x811c9dc5;
  for (final unit in chave.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
