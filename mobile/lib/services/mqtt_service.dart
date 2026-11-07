// Servico MQTT unico do app do cuidador (ver docs/mqtt.md e docs/app.md).
//
//   - conecta no broker com TLS (porta 8883), keepalive de 60 s e reconexao
//     automatica;
//   - Last Will "offline" (retain) em puzzleband/<id>/app/status e "online"
//     (retain) a cada conexao - o site mostra "App do cuidador: conectado";
//   - assina estado, alertas, historico e status (da pulseira);
//   - publica ack ("Estou ciente") e avaliacao (confirmar/descartar gatilho);
//   - guarda os ultimos 5 min de leituras do estado (todas as metricas) para
//     o grafico ao vivo;
//   - guarda a ultima copia do historico (shared_preferences) para mostrar
//     sem conexao; so aceita historico com origem "pulseira";
//   - assina comando: a ordem "resetar" do terminal (npm run resetar) apaga
//     os dados locais uma vez por id, confirma em comando/resposta e avisa a
//     tela (avisos -> SnackBar). O mesmo apagarDadosLocais serve ao botao
//     "Apagar dados deste aparelho" (Ajustes).
// Mensagem malformada e descartada sem derrubar o app.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../models/sinais.dart';
import 'notification_service.dart';

enum BrokerStatus { naoConfigurado, conectando, conectado, desconectado, erro }

enum Presenca { online, offline, desconhecido }

/// Apaga o que fica fora do MqttService (lembretes, nome, aparencia):
/// PreferenciasLocais.apagarDados.
typedef ApagarDadosLocais = Future<void> Function({required bool manterPreferencias});

class MqttService extends ChangeNotifier {
  MqttService({required this.config, required this.prefs, required this.notificacoes, this.aoApagarDados})
      : _topics = Topics(config);

  final AppConfig config;
  final SharedPreferences prefs;
  final NotificationService notificacoes;
  final ApagarDadosLocais? aoApagarDados;
  final Topics _topics;

  /// SnackBar mostrado quando a ordem do terminal apaga os dados.
  static const avisoDeReset = 'Dados apagados pelo painel para uma nova apresentação.';

  static const janelaSinais = Duration(minutes: 5); // grafico ao vivo
  static const _estadoMaxAtraso = Duration(seconds: 6); // site publica 1x/s
  static const _alertaMaxAtraso = Duration(minutes: 10); // alerta mais velho nao notifica
  static const _maxAlertas = 50;
  static const _maxNotificados = 100;
  static const _maxObservacao = 200;

  static const _chaveHistorico = 'historico_v1';
  static const _chaveAlertasSonoros = 'alertas_sonoros';
  static const _chaveNotificados = 'episodios_notificados';
  static const _chaveClienteId = 'mqtt_cliente_sufixo';
  static const _chaveResetAplicado = 'reset_aplicado_id';

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;
  Timer? _novaTentativa;
  Timer? _frescor;
  Timer? _presenca;
  int _tentativas = 0;
  bool _conectando = false;
  bool _parado = false;
  bool _descartado = false;

  BrokerStatus _brokerStatus = BrokerStatus.conectando;
  String? _ultimoErro;
  Presenca _pulseira = Presenca.desconhecido;
  EstadoAtual? _estado;
  DateTime? _estadoEm;
  bool _aoVivoAnterior = false;
  final JanelaDeSinais _sinais = JanelaDeSinais(duracao: janelaSinais);
  final List<Alerta> _alertas = [];
  List<Episodio> _historico = const [];
  DateTime? _historicoRecebidoEm;
  bool _historicoNestaSessao = false;
  final Map<String, DateTime> _cienteLocal = {};
  final LinkedHashMap<String, NivelRisco> _notificados = LinkedHashMap();
  bool _alertasSonoros = true;
  final StreamController<String> _avisos = StreamController<String>.broadcast();
  Future<void>? _reset;

  // -------------------------------------------------------------------------
  // Leitura (telas)
  // -------------------------------------------------------------------------

  BrokerStatus get brokerStatus => _brokerStatus;
  String? get ultimoErro => _ultimoErro;
  Presenca get pulseira => _brokerStatus == BrokerStatus.conectado ? _pulseira : Presenca.desconhecido;
  EstadoAtual? get estado => _estado;
  DateTime? get estadoRecebidoEm => _estadoEm;

  /// O site esta publicando o estado agora (o modelo roda no site).
  bool get estadoAoVivo =>
      _brokerStatus == BrokerStatus.conectado &&
      _estadoEm != null &&
      DateTime.now().difference(_estadoEm!) <= _estadoMaxAtraso;

  /// Episodio em andamento segundo o estado ao vivo (null se nao ha).
  EpisodioAtivo? get episodioAtivo => estadoAoVivo ? _estado?.episodio : null;

  /// Leituras ao vivo dos ultimos 5 minutos (todas as metricas, a
  /// probabilidade e o nivel), a mais antiga primeiro.
  List<AmostraSinais> get sinaisRecentes => _sinais.amostras;
  List<Alerta> get alertas => List.unmodifiable(_alertas);
  List<Episodio> get historico => _historico;
  DateTime? get historicoRecebidoEm => _historicoRecebidoEm;

  /// Historico recebido nesta sessao e broker conectado (senao e a copia salva).
  bool get historicoAoVivo => _historicoNestaSessao && _brokerStatus == BrokerStatus.conectado;

  bool get alertasSonoros => _alertasSonoros;

  /// Mensagens curtas para a tela (SnackBar), como o aviso do reset.
  Stream<String> get avisos => _avisos.stream;

  /// Id da ultima ordem de reset aplicada (null: nenhuma).
  String? get resetAplicado => prefs.getString(_chaveResetAplicado);

  /// Reset em andamento (apagando), para os testes esperarem.
  @visibleForTesting
  Future<void>? get resetEmAndamento => _reset;

  /// Quando o cuidador marcou "Estou ciente" (confirmado pelo site ou local).
  DateTime? cienteEm(String episodioId) {
    final ativo = _estado?.episodio;
    if (ativo != null && ativo.id == episodioId && ativo.vistoEm != null) return ativo.vistoEm;
    return _cienteLocal[episodioId];
  }

  // -------------------------------------------------------------------------
  // Ciclo de vida
  // -------------------------------------------------------------------------

  Future<void> iniciar() async {
    _carregarPreferencias();
    if (!config.isValid) {
      _brokerStatus = BrokerStatus.naoConfigurado;
      _ultimoErro = 'Configuração ausente: ${config.problems.join(', ')}. '
          'Rode com --dart-define-from-file=env.json (ver docs/app.md).';
      _avisar();
      return;
    }
    _frescor = Timer.periodic(const Duration(seconds: 2), (_) => _verificarFrescor());
    await _conectar();
  }

  /// App voltou para o primeiro plano: reconecta na hora se estava sem conexao.
  void retomar() {
    if (_parado || _conectando || !config.isValid) return;
    if (_brokerStatus == BrokerStatus.desconectado || _brokerStatus == BrokerStatus.erro) {
      _tentativas = 0;
      _conectar();
    }
  }

  /// Saida normal: publica "offline" antes de desconectar (o DISCONNECT
  /// limpo nao dispara o Last Will).
  Future<void> parar() async {
    if (_parado) return;
    _parado = true;
    _novaTentativa?.cancel();
    _presenca?.cancel();
    _frescor?.cancel();
    final client = _client;
    if (client != null && _conectado(client)) {
      publicarTexto(_topics.appStatus, 'offline', MqttQos.atLeastOnce, retain: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      client?.disconnect();
    } catch (_) {}
  }

  @override
  void dispose() {
    _descartado = true;
    _novaTentativa?.cancel();
    _presenca?.cancel();
    _frescor?.cancel();
    _updatesSub?.cancel();
    _avisos.close();
    try {
      _client?.disconnect();
    } catch (_) {}
    super.dispose();
  }

  void _avisar() {
    if (!_descartado) notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Conexao
  // -------------------------------------------------------------------------

  String get _clienteId {
    var sufixo = prefs.getString(_chaveClienteId);
    if (sufixo == null) {
      final r = Random.secure();
      sufixo = List.generate(6, (_) => r.nextInt(16).toRadixString(16)).join();
      prefs.setString(_chaveClienteId, sufixo);
    }
    // Id fixo por instalacao: numa reconexao o broker derruba a sessao antiga
    // (meio aberta) em vez de manter duas.
    return 'puzzleband-app-${config.childId}-$sufixo';
  }

  MqttServerClient _criarCliente() {
    final id = _clienteId;
    final client = MqttServerClient.withPort(config.host, id, config.port)
      ..secure = true // TLS (8883); certificado do EMQX Cloud validado pelas CAs do sistema
      ..keepAlivePeriod = 60
      ..disconnectOnNoResponsePeriod = 20 // sem PINGRESP em 20 s: conexao morta, reconecta
      ..connectTimeoutPeriod = 10000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..onAutoReconnect = _aoIniciarReconexao
      ..onAutoReconnected = _aoConectar;
    client.setProtocolV311();
    client.logging(on: false);
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .startClean()
        .withWillTopic(_topics.appStatus)
        .withWillMessage('offline')
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain()
        .authenticateAs(config.user, config.pass);
    return client;
  }

  bool _conectado(MqttServerClient client) =>
      client.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> _conectar() async {
    if (_conectando || _parado) return;
    _conectando = true;
    await _updatesSub?.cancel();
    _updatesSub = null;
    final antigo = _client;
    if (antigo != null) {
      // o cliente antigo nao pode mais mexer no status nem agendar tentativas
      antigo
        ..onDisconnected = null
        ..onAutoReconnect = null
        ..onAutoReconnected = null;
      try {
        antigo.disconnect();
      } catch (_) {}
    }
    _novaTentativa?.cancel();

    _brokerStatus = BrokerStatus.conectando;
    _avisar();

    final client = _criarCliente();
    _client = client;
    Object? falha;
    try {
      await client.connect();
    } catch (e) {
      falha = e;
    }
    _conectando = false;

    if (_parado || _descartado) {
      try {
        client.disconnect();
      } catch (_) {}
      return;
    }

    if (_conectado(client)) {
      _tentativas = 0;
      client.onDisconnected = _aoDesconectar;
      _updatesSub = client.updates?.listen(_aoReceber);
      client.subscribe(_topics.estado, MqttQos.atMostOnce);
      client.subscribe(_topics.alertas, MqttQos.atLeastOnce);
      client.subscribe(_topics.historico, MqttQos.atLeastOnce);
      client.subscribe(_topics.status, MqttQos.atLeastOnce);
      client.subscribe(_topics.comando, MqttQos.atLeastOnce);
      _aoConectar();
    } else {
      // le o motivo antes do disconnect (que pode limpar o status do cliente)
      final autenticacao = _falhaDeAutenticacao(client);
      _ultimoErro = _descreverFalha(client, falha);
      client
        ..onAutoReconnect = null
        ..onAutoReconnected = null;
      try {
        client.disconnect();
      } catch (_) {}
      _brokerStatus = BrokerStatus.erro;
      _avisar();
      _agendarNovaTentativa(autenticacao: autenticacao);
    }
  }

  void _aoConectar() {
    _ultimoErro = null;
    _brokerStatus = BrokerStatus.conectado;
    _publicarPresenca();
    // Reforco periodico do "online": corrige um "offline" atrasado de uma
    // conexao antiga (Last Will) que chegue depois desta conexao.
    _presenca?.cancel();
    _presenca = Timer.periodic(const Duration(seconds: 60), (_) => _publicarPresenca());
    _avisar();
  }

  void _aoIniciarReconexao() {
    _brokerStatus = BrokerStatus.conectando;
    _pulseira = Presenca.desconhecido;
    _presenca?.cancel();
    _avisar();
  }

  void _aoDesconectar() {
    if (_parado || _descartado) return;
    _presenca?.cancel();
    _brokerStatus = BrokerStatus.desconectado;
    _pulseira = Presenca.desconhecido;
    _avisar();
    _agendarNovaTentativa();
  }

  void _agendarNovaTentativa({bool autenticacao = false}) {
    if (_parado || _descartado) return;
    const atrasos = [2, 5, 10, 20, 30];
    final segundos = autenticacao ? 60 : atrasos[min(_tentativas, atrasos.length - 1)];
    _tentativas += 1;
    _novaTentativa?.cancel();
    _novaTentativa = Timer(Duration(seconds: segundos), _conectar);
  }

  bool _falhaDeAutenticacao(MqttServerClient client) {
    final codigo = client.connectionStatus?.returnCode;
    return codigo == MqttConnectReturnCode.badUsernameOrPassword ||
        codigo == MqttConnectReturnCode.notAuthorized;
  }

  String _descreverFalha(MqttServerClient client, Object? falha) {
    if (_falhaDeAutenticacao(client)) {
      return 'Usuário ou senha recusados pelo broker (confira MQTT_USER e MQTT_PASS no env.json).';
    }
    if (falha is SocketException) return 'Sem rede ou broker inacessível (${falha.message}).';
    if (falha is HandshakeException) return 'Falha no TLS com o broker (${falha.message}).';
    if (falha != null) return 'Falha ao conectar: $falha';
    return 'Não foi possível conectar ao broker.';
  }

  // -------------------------------------------------------------------------
  // Recebimento
  // -------------------------------------------------------------------------

  void _aoReceber(List<MqttReceivedMessage<MqttMessage>> lote) {
    var mudou = false;
    for (final recebida in lote) {
      final mensagem = recebida.payload;
      if (mensagem is! MqttPublishMessage) continue;
      try {
        final texto = utf8.decode(mensagem.payload.message, allowMalformed: true);
        final retida = mensagem.header?.retain ?? false;
        mudou = _tratar(recebida.topic, texto, retida: retida) || mudou;
      } catch (e) {
        debugPrint('Mensagem descartada em ${recebida.topic}: $e');
      }
    }
    if (mudou) _avisar();
  }

  /// Como uma mensagem chegando do broker (avisa a tela se algo mudou).
  /// Devolve true se algo mudou na tela.
  @visibleForTesting
  bool tratarMensagem(String topico, String texto, {bool retida = false}) {
    final mudou = _tratar(topico, texto, retida: retida);
    if (mudou) _avisar();
    return mudou;
  }

  bool _tratar(String topico, String texto, {required bool retida}) {
    if (topico == _topics.estado) return _tratarEstado(texto, retida);
    if (topico == _topics.alertas) return _tratarAlerta(texto);
    if (topico == _topics.historico) return _tratarHistorico(texto);
    if (topico == _topics.comando) return _tratarComando(texto);
    if (topico == _topics.status) {
      final online = parseOnline(texto);
      if (online == null) return false;
      _pulseira = online ? Presenca.online : Presenca.offline;
      return true;
    }
    return false;
  }

  bool _tratarEstado(String texto, bool retida) {
    final novo = EstadoAtual.tryParse(texto);
    if (novo == null) return false;
    final agora = DateTime.now();
    // Mensagem retida pode ser velha (site fechado): vale o horario dela.
    var referencia = agora;
    if (retida) {
      final ts = novo.timestamp;
      referencia = ts == null ? DateTime.fromMillisecondsSinceEpoch(0) : (ts.isAfter(agora) ? agora : ts);
    }
    _estado = novo;
    _estadoEm = referencia;
    _aoVivoAnterior = estadoAoVivo;
    // Pausado no site, o estado repete a mesma leitura: nao entra de novo
    _sinais.registrar(novo, agora, aoVivo: estadoAoVivo);
    return true;
  }

  bool _tratarAlerta(String texto) {
    final alerta = Alerta.tryParse(texto);
    if (alerta == null) return false;
    _alertas.insert(0, alerta);
    if (_alertas.length > _maxAlertas) _alertas.removeRange(_maxAlertas, _alertas.length);
    _notificarSePreciso(alerta);
    return true;
  }

  bool _tratarHistorico(String texto) {
    // So a pulseira publica o historico: outra origem nao substitui a copia
    if (!historicoDaPulseira(texto)) return false;
    final lista = parseHistorico(texto);
    if (lista == null) return false;
    _historico = lista;
    _historicoRecebidoEm = DateTime.now();
    _historicoNestaSessao = true;
    _salvarHistorico();
    return true;
  }

  // -------------------------------------------------------------------------
  // Ordem de reset (npm run resetar) e "Apagar dados deste aparelho"
  // -------------------------------------------------------------------------

  /// A ordem e retida: chega a cada conexao. So a de id novo apaga; o id e
  /// gravado ANTES de apagar, para uma repeticao (QoS 1, reconexao) no meio
  /// da limpeza nao aplicar de novo. A limpeza avisa a tela sozinha.
  bool _tratarComando(String texto) {
    final comando = ComandoResetar.tryParse(texto);
    if (comando == null || comando.id == resetAplicado) return false;
    prefs.setString(_chaveResetAplicado, comando.id);
    _reset = _aplicarReset(comando);
    return false;
  }

  Future<void> _aplicarReset(ComandoResetar comando) async {
    await apagarDadosLocais(manterPreferencias: comando.manterPreferencias);
    publicarTexto(_topics.comandoResposta, respostaDoComando(comando.id), MqttQos.atLeastOnce);
    if (!_descartado) _avisos.add(avisoDeReset);
    // O historico (ou estado) retido de DEPOIS do reset pode ter chegado
    // antes da ordem e acabou de ser apagado: assinar de novo faz o broker
    // reentregar os retidos atuais.
    final client = _client;
    if (client != null && _conectado(client)) {
      try {
        client.resubscribe();
      } catch (e) {
        debugPrint('Falha ao assinar de novo depois do reset: $e');
      }
    }
  }

  /// Apaga o que este celular guarda: a copia do historico, os episodios ja
  /// notificados, os alertas recebidos, o "Estou ciente" local, o buffer dos
  /// graficos e o estado, e (via [aoApagarDados]) os lembretes com os avisos
  /// agendados. Com `manterPreferencias` false, tambem volta ao padrao os
  /// alertas sonoros, o nome da crianca e a aparencia.
  Future<void> apagarDadosLocais({required bool manterPreferencias}) async {
    _historico = const [];
    _historicoRecebidoEm = null;
    _historicoNestaSessao = false;
    _notificados.clear();
    _alertas.clear();
    _cienteLocal.clear();
    _sinais.limpar();
    _estado = null;
    _estadoEm = null;
    _aoVivoAnterior = false;
    if (!manterPreferencias) _alertasSonoros = true;
    _avisar();
    await prefs.remove(_chaveHistorico);
    await prefs.remove(_chaveNotificados);
    if (!manterPreferencias) await prefs.remove(_chaveAlertasSonoros);
    await aoApagarDados?.call(manterPreferencias: manterPreferencias);
  }

  void _verificarFrescor() {
    final agora = estadoAoVivo;
    if (agora != _aoVivoAnterior) {
      _aoVivoAnterior = agora;
      _avisar();
    }
  }

  // -------------------------------------------------------------------------
  // Notificacao (no maximo uma por episodio)
  // -------------------------------------------------------------------------

  void _notificarSePreciso(Alerta alerta) {
    if (!alerta.nivel.isAlerta) return;
    final ts = alerta.timestamp;
    if (ts != null && DateTime.now().difference(ts) > _alertaMaxAtraso) return;

    final chave = alerta.episodioId ?? 'sem_id_${(ts ?? DateTime.now()).millisecondsSinceEpoch}';
    final anterior = _notificados[chave];
    // Mesmo episodio: nao notifica de novo. Se subiu de nivel (atencao ->
    // possivel crise), a MESMA notificacao e atualizada, sem som.
    if (anterior != null && alerta.nivel.rank <= anterior.rank) return;
    final atualizacao = anterior != null;

    _notificados.remove(chave);
    _notificados[chave] = alerta.nivel;
    while (_notificados.length > _maxNotificados) {
      _notificados.remove(_notificados.keys.first);
    }
    prefs.setString(
      _chaveNotificados,
      jsonEncode([for (final e in _notificados.entries) [e.key, e.value.codigo]]),
    );

    final critico = alerta.nivel == NivelRisco.altoRisco;
    final textoGatilho = alerta.gatilho?.texto ?? '';
    notificacoes.mostrarAlerta(
      id: idDeNotificacao(chave),
      titulo: critico ? 'Possível crise' : 'Atenção',
      texto: textoGatilho.isNotEmpty
          ? textoGatilho
          : 'O modelo identificou sinais de ${critico ? 'possível crise' : 'atenção'}. Verifique o ambiente da criança.',
      comSom: _alertasSonoros,
      atualizacao: atualizacao,
      payload: alerta.episodioId,
    );
  }

  // -------------------------------------------------------------------------
  // Publicacao
  // -------------------------------------------------------------------------

  /// Publica se conectado; false sem conexao. Os testes sobrescrevem para
  /// ver o que seria publicado.
  @protected
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) {
    final client = _client;
    if (client == null || !_conectado(client)) return false;
    final builder = MqttClientPayloadBuilder()..addUTF8String(texto);
    try {
      client.publishMessage(topico, qos, builder.payload!, retain: retain);
      return true;
    } catch (e) {
      debugPrint('Falha ao publicar em $topico: $e');
      return false;
    }
  }

  void _publicarPresenca() {
    publicarTexto(_topics.appStatus, 'online', MqttQos.atLeastOnce, retain: true);
  }

  String _agoraIso(DateTime agora) => agora.toUtc().toIso8601String();

  /// "Estou ciente" -> `puzzleband/<id>/ack`. Devolve false sem conexao.
  bool enviarCiente(String episodioId) {
    final agora = DateTime.now();
    final ok = publicarTexto(
      _topics.ack,
      jsonEncode({'episodio_id': episodioId, 'timestamp': _agoraIso(agora), 'origem': 'app'}),
      MqttQos.atLeastOnce,
    );
    if (ok) {
      _cienteLocal[episodioId] = agora;
      _avisar();
    }
    return ok;
  }

  /// Confirmar/descartar gatilho -> `puzzleband/<id>/avaliacao`. A copia local
  /// ja mostra a avaliacao; o site confirma ao republicar o historico.
  bool enviarAvaliacao(Episodio episodio, Avaliacao avaliacao, String observacao) {
    if (avaliacao == Avaliacao.pendente) return false;
    var obs = observacao.trim();
    if (obs.length > _maxObservacao) obs = obs.substring(0, _maxObservacao);
    final agora = DateTime.now();
    final ok = publicarTexto(
      _topics.avaliacao,
      jsonEncode({
        'episodio_id': episodio.id,
        'avaliacao': avaliacao.codigo,
        'observacao': obs,
        'origem': 'app',
        'timestamp': _agoraIso(agora),
      }),
      MqttQos.atLeastOnce,
    );
    if (!ok) return false;
    _historico = [
      for (final e in _historico) e.id == episodio.id ? e.avaliadoPeloApp(avaliacao, obs, agora) : e,
    ];
    _salvarHistorico();
    _avisar();
    return true;
  }

  Future<void> definirAlertasSonoros(bool ligado) async {
    _alertasSonoros = ligado;
    _avisar();
    await prefs.setBool(_chaveAlertasSonoros, ligado);
  }

  // -------------------------------------------------------------------------
  // Persistencia local (shared_preferences)
  // -------------------------------------------------------------------------

  void _carregarPreferencias() {
    _alertasSonoros = prefs.getBool(_chaveAlertasSonoros) ?? true;

    final historico = prefs.getString(_chaveHistorico);
    if (historico != null) {
      final lista = parseHistorico(historico);
      if (lista != null) {
        _historico = lista;
        final recebido = decodeObject(historico)?['recebido_em'];
        _historicoRecebidoEm = recebido is String ? DateTime.tryParse(recebido)?.toLocal() : null;
      }
    }

    try {
      final notificados = jsonDecode(prefs.getString(_chaveNotificados) ?? '[]');
      if (notificados is List) {
        for (final item in notificados) {
          if (item is List && item.length == 2 && item[0] is String) {
            final nivel = NivelRisco.fromCodigo(item[1]);
            if (nivel != null) _notificados[item[0] as String] = nivel;
          }
        }
      }
    } catch (_) {
      // lista corrompida: recomeca vazia
    }
  }

  void _salvarHistorico() {
    final dados = {
      'recebido_em': _historicoRecebidoEm?.toUtc().toIso8601String(),
      'episodios': [for (final e in _historico) e.toJson()],
    };
    prefs.setString(_chaveHistorico, jsonEncode(dados));
  }
}
