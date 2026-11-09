// Estado da configuracao dos alertas com o app fechado (tela "Configurar
// alertas", opcao "Monitorar com o app fechado" nos Ajustes e o aviso fixo
// do Inicio). Ver docs/app.md, "Configuracao na primeira abertura".
//
//   - passos: notificacoes permitidas, sem restricao de bateria e, so em
//     Samsung, "Apps em suspensao" (nao da para verificar: o tutor confirma
//     com "Ja fiz"). Reavaliados ao voltar para o app (atualizar);
//   - passo OPCIONAL (nao conta para o "Comecar"): acesso ao "Nao perturbe",
//     para os canais de alerta ignorarem o modo;
//   - a opcao (ligada por padrao) inicia e para o servico em primeiro plano;
//   - quem notifica: o MqttService das telas e avisado de que o servico
//     comecou ou parou (definirServicoRodando) - sem lacuna nem duplicata;
//   - com o app aberto, o servico e conferido a cada 5 s; se parou e a opcao
//     esta ligada, o app tenta inicia-lo de novo.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mqtt_service.dart';
import 'sistema_android.dart';

class ConfiguracaoDeAlertas extends ChangeNotifier {
  ConfiguracaoDeAlertas({
    required this.prefs,
    required this.sistema,
    required this.nomeCrianca,
    this.mqtt,
  });

  final SharedPreferences prefs;
  final SistemaAndroid sistema;
  final String Function() nomeCrianca;
  final MqttService? mqtt;

  static const chaveMonitorar = 'monitorar_app_fechado';
  static const chaveConcluida = 'config_alertas_concluida';
  static const chavePulada = 'config_alertas_pulada';
  static const chaveSamsung = 'samsung_suspensao_ok';
  static const intervaloDeConferencia = Duration(seconds: 5);

  bool _notificacoes = false;
  bool _bateria = false;
  bool _samsung = false;
  bool _naoPerturbe = false;
  bool _servico = false;
  bool _carregado = false;
  bool _descartado = false;
  Timer? _conferencia;

  // -------------------------------------------------------------------------
  // Leitura
  // -------------------------------------------------------------------------

  bool get carregado => _carregado;
  bool get notificacoesPermitidas => _notificacoes;
  bool get semRestricaoDeBateria => _bateria;

  /// Celular Samsung: mostra o passo "Apps em suspensao".
  bool get ehSamsung => _samsung;
  bool get samsungConfirmado => prefs.getBool(chaveSamsung) ?? false;

  /// Passo opcional: os alertas tocam mesmo no "Nao perturbe".
  bool get naoPerturbeLiberado => _naoPerturbe;
  bool get servicoRodando => _servico;

  /// Opcao "Monitorar com o app fechado" (ligada por padrao).
  bool get monitorar => prefs.getBool(chaveMonitorar) ?? true;

  /// O tutor ja passou pela tela (com "Comecar" ou "Continuar sem isso").
  bool get concluida => prefs.getBool(chaveConcluida) ?? false;

  /// Saiu por "Continuar sem isso" e ainda nao resolveu.
  bool get pulada => prefs.getBool(chavePulada) ?? false;

  /// Todos os passos com o ✓.
  bool get tudoConcedido => _notificacoes && _bateria && (!_samsung || samsungConfirmado);

  /// Os alertas chegam com o app fechado agora.
  bool get monitoramentoAtivo => monitorar && tudoConcedido && _servico;

  /// Aviso fixo no Inicio: "Alertas com o app fechado desativados - Corrigir".
  bool get mostrarAvisoNoInicio => _carregado && concluida && monitorar && !monitoramentoAtivo;

  /// Ao abrir: mostrar "Configurar alertas" antes do Inicio (primeira vez, ou
  /// algo se perdeu depois de configurado - e nao foi o tutor que pulou).
  bool get precisaConfigurar =>
      _carregado && (!concluida || (monitorar && !pulada && !monitoramentoAtivo));

  // -------------------------------------------------------------------------
  // Acoes
  // -------------------------------------------------------------------------

  /// Le de novo o que o sistema concedeu (ao abrir e ao voltar para o app) e,
  /// com a opcao ligada e a tela ja vista, garante o servico rodando.
  Future<void> atualizar() async {
    final permitidas = await sistema.notificacoesPermitidas();
    final bateria = await sistema.semRestricaoDeBateria();
    final fabricante = await sistema.fabricante();
    final naoPerturbe = await sistema.naoPerturbeLiberado();
    _notificacoes = permitidas;
    _bateria = bateria;
    _samsung = fabricante.toLowerCase().contains('samsung');
    // Acabou de liberar: cria ja o par de canais que ignora o "Nao perturbe"
    // (aparece nas configuracoes do Android; os alertas passam a usa-lo)
    if (naoPerturbe && !_naoPerturbe) await sistema.prepararCanaisDeAlerta();
    _naoPerturbe = naoPerturbe;
    _carregado = true;
    if (tudoConcedido && pulada) await prefs.setBool(chavePulada, false); // resolvido
    await _conferirServico(iniciarSeParado: concluida && monitorar);
    _avisar();
  }

  Future<void> pedirNotificacoes() async {
    await sistema.pedirNotificacoes();
    await atualizar();
  }

  Future<void> pedirSemRestricaoDeBateria() async {
    await sistema.pedirSemRestricaoDeBateria();
    await atualizar(); // a janela e outra Activity: o resultado chega no onResume
  }

  Future<void> abrirDetalhesDoApp() => sistema.abrirDetalhesDoApp();

  /// Passo opcional: abre a tela do sistema de acesso ao "Nao perturbe" (o
  /// resultado chega no onResume).
  Future<void> pedirNaoPerturbe() async {
    await sistema.abrirAcessoNaoPerturbe();
    await atualizar();
  }

  /// "Ja fiz" do passo Samsung.
  Future<void> confirmarSamsung() async {
    await prefs.setBool(chaveSamsung, true);
    _avisar();
  }

  /// "Comecar": a tela foi vista; com a opcao ligada, inicia o servico.
  Future<void> comecar() async {
    await prefs.setBool(chaveConcluida, true);
    await prefs.setBool(chavePulada, false);
    await _conferirServico(iniciarSeParado: monitorar);
    _avisar();
  }

  /// "Continuar sem isso": entra no app; o Inicio mostra o aviso fixo ate
  /// resolver. O servico ainda e iniciado se a opcao estiver ligada (o que
  /// estiver concedido ja ajuda).
  Future<void> continuarSemIsso() async {
    await prefs.setBool(chaveConcluida, true);
    await prefs.setBool(chavePulada, true);
    await _conferirServico(iniciarSeParado: monitorar);
    _avisar();
  }

  /// Opcao "Monitorar com o app fechado". Desligar para o servico na hora (as
  /// telas voltam a notificar e a publicar "online") e desarma o aviso
  /// "Monitoramento pausado".
  Future<void> definirMonitorar(bool ligado) async {
    await prefs.setBool(chaveMonitorar, ligado);
    if (ligado) {
      await _conferirServico(iniciarSeParado: true);
    } else {
      await sistema.pararServico();
      await sistema.cancelarAvisoDePausa();
      _definirServico(false);
    }
    _avisar();
  }

  /// O nome da crianca mudou (notificacao fixa do servico).
  Future<void> nomeMudou() => sistema.atualizarNomeNoServico(nomeCrianca());

  /// App em primeiro plano: confere o servico a cada 5 s (parado pelo
  /// sistema -> as telas notificam na hora e o app tenta inicia-lo de novo).
  void retomar() {
    _conferencia?.cancel();
    _conferencia = Timer.periodic(intervaloDeConferencia, (_) {
      _conferirServico(iniciarSeParado: concluida && monitorar);
    });
    unawaited(atualizar());
  }

  /// App foi para o segundo plano: para a conferencia (o servico segue).
  void pausar() {
    _conferencia?.cancel();
    _conferencia = null;
  }

  Future<void> _conferirServico({required bool iniciarSeParado}) async {
    var rodando = await sistema.servicoRodando();
    if (!rodando && iniciarSeParado) {
      rodando = await sistema.iniciarServico(nomeCrianca());
      if (rodando) await sistema.cancelarAvisoDePausa(); // o vigia volta com a tarefa
    }
    _definirServico(rodando);
  }

  void _definirServico(bool rodando) {
    final mudou = rodando != _servico;
    _servico = rodando;
    mqtt?.definirServicoRodando(rodando);
    if (mudou) _avisar();
  }

  void _avisar() {
    if (!_descartado) notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _conferencia?.cancel();
    super.dispose();
  }
}

/// Entrega a configuracao as telas (como o AppScope). Sem o scope (testes de
/// tela antigos), as telas se comportam como "tudo configurado".
class ConfiguracaoScope extends InheritedNotifier<ConfiguracaoDeAlertas> {
  const ConfiguracaoScope({super.key, required ConfiguracaoDeAlertas configuracao, required super.child})
      : super(notifier: configuracao);

  static ConfiguracaoDeAlertas? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConfiguracaoScope>()?.notifier;

  static ConfiguracaoDeAlertas? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ConfiguracaoScope>()?.notifier;
}
