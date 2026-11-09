// Sistema Android falso para os testes: o que esta concedido, o fabricante
// e o servico em primeiro plano sao campos; as chamadas ficam registradas.
import 'package:puzzleband/services/configuracao_de_alertas.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/sistema_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SistemaFalso implements SistemaAndroid {
  SistemaFalso({
    this.notificacoes = false,
    this.bateria = false,
    this.marca = 'Google',
    this.servico = false,
    this.concederAoPedir = true,
  });

  bool notificacoes;
  bool bateria;
  String marca;
  bool servico;

  /// O tutor aceita na janela do sistema.
  bool concederAoPedir;

  final chamadas = <String>[];
  String? nomeNoServico;

  @override
  Future<bool> notificacoesPermitidas() async => notificacoes;

  @override
  Future<void> pedirNotificacoes() async {
    chamadas.add('pedirNotificacoes');
    if (concederAoPedir) notificacoes = true;
  }

  @override
  Future<bool> semRestricaoDeBateria() async => bateria;

  @override
  Future<void> pedirSemRestricaoDeBateria() async {
    chamadas.add('pedirSemRestricaoDeBateria');
    if (concederAoPedir) bateria = true;
  }

  @override
  Future<String> fabricante() async => marca;

  @override
  Future<void> abrirDetalhesDoApp() async => chamadas.add('abrirDetalhesDoApp');

  @override
  Future<bool> servicoRodando() async => servico;

  @override
  Future<bool> iniciarServico(String nomeCrianca) async {
    chamadas.add('iniciarServico');
    nomeNoServico = nomeCrianca;
    servico = true;
    return true;
  }

  @override
  Future<void> pararServico() async {
    chamadas.add('pararServico');
    servico = false;
  }

  @override
  Future<void> atualizarNomeNoServico(String nomeCrianca) async {
    chamadas.add('atualizarNome');
    nomeNoServico = nomeCrianca;
  }

  @override
  Future<void> cancelarAvisoDePausa() async => chamadas.add('cancelarAvisoDePausa');
}

/// Configuracao montada e carregada. `concluida`: o tutor ja passou pela tela.
Future<ConfiguracaoDeAlertas> configuracaoDe(
  SharedPreferences prefs,
  SistemaFalso sistema, {
  bool concluida = false,
  MqttService? mqtt,
  String nome = 'Lia',
}) async {
  if (concluida) await prefs.setBool(ConfiguracaoDeAlertas.chaveConcluida, true);
  final c = ConfiguracaoDeAlertas(prefs: prefs, sistema: sistema, nomeCrianca: () => nome, mqtt: mqtt);
  await c.atualizar();
  return c;
}
