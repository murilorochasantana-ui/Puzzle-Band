import 'package:flutter/widgets.dart';

import 'mqtt_service.dart';

/// Entrega o MqttService as telas, sem pacote de estado: quem chama
/// AppScope.of(context) e reconstruido a cada notifyListeners do servico.
class AppScope extends InheritedNotifier<MqttService> {
  const AppScope({super.key, required MqttService service, required super.child})
      : super(notifier: service);

  static MqttService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Sem se inscrever para reconstrucao (use em callbacks de botao).
  static MqttService read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
