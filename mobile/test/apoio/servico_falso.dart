// MqttService sem rede para os testes de tela: os getters que as telas leem
// sao sobrescritos e o estado e montado a mao em cada cenario.
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/sinais.dart';
import 'package:puzzleband/services/aviso_de_lembrete.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:puzzleband/utils/relogio.dart';

const configOk = AppConfig(host: 'g12cbd17.ala.us-east-1.emqxsl.com', port: 8883, user: 'app', pass: 'x', childId: 'C01');
const configSemSenha = AppConfig(host: 'g12cbd17.ala.us-east-1.emqxsl.com', port: 8883, user: 'app', pass: '', childId: 'C01');

class ServicoFalso extends MqttService {
  ServicoFalso({required super.prefs, super.config = configOk}) : super(notificacoes: NotificationService());

  BrokerStatus broker = BrokerStatus.conectado;
  String? erro;
  Presenca presenca = Presenca.online;
  EstadoAtual? estadoAtual;
  DateTime? recebidoEm;
  bool aoVivo = true;
  List<AmostraSinais> sinais = const [];
  List<Episodio> episodios = const [];
  DateTime? historicoEm;
  bool historicoVivo = true;
  bool sonoros = true;

  /// false simula o envio sem conexao (o servico real devolve false).
  bool envioFunciona = true;
  final cientes = <String, DateTime>{};
  final avaliacoes = <(String, Avaliacao, String)>[];

  @override
  BrokerStatus get brokerStatus => broker;
  @override
  String? get ultimoErro => erro;
  @override
  Presenca get pulseira => broker == BrokerStatus.conectado ? presenca : Presenca.desconhecido;
  @override
  EstadoAtual? get estado => estadoAtual;
  @override
  DateTime? get estadoRecebidoEm => recebidoEm;
  @override
  bool get estadoAoVivo => aoVivo && broker == BrokerStatus.conectado && estadoAtual != null;
  @override
  EpisodioAtivo? get episodioAtivo => estadoAoVivo ? estadoAtual?.episodio : null;
  @override
  List<AmostraSinais> get sinaisRecentes => sinais;
  @override
  List<Episodio> get historico => episodios;
  @override
  DateTime? get historicoRecebidoEm => historicoEm;
  @override
  bool get historicoAoVivo => historicoVivo;
  @override
  bool get alertasSonoros => sonoros;

  @override
  DateTime? cienteEm(String episodioId) {
    final ativo = estadoAtual?.episodio;
    if (ativo != null && ativo.id == episodioId && ativo.vistoEm != null) return ativo.vistoEm;
    return cientes[episodioId];
  }

  @override
  bool enviarCiente(String episodioId) {
    if (!envioFunciona) return false;
    cientes[episodioId] = relogio();
    notifyListeners();
    return true;
  }

  @override
  bool enviarAvaliacao(Episodio episodio, Avaliacao avaliacao, String observacao) {
    if (!envioFunciona || avaliacao == Avaliacao.pendente) return false;
    avaliacoes.add((episodio.id, avaliacao, observacao.trim()));
    episodios = [
      for (final e in episodios) e.id == episodio.id ? e.avaliadoPeloApp(avaliacao, observacao.trim(), relogio()) : e,
    ];
    notifyListeners();
    return true;
  }

  @override
  Future<void> definirAlertasSonoros(bool ligado) async {
    sonoros = ligado;
    notifyListeners();
  }
}

/// Aviso de lembrete sem plugin: guarda o que seria agendado.
class AvisoFalso implements AvisoDeLembrete {
  bool funciona = true;
  final agendados = <int, (DateTime, String, String)>{};
  final cancelados = <int>[];

  @override
  Future<bool> agendar({required int id, required DateTime quando, required String titulo, required String texto}) async {
    if (!funciona) return false;
    agendados[id] = (quando, titulo, texto);
    return true;
  }

  @override
  Future<void> cancelar(int id) async {
    agendados.remove(id);
    cancelados.add(id);
  }
}
