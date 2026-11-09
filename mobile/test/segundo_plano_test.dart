// Alertas com o app fechado (flutter test): quem notifica (app aberto x
// servico em primeiro plano), a lista de episodios notificados dividida entre
// os dois isolates, as transicoes sem lacuna e a opcao "Monitorar com o app
// fechado".
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart' show AndroidNotificationChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/configuracao_de_alertas.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:puzzleband/services/regra_de_notificacao.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio/sistema_falso.dart';

const _semRede = AppConfig(host: 'broker.invalido', port: 8883, user: 'app', pass: '', childId: 'C01');
const _alertas = 'puzzleband/C01/alertas';

String alerta(String episodio, String nivel, {DateTime? quando}) => jsonEncode({
      'origem': 'pulseira',
      'timestamp': (quando ?? DateTime.now()).toUtc().toIso8601String(),
      'episodio_id': episodio,
      'nivel_anterior': 'baixo_risco',
      'nivel': nivel,
      'probabilidade': 0.8,
      'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
    });

Alerta alertaDe(String episodio, String nivel) => Alerta.tryParse(alerta(episodio, nivel))!;

class NotificacoesContadas extends NotificationService {
  final titulos = <String>[];
  final comSom = <bool>[];

  @override
  Future<void> mostrarAlerta({
    required int id,
    required String titulo,
    required String texto,
    required bool comSom,
    required bool atualizacao,
    String? payload,
    bool ignoraNaoPerturbe = false,
  }) async {
    titulos.add(titulo);
    this.comSom.add(comSom);
  }
}

/// MqttService sem rede que guarda o que publicaria.
class MqttRegistrado extends MqttService {
  MqttRegistrado({required super.prefs, required super.notificacoes, super.papel})
      : super(config: _semRede);

  final publicados = <(String, String, bool)>[];

  @override
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) {
    publicados.add((topico, texto, retain));
    return false; // sem conexao
  }
}

/// Um "disco" (o shared_preferences nativo) e uma copia em memoria por
/// isolate, como no app: cada lado so ve o que o outro gravou depois de
/// recarregar.
class Disco {
  final valores = <String, Object>{};
}

class CopiaDoIsolate implements EstadoCompartilhado {
  CopiaDoIsolate(this.disco, {this.recarregaDeVerdade = true}) {
    _copia.addAll(disco.valores);
  }

  final Disco disco;
  final bool recarregaDeVerdade;
  final _copia = <String, Object>{};

  @override
  Future<void> recarregar() async {
    if (!recarregaDeVerdade) return;
    _copia
      ..clear()
      ..addAll(disco.valores);
  }

  @override
  String? lerTexto(String chave) => _copia[chave] as String?;

  @override
  bool? lerBooleano(String chave) => _copia[chave] as bool?;

  @override
  Future<void> gravarTexto(String chave, String valor) async {
    _copia[chave] = valor;
    disco.valores[chave] = valor;
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('quem notifica', () {
    test('com o servico rodando, so o servico; sem ele, o app', () {
      expect(quemNotifica(servicoRodando: true), QuemNotifica.servico);
      expect(quemNotifica(servicoRodando: false), QuemNotifica.app);
    });

    test('app aberto com o servico rodando: o app nao notifica nem publica presenca', () async {
      final n = NotificacoesContadas();
      final app = MqttRegistrado(prefs: prefs, notificacoes: n);
      await app.iniciar();
      app.definirServicoRodando(true);
      expect(app.notificaAlertas, isFalse);
      expect(app.publicaPresenca, isFalse);
      app.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
      await app.notificacoesPendentes;
      expect(n.titulos, isEmpty);
    });

    test('a conexao do servico notifica sempre', () async {
      final n = NotificacoesContadas();
      final servico = MqttRegistrado(prefs: prefs, notificacoes: n, papel: PapelDaConexao.servico);
      await servico.iniciar();
      servico.definirServicoRodando(true); // ignorado no papel servico
      expect(servico.notificaAlertas, isTrue);
      servico.tratarMensagem(_alertas, alerta('ep_1', 'alto_risco'));
      await servico.notificacoesPendentes;
      expect(n.titulos, ['Possível crise']);
    });
  });

  group('lista de notificados dividida entre app e servico', () {
    test('cada lado relê o disco antes de decidir: sem duplicata, e a subida toca no outro lado', () async {
      final disco = Disco();
      final app = RegistroDeNotificacoes(CopiaDoIsolate(disco));
      final servico = RegistroDeNotificacoes(CopiaDoIsolate(disco));

      expect(await servico.decidir(alertaDe('ep_1', 'atencao')), isNotNull);
      // o app recebeu o mesmo alerta (QoS 1, troca de dono no meio): nada
      expect(await app.decidir(alertaDe('ep_1', 'atencao')), isNull);
      // subiu de nivel: quem estiver notificando substitui e toca de novo
      final subida = await app.decidir(alertaDe('ep_1', 'alto_risco'));
      expect(subida, isNotNull);
      expect(subida!.atualizacao, isTrue);
      expect(subida.titulo, 'Possível crise');
      // o servico ve a subida que o app gravou
      expect(await servico.decidir(alertaDe('ep_1', 'alto_risco')), isNull);
      expect(await servico.decidir(alertaDe('ep_1', 'atencao')), isNull);
    });

    test('controle: sem recarregar, a copia velha de um lado notificaria de novo', () async {
      final disco = Disco();
      final servico = RegistroDeNotificacoes(CopiaDoIsolate(disco));
      final appSemReload = RegistroDeNotificacoes(CopiaDoIsolate(disco, recarregaDeVerdade: false));
      expect(await servico.decidir(alertaDe('ep_1', 'atencao')), isNotNull);
      expect(await appSemReload.decidir(alertaDe('ep_1', 'atencao')), isNotNull, reason: 'duplicata');
    });

    test('a opcao "Alertas sonoros" e lida do disco a cada alerta (mudada pelo outro lado)', () async {
      final disco = Disco();
      final servico = RegistroDeNotificacoes(CopiaDoIsolate(disco));
      disco.valores[RegistroDeNotificacoes.chaveAlertasSonoros] = false; // o app desligou
      final d = await servico.decidir(alertaDe('ep_1', 'atencao'));
      expect(d!.comSom, isFalse);
    });

    test('com o shared_preferences real: grava logo depois de decidir', () async {
      final registro = RegistroDeNotificacoes(EstadoNasPreferencias(prefs));
      await registro.decidir(alertaDe('ep_9', 'atencao'));
      expect(prefs.getString(RegistroDeNotificacoes.chaveNotificados), contains('ep_9'));
    });

    test('alerta com mais de 10 minutos nao notifica', () async {
      final registro = RegistroDeNotificacoes(CopiaDoIsolate(Disco()));
      final velho = Alerta.tryParse(
        alerta('ep_v', 'alto_risco', quando: DateTime.now().subtract(const Duration(minutes: 11))),
      )!;
      expect(await registro.decidir(velho), isNull);
    });
  });

  group('"Nao perturbe": par de canais de alerta', () {
    test('a subida usa o par da notificacao original, mesmo que o acesso mude no meio', () async {
      final registro = RegistroDeNotificacoes(CopiaDoIsolate(Disco()));
      // sem acesso no "Atencao"; o tutor libera; a subida continua no par normal
      final atencao = await registro.decidir(alertaDe('ep_1', 'atencao'), naoPerturbeLiberado: false);
      expect(atencao!.ignoraNaoPerturbe, isFalse);
      final subida = await registro.decidir(alertaDe('ep_1', 'alto_risco'), naoPerturbeLiberado: true);
      expect(subida!.atualizacao, isTrue);
      expect(subida.ignoraNaoPerturbe, isFalse, reason: 'mesma notificacao, mesmo canal-par');
      expect(subida.id, atencao.id);

      // ao contrario: com acesso no "Atencao", revogado antes da subida
      final outra = await registro.decidir(alertaDe('ep_2', 'atencao'), naoPerturbeLiberado: true);
      expect(outra!.ignoraNaoPerturbe, isTrue);
      final subida2 = await registro.decidir(alertaDe('ep_2', 'alto_risco'), naoPerturbeLiberado: false);
      expect(subida2!.ignoraNaoPerturbe, isTrue);

      // episodio novo segue o acesso atual
      final nova = await registro.decidir(alertaDe('ep_3', 'atencao'), naoPerturbeLiberado: true);
      expect(nova!.ignoraNaoPerturbe, isTrue);
    });

    test('o par usado e lido pelo outro lado (app x servico); o formato antigo vale como par normal', () async {
      final disco = Disco();
      disco.valores[RegistroDeNotificacoes.chaveNotificados] = jsonEncode([
        ['ep_velho', 'atencao'],
      ]);
      final servico = RegistroDeNotificacoes(CopiaDoIsolate(disco));
      final app = RegistroDeNotificacoes(CopiaDoIsolate(disco));
      final velho = await servico.decidir(alertaDe('ep_velho', 'alto_risco'), naoPerturbeLiberado: true);
      expect(velho!.ignoraNaoPerturbe, isFalse);
      await servico.decidir(alertaDe('ep_n', 'atencao'), naoPerturbeLiberado: true);
      final subida = await app.decidir(alertaDe('ep_n', 'alto_risco'), naoPerturbeLiberado: false);
      expect(subida!.ignoraNaoPerturbe, isTrue);
    });

    test('nenhum canal de alerta e apagado; o par que ignora o "Nao perturbe" so nasce com o acesso', () {
      Set<String> ids(List<AndroidNotificationChannel> c) => {for (final x in c) x.id};
      const normal = {'puzzleband_alertas', 'puzzleband_alertas_silenciosos'};
      const dnd = {'puzzleband_alertas_dnd', 'puzzleband_alertas_silenciosos_dnd'};
      // sem acesso: so o par normal (criar um canal com bypassDnd antes do
      // acesso faria o Android cria-lo sem essa opcao, para sempre)
      expect(ids(NotificationService.canaisDeAlertaACriar(naoPerturbeLiberado: false, existentes: {})), normal);
      // acesso concedido: cria o par novo e mantem o normal (que pode ter um
      // "Possivel crise" na tela)
      expect(
        ids(NotificationService.canaisDeAlertaACriar(naoPerturbeLiberado: true, existentes: normal)),
        {...normal, ...dnd},
      );
      // acesso revogado depois: nada alem do par normal e nada a apagar; o par
      // que ignora continua existindo para a subida de um episodio que comecou
      // nele
      expect(
        ids(NotificationService.canaisDeAlertaACriar(naoPerturbeLiberado: false, existentes: {...normal, ...dnd})),
        normal,
      );
      expect(NotificationService.canalDoAlerta(comSom: true, ignoraNaoPerturbe: true).id, 'puzzleband_alertas_dnd');
      expect(NotificationService.canalDoAlerta(comSom: false, ignoraNaoPerturbe: false).id, 'puzzleband_alertas_silenciosos');
      // so os canais de alerta ignoram o "Nao perturbe"
      expect(NotificationService.canalSomNaoPerturbe.bypassDnd, isTrue);
      expect(NotificationService.canalSilenciosoNaoPerturbe.bypassDnd, isTrue);
      expect(NotificationService.canalSom.bypassDnd, isFalse);
      // nomes claros nas configuracoes do Android
      expect(NotificationService.canalSom.name, 'Alertas de crise');
      expect(NotificationService.canalSilencioso.name, 'Alertas de crise (sem som)');
      expect(NotificationService.canalSomNaoPerturbe.name, 'Alertas de crise (ignora Não perturbe)');
      expect(NotificationService.canalSilenciosoNaoPerturbe.name, 'Alertas de crise sem som (ignora Não perturbe)');
    });
  });

  group('transicoes sem lacuna', () {
    test('servico parou: o app volta a notificar e publica "online" na hora; voltou: o app para', () async {
      final n = NotificacoesContadas();
      final app = MqttRegistrado(prefs: prefs, notificacoes: n);
      await app.iniciar();

      app.definirServicoRodando(true);
      app.publicados.clear();
      app.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
      await app.notificacoesPendentes;
      expect(n.titulos, isEmpty);

      // o servico parou (opcao desligada ou morto pelo sistema)
      app.definirServicoRodando(false);
      expect(app.publicaPresenca, isTrue);
      expect(app.publicados, [('puzzleband/C01/app/status', 'online', true)]);
      app.tratarMensagem(_alertas, alerta('ep_2', 'atencao'));
      await app.notificacoesPendentes;
      expect(n.titulos, ['Atenção']);

      // o servico voltou: o app deixa de notificar e de publicar presenca
      app.publicados.clear();
      app.definirServicoRodando(true);
      expect(app.publicados, isEmpty);
      app.tratarMensagem(_alertas, alerta('ep_3', 'alto_risco'));
      await app.notificacoesPendentes;
      expect(n.titulos, ['Atenção']);
    });
  });

  group('opcao "Monitorar com o app fechado"', () {
    test('ligada por padrao; desligar para o servico, desarma o aviso e devolve os alertas ao app', () async {
      final sistema = SistemaFalso(notificacoes: true, bateria: true);
      final app = MqttRegistrado(prefs: prefs, notificacoes: NotificacoesContadas());
      final c = await configuracaoDe(prefs, sistema, concluida: true, mqtt: app);

      expect(c.monitorar, isTrue);
      expect(sistema.chamadas, contains('iniciarServico'), reason: 'tela ja vista + opcao ligada');
      expect(c.servicoRodando, isTrue);
      expect(app.notificaAlertas, isFalse);

      await c.definirMonitorar(false);
      expect(prefs.getBool(ConfiguracaoDeAlertas.chaveMonitorar), isFalse);
      expect(sistema.chamadas, containsAllInOrder(['pararServico', 'cancelarAvisoDePausa']));
      expect(c.servicoRodando, isFalse);
      expect(app.notificaAlertas, isTrue);
      expect(c.mostrarAvisoNoInicio, isFalse, reason: 'desligado pelo tutor: sem aviso fixo');

      sistema.chamadas.clear();
      await c.definirMonitorar(true);
      expect(sistema.chamadas, ['iniciarServico', 'cancelarAvisoDePausa']);
      expect(c.monitoramentoAtivo, isTrue);
      expect(app.notificaAlertas, isFalse);
    });

    test('primeira abertura, "Continuar sem isso", resolver depois e perder uma permissao', () async {
      final sistema = SistemaFalso();
      final c = await configuracaoDe(prefs, sistema);
      expect(c.precisaConfigurar, isTrue, reason: 'primeira abertura');
      expect(sistema.chamadas, isNot(contains('iniciarServico')), reason: 'so depois da tela');

      await c.continuarSemIsso();
      expect(c.precisaConfigurar, isFalse);
      expect(c.mostrarAvisoNoInicio, isTrue);

      sistema
        ..notificacoes = true
        ..bateria = true;
      await c.atualizar();
      expect(c.pulada, isFalse, reason: 'resolvido');
      expect(c.mostrarAvisoNoInicio, isFalse);

      sistema.bateria = false; // revogada depois
      await c.atualizar();
      expect(c.precisaConfigurar, isTrue, reason: 'ao abrir, leva a "Configurar alertas"');
      expect(c.mostrarAvisoNoInicio, isTrue);
    });

    test('servico parado pelo sistema com o app aberto: o app tenta inicia-lo de novo', () async {
      final sistema = SistemaFalso(notificacoes: true, bateria: true);
      final app = MqttRegistrado(prefs: prefs, notificacoes: NotificacoesContadas());
      final c = await configuracaoDe(prefs, sistema, concluida: true, mqtt: app);
      sistema.servico = false; // morto
      sistema.chamadas.clear();
      await c.atualizar();
      expect(sistema.chamadas, ['iniciarServico', 'cancelarAvisoDePausa']);
      expect(c.monitoramentoAtivo, isTrue);
    });

    test('o nome da crianca vai para a notificacao fixa', () async {
      final sistema = SistemaFalso(notificacoes: true, bateria: true);
      final c = await configuracaoDe(prefs, sistema, concluida: true, nome: 'Ana');
      expect(sistema.nomeNoServico, 'Ana');
      await c.nomeMudou();
      expect(sistema.chamadas.last, 'atualizarNome');
    });
  });
}
