// Aviso de lembrete: uma notificacao local agendada pelo proprio celular, no
// horario que o cuidador escolheu. Separado do servico dos alertas
// (notification_service.dart), que nao muda.
//
//   - canal proprio "Lembretes" (importancia normal: som, sem tela cheia);
//   - agendamento INEXATO (AndroidScheduleMode.inexactAllowWhileIdle): pode
//     atrasar alguns minutos, mas nao pede a permissao de "alarme exato";
//   - visibilidade "secreta": numa tela bloqueada com PIN, padrao ou
//     digital, o Android nao mostra nada do lembrete (o texto aparece depois
//     de desbloquear);
//   - o instante e agendado em UTC: um aviso unico (sem repeticao) nao
//     depende do fuso do celular, entao nao e preciso carregar a base de
//     fusos do pacote timezone.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

abstract class AvisoDeLembrete {
  /// Agenda (ou reagenda, mesmo id) o aviso. Devolve false se o aparelho nao
  /// conseguiu agendar.
  Future<bool> agendar({required int id, required DateTime quando, required String titulo, required String texto});

  Future<void> cancelar(int id);
}

class AvisoDeLembreteLocal implements AvisoDeLembrete {
  // O plugin e um objeto unico: ja foi inicializado pelo NotificationService.
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _canalCriado = false;

  static const _canal = AndroidNotificationChannel(
    'puzzleband_lembretes',
    'Lembretes',
    description: 'Lembretes que você deixou no app. Ficam só neste celular.',
    importance: Importance.defaultImportance,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> agendar({
    required int id,
    required DateTime quando,
    required String titulo,
    required String texto,
  }) async {
    final android = _android;
    if (android == null) return false; // so Android
    try {
      if (!_canalCriado) {
        await android.createNotificationChannel(_canal);
        _canalCriado = true;
      }
      await _plugin.cancel(id: id);
      await _plugin.zonedSchedule(
        id: id,
        title: titulo,
        body: texto,
        scheduledDate: tz.TZDateTime.from(quando, tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _canal.id,
            _canal.name,
            channelDescription: _canal.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            visibility: NotificationVisibility.secret,
            category: AndroidNotificationCategory.reminder,
            styleInformation: BigTextStyleInformation(texto),
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Falha ao agendar o lembrete: $e');
      return false;
    }
  }

  @override
  Future<void> cancelar(int id) async {
    if (_android == null) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('Falha ao cancelar o lembrete: $e');
    }
  }
}
