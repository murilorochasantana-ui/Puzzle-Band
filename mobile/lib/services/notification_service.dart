// Notificacoes locais dos alertas (atencao / possivel crise) e o aviso
// "Monitoramento pausado". Com o app fechado, quem as mostra e o servico em
// primeiro plano (monitor_segundo_plano.dart), com este mesmo codigo; ver
// docs/app.md, "Notificacoes".

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _pronto = false;

  // No Android a configuracao de um canal (som, "ignorar Nao perturbe") nao
  // muda depois de criado: por isso ha dois PARES de canais de alerta - o
  // normal e o que ignora o "Nao perturbe" - e, em cada par, um com som e um
  // sem som ("Alertas sonoros" escolhe). O par que ignora o "Nao perturbe"
  // so e criado com o acesso concedido (antes disso, o Android criaria o
  // canal sem essa opcao) e depois fica. NENHUM canal de alerta e apagado:
  // apagar um canal tira da tela as notificacoes dele (um "Possivel crise"
  // ativo sumiria). Qual par usar e decidido por episodio
  // (regra_de_notificacao.dart): a subida repete o par da notificacao
  // original, para continuar sendo a mesma notificacao.
  static const canalSom = AndroidNotificationChannel(
    'puzzleband_alertas',
    'Alertas de crise',
    description: 'Atenção e possível crise, com som e vibração',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const canalSilencioso = AndroidNotificationChannel(
    'puzzleband_alertas_silenciosos',
    'Alertas de crise (sem som)',
    description: 'Atenção e possível crise, sem som (opção "Alertas sonoros" desligada)',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );

  static const canalSomNaoPerturbe = AndroidNotificationChannel(
    'puzzleband_alertas_dnd',
    'Alertas de crise (ignora Não perturbe)',
    description: 'Atenção e possível crise, com som e vibração, mesmo com o "Não perturbe" ligado',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    bypassDnd: true,
  );

  static const canalSilenciosoNaoPerturbe = AndroidNotificationChannel(
    'puzzleband_alertas_silenciosos_dnd',
    'Alertas de crise sem som (ignora Não perturbe)',
    description: 'Atenção e possível crise, sem som, aparecendo mesmo com o "Não perturbe" ligado',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
    bypassDnd: true,
  );

  /// O canal de um alerta.
  static AndroidNotificationChannel canalDoAlerta({required bool comSom, required bool ignoraNaoPerturbe}) =>
      ignoraNaoPerturbe
          ? (comSom ? canalSomNaoPerturbe : canalSilenciosoNaoPerturbe)
          : (comSom ? canalSom : canalSilencioso);

  /// Canais de alerta a criar: o par normal sempre (criar de novo um canal
  /// que ja existe so atualiza o nome); o que ignora o "Nao perturbe", so com
  /// o acesso concedido e se ainda nao existe. Nunca apaga canal nenhum.
  static List<AndroidNotificationChannel> canaisDeAlertaACriar({
    required bool naoPerturbeLiberado,
    required Set<String> existentes,
  }) =>
      [
        canalSom,
        canalSilencioso,
        if (naoPerturbeLiberado)
          for (final c in [canalSomNaoPerturbe, canalSilenciosoNaoPerturbe])
            if (!existentes.contains(c.id)) c,
      ];

  // Avisos sobre o proprio monitoramento ("Monitoramento pausado"): canal
  // separado dos alertas, importancia alta (o tutor precisa ver).
  static const _canalAvisos = AndroidNotificationChannel(
    'puzzleband_avisos',
    'Avisos do monitoramento',
    description: 'Avisa quando o monitoramento com o app fechado parou',
    importance: Importance.high,
  );

  /// Id fixo do "Monitoramento pausado" (o vigia agendado e o aviso na hora).
  static const idMonitoramentoPausado = 0x50424d50; // "PBMP"
  static const tituloPausado = 'Monitoramento pausado';
  static const textoPausado = 'Os alertas com o app fechado pararam. Toque para corrigir.';

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _android?.createNotificationChannel(_canalAvisos);
      _pronto = true;
      await prepararCanaisDeAlerta();
    } catch (e) {
      // Plataforma sem suporte (testes, desktop): o app segue sem notificacao
      debugPrint('Notificacoes indisponiveis: $e');
    }
  }

  /// O app tem acesso ao "Nao perturbe" (ACCESS_NOTIFICATION_POLICY concedido
  /// em Configuracoes -> Acesso ao "Nao perturbe").
  Future<bool> naoPerturbeLiberado() async {
    if (!_pronto) return false;
    try {
      return await _android?.hasNotificationPolicyAccess() ?? false;
    } catch (e) {
      debugPrint('Falha ao ler o acesso ao Nao perturbe: $e');
      return false;
    }
  }

  Future<Set<String>> _canaisExistentes() async {
    try {
      final canais = await _android?.getNotificationChannels() ?? const [];
      return {for (final c in canais) c.id};
    } catch (_) {
      return const {};
    }
  }

  /// Cria os canais de alerta que faltam (ver canaisDeAlertaACriar). Chamado
  /// na abertura e quando o tutor concede o acesso ao "Nao perturbe".
  Future<void> prepararCanaisDeAlerta() async {
    final android = _android;
    if (android == null) return;
    try {
      final criar = canaisDeAlertaACriar(
        naoPerturbeLiberado: await naoPerturbeLiberado(),
        existentes: await _canaisExistentes(),
      );
      for (final canal in criar) {
        await android.createNotificationChannel(canal);
      }
    } catch (e) {
      debugPrint('Falha ao criar os canais de alerta: $e');
    }
  }

  /// As notificacoes do app estao permitidas (Android 13+: POST_NOTIFICATIONS;
  /// antes, o interruptor do app nos ajustes). null: plataforma sem suporte.
  Future<bool?> permitidas() async {
    if (!_pronto) return null;
    try {
      return await _android?.areNotificationsEnabled();
    } catch (e) {
      debugPrint('Falha ao ler a permissao de notificacao: $e');
      return null;
    }
  }

  /// Abre a janela do sistema de POST_NOTIFICATIONS (Android 13+). Devolve se
  /// ficou permitido. Depois de duas recusas o Android nao mostra mais a
  /// janela (devolve false na hora): quem chama abre os ajustes do app.
  Future<bool> pedirPermissao() async {
    if (!_pronto) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Falha ao pedir permissao de notificacao: $e');
      return false;
    }
  }

  NotificationDetails get _detalhesPausado => NotificationDetails(
        android: AndroidNotificationDetails(
          _canalAvisos.id,
          _canalAvisos.name,
          channelDescription: _canalAvisos.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.status,
          styleInformation: const BigTextStyleInformation(textoPausado),
        ),
      );

  /// "Monitoramento pausado - toque para corrigir", agora (tocar abre o app,
  /// que leva a "Configurar alertas").
  Future<void> mostrarMonitoramentoPausado() async {
    if (!_pronto) return;
    try {
      await _plugin.show(
        id: idMonitoramentoPausado,
        title: tituloPausado,
        body: textoPausado,
        notificationDetails: _detalhesPausado,
        payload: 'configurar_alertas',
      );
    } catch (e) {
      debugPrint('Falha ao mostrar o aviso de monitoramento pausado: $e');
    }
  }

  /// Vigia: agenda o "Monitoramento pausado" para daqui a [depois], trocando
  /// o anterior (e apagando um aviso ja mostrado). O servico vivo rearma a
  /// cada poucos minutos; se ele morrer, o aviso dispara sozinho. Agendamento
  /// INEXATO (inexactAllowWhileIdle): pode atrasar alguns minutos, sem a
  /// permissao de alarme exato.
  Future<void> armarVigia(Duration depois) async {
    if (!_pronto) return;
    try {
      await _plugin.cancel(id: idMonitoramentoPausado);
      await _plugin.zonedSchedule(
        id: idMonitoramentoPausado,
        title: tituloPausado,
        body: textoPausado,
        scheduledDate: tz.TZDateTime.from(DateTime.now().add(depois), tz.UTC),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        notificationDetails: _detalhesPausado,
        payload: 'configurar_alertas',
      );
    } catch (e) {
      debugPrint('Falha ao armar o vigia do monitoramento: $e');
    }
  }

  /// Desarma o vigia e apaga o aviso (tutor desligou a opcao ou resolveu).
  Future<void> cancelarVigia() async {
    if (!_pronto) return;
    try {
      await _plugin.cancel(id: idMonitoramentoPausado);
    } catch (e) {
      debugPrint('Falha ao desarmar o vigia do monitoramento: $e');
    }
  }

  /// `atualizacao`: o episodio ja foi notificado e SUBIU de nivel (atencao ->
  /// possivel crise) - a mesma notificacao (mesmo id) e substituida e toca de
  /// novo: pode ser uma crise comecando dentro de um episodio que ja estava
  /// aberto. Quem chama so manda atualizacao quando o nivel sobe.
  Future<void> mostrarAlerta({
    required int id,
    required String titulo,
    required String texto,
    required bool comSom,
    required bool atualizacao,
    String? payload,
    bool ignoraNaoPerturbe = false,
  }) async {
    if (!_pronto) return;
    var ignora = ignoraNaoPerturbe;
    if (ignora) {
      // O par que ignora o "Nao perturbe" precisa existir; se o acesso caiu
      // antes de ele ser criado, vai pelo par normal
      await prepararCanaisDeAlerta();
      final canalDnd = canalDoAlerta(comSom: comSom, ignoraNaoPerturbe: true);
      ignora = (await _canaisExistentes()).contains(canalDnd.id);
    }
    final canal = canalDoAlerta(comSom: comSom, ignoraNaoPerturbe: ignora);
    final detalhes = AndroidNotificationDetails(
      canal.id,
      canal.name,
      channelDescription: canal.description,
      channelBypassDnd: canal.bypassDnd,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(texto),
      ticker: titulo,
      // Explicito: com onlyAlertOnce, a reemissao com o mesmo id (subida de
      // nivel) ficaria em silencio
      silent: false,
      onlyAlertOnce: false,
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
