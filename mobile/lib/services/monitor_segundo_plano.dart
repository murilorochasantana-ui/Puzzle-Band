// Monitoramento com o app fechado: um servico em primeiro plano do Android
// (pacote flutter_foreground_task) com uma notificacao fixa e discreta
// ("Puzzle Band: monitorando <nome>"). Ele roda a tarefa abaixo num motor
// Dart proprio, que continua vivo quando o app e tirado dos recentes, e
// mantem a SUA conexao MQTT (MqttService no papel servico: mesmas
// credenciais do env.json via --dart-define, mesma reconexao). Ver
// docs/app.md, "Notificacoes" e "Limitacoes".
//
//   - tipo specialUse (AndroidManifest.xml): o dataSync tem limite de 6 h a
//     cada 24 h no Android 15 e nao pode ser iniciado no BOOT_COMPLETED;
//   - wake lock parcial (allowWakeLock): sem ele, com a tela desligada, a CPU
//     dorme, o ping do MQTT (keepalive de 60 s) atrasa e o broker derruba a
//     conexao; o radio de rede continua liberado pela isencao de bateria;
//   - a cada 5 min a tarefa rearma o vigia ("Monitoramento pausado" agendado
//     para daqui a 15 min): se o servico morrer, o aviso dispara sozinho;
//   - volta sozinho depois de reiniciar o celular (autoRunOnBoot), so se
//     estava ligado (o pacote nao religa um servico parado pelo app).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'mqtt_service.dart';
import 'notification_service.dart';

/// Comando das telas para a tarefa: o tutor desligou a opcao (as telas
/// assumem a presenca; a tarefa sai sem publicar "offline").
const comandoParadoPeloTutor = 'parado_pelo_tutor';

/// Comando das telas para a tarefa: o nome da crianca mudou.
const comandoAtualizarNome = 'atualizar_nome';

const _chaveNome = 'nome_crianca'; // o mesmo de PreferenciasLocais
const _intervaloDaTarefa = Duration(minutes: 5);

/// O vigia dispara se a tarefa nao o rearmar por este tempo.
const atrasoDoVigia = Duration(minutes: 15);

String tituloDoMonitoramento(String nome) => 'Puzzle Band: monitorando $nome';
const textoDoMonitoramento = 'Os alertas chegam mesmo com o app fechado.';

/// Controle do servico pelas telas.
class MonitorSegundoPlano {
  static const _idDoServico = 4242;

  /// Uma vez, no main(): porta de comunicacao e opcoes do servico.
  static void configurar() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'puzzleband_monitoramento',
        channelName: 'Monitoramento com o app fechado',
        channelDescription: 'Notificação fixa enquanto o app recebe os alertas com ele fechado. Sem som.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(_intervaloDaTarefa.inMilliseconds),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<bool> rodando() => FlutterForegroundTask.isRunningService;

  Future<bool> iniciar(String nome) async {
    if (await rodando()) return true;
    final r = await FlutterForegroundTask.startService(
      serviceId: _idDoServico,
      serviceTypes: const [ForegroundServiceTypes.specialUse],
      notificationTitle: tituloDoMonitoramento(nome),
      notificationText: textoDoMonitoramento,
      callback: iniciarTarefaDoMonitor,
    );
    if (r is ServiceRequestFailure) debugPrint('Servico nao iniciou: ${r.error}');
    return r is ServiceRequestSuccess;
  }

  Future<void> parar() async {
    if (!await rodando()) return;
    FlutterForegroundTask.sendDataToTask(comandoParadoPeloTutor);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final r = await FlutterForegroundTask.stopService();
    if (r is ServiceRequestFailure) debugPrint('Servico nao parou: ${r.error}');
  }

  Future<void> atualizarNome(String nome) async {
    if (!await rodando()) return;
    await FlutterForegroundTask.updateService(notificationTitle: tituloDoMonitoramento(nome));
  }
}

// ---------------------------------------------------------------------------
// A tarefa (motor Dart do servico)
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void iniciarTarefaDoMonitor() {
  FlutterForegroundTask.setTaskHandler(TarefaDoMonitor());
}

class TarefaDoMonitor extends TaskHandler {
  SharedPreferences? _prefs;
  NotificationService? _notificacoes;
  MqttService? _mqtt;
  bool _paradoPeloTutor = false;
  bool _avisouPausa = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    final notificacoes = _notificacoes = NotificationService();
    await notificacoes.init();
    final config = AppConfig.fromEnvironment();
    final mqtt = _mqtt = MqttService(
      config: config,
      prefs: prefs,
      notificacoes: notificacoes,
      papel: PapelDaConexao.servico,
    );
    unawaited(mqtt.iniciar());
    await _verificar();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_verificar());
  }

  /// Rearma o vigia, atualiza o nome na notificacao fixa e confere as
  /// permissoes: se a notificacao ou a isencao de bateria foram revogadas,
  /// avisa "Monitoramento pausado" (uma vez, ate voltar).
  Future<void> _verificar() async {
    final prefs = _prefs;
    final notificacoes = _notificacoes;
    if (prefs == null || notificacoes == null) return;
    await notificacoes.armarVigia(atrasoDoVigia);
    try {
      await prefs.reload();
      final nome = (prefs.getString(_chaveNome) ?? '').trim();
      await FlutterForegroundTask.updateService(
        notificationTitle: tituloDoMonitoramento(nome.isEmpty ? AppConfig.fromEnvironment().childId : nome),
      );
    } catch (e) {
      debugPrint('Falha ao atualizar a notificacao fixa: $e');
    }
    final bateria = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    final permitidas = await notificacoes.permitidas() ?? true;
    final perdeu = !bateria || !permitidas;
    if (perdeu && !_avisouPausa) {
      _avisouPausa = true;
      await notificacoes.mostrarMonitoramentoPausado();
    } else if (!perdeu) {
      _avisouPausa = false;
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data == comandoParadoPeloTutor) _paradoPeloTutor = true;
    if (data == comandoAtualizarNome) unawaited(_verificar());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Parado pelo tutor: as telas assumem a presenca, e o vigia e desarmado
    // por elas. Parado pelo sistema: o vigia continua armado.
    await _mqtt?.parar(semOffline: _paradoPeloTutor);
    _mqtt?.dispose();
  }
}
