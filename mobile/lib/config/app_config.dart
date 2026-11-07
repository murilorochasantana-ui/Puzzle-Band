// Configuracao do broker, lida em tempo de compilacao com
//   flutter run --dart-define-from-file=env.json
// (ver env.example.json e docs/app.md). Nenhuma senha fica no codigo.

class AppConfig {
  const AppConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
    required this.childId,
  });

  factory AppConfig.fromEnvironment() {
    const host = String.fromEnvironment('MQTT_HOST');
    const port = String.fromEnvironment('MQTT_PORT', defaultValue: '8883');
    const user = String.fromEnvironment('MQTT_USER');
    const pass = String.fromEnvironment('MQTT_PASS');
    const childId = String.fromEnvironment('CHILD_ID', defaultValue: 'C01');
    return AppConfig(
      host: host.trim(),
      port: int.tryParse(port.trim()) ?? 0,
      user: user.trim(),
      pass: pass,
      childId: childId.trim(),
    );
  }

  final String host;
  final int port;
  final String user;
  final String pass;
  final String childId;

  static final _childIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Variaveis ausentes ou invalidas (vazio = configuracao ok).
  List<String> get problems => [
        if (host.isEmpty) 'MQTT_HOST',
        if (port <= 0 || port > 65535) 'MQTT_PORT',
        if (user.isEmpty) 'MQTT_USER',
        if (pass.isEmpty) 'MQTT_PASS',
        if (!_childIdPattern.hasMatch(childId)) 'CHILD_ID',
      ];

  bool get isValid => problems.isEmpty;

  String topic(String suffix) => 'puzzleband/$childId/$suffix';
}

/// Topicos de uma crianca (tabela completa em docs/mqtt.md).
class Topics {
  Topics(AppConfig config)
      : estado = config.topic('estado'),
        alertas = config.topic('alertas'),
        historico = config.topic('historico'),
        status = config.topic('status'),
        avaliacao = config.topic('avaliacao'),
        ack = config.topic('ack'),
        appStatus = config.topic('app/status'),
        comando = config.topic('comando'),
        comandoResposta = config.topic('comando/resposta');

  final String estado;
  final String alertas;
  final String historico;
  final String status;
  final String avaliacao;
  final String ack;
  final String appStatus;

  /// Ordem do terminal (npm run resetar): o app assina.
  final String comando;

  /// Confirmacao do app para o terminal: o app publica.
  final String comandoResposta;
}
