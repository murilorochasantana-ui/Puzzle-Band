// Alertas com o app fechado (flutter test): quem notifica (app aberto x
// servico em primeiro plano), a lista de episodios notificados no banco
// local dividida entre os dois motores Dart (duas conexoes no mesmo arquivo
// SQLite, em WAL), as transicoes sem lacuna e a opcao "Monitorar com o app
// fechado". A concorrencia de verdade (isolates separados) fica em
// test/banco_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart' show AndroidNotificationChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;
import 'package:puzzleband/config/app_config.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/banco.dart';
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
  MqttRegistrado({required super.prefs, required super.notificacoes, super.papel, BancoPuzzleBand? banco})
      : super(config: _semRede, banco: banco ?? BancoPuzzleBand.emMemoria());

  final publicados = <(String, String, bool)>[];

  @override
  bool publicarTexto(String topico, String texto, MqttQos qos, {bool retain = false}) {
    publicados.add((topico, texto, retain));
    return false; // sem conexao
  }
}

/// Um arquivo de banco novo numa pasta temporaria (apagada no fim).
Future<File> arquivoNovo() async {
  final pasta = await Directory.systemTemp.createTemp('puzzleband_banco_');
  addTearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } catch (_) {}
  });
  return File('${pasta.path}${Platform.pathSeparator}puzzleband.db');
}

/// Duas conexoes no mesmo arquivo, como as telas e o servico no celular.
Future<(BancoPuzzleBand, BancoPuzzleBand)> appEServico() async {
  final arquivo = await arquivoNovo();
  final app = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
  final servico = BancoPuzzleBand.noArquivo(arquivo, emSegundoPlano: false);
  addTearDown(() async {
    await app.close();
    await servico.close();
  });
  return (app, servico);
}

RegistroDeNotificacoes registro(BancoPuzzleBand banco, {bool comSom = true}) =>
    RegistroDeNotificacoes(banco: banco, alertasSonoros: () async => comSom);

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

  group('lista de notificados no banco, dividida entre app e servico', () {
    test('cada lado ve o que o outro gravou: sem duplicata, e a subida toca no outro lado', () async {
      final (bancoApp, bancoServico) = await appEServico();
      final app = registro(bancoApp);
      final servico = registro(bancoServico);

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

    test('app e servico decidindo o mesmo alerta ao mesmo tempo: so um notifica', () async {
      final (bancoApp, bancoServico) = await appEServico();
      final app = registro(bancoApp);
      final servico = registro(bancoServico);
      for (var i = 0; i < 20; i++) {
        final decisoes = await Future.wait([
          app.decidir(alertaDe('ep_$i', 'alto_risco')),
          servico.decidir(alertaDe('ep_$i', 'alto_risco')),
        ]);
        expect(decisoes.whereType<DecisaoDeNotificacao>().length, 1, reason: 'ep_$i');
      }
    });

    test('a conexao do app (MqttService) e a do servico no mesmo arquivo: uma notificacao so', () async {
      final (bancoApp, bancoServico) = await appEServico();
      final nApp = NotificacoesContadas();
      final nServico = NotificacoesContadas();
      final app = MqttRegistrado(prefs: prefs, notificacoes: nApp, banco: bancoApp);
      final servico = MqttRegistrado(prefs: prefs, notificacoes: nServico, papel: PapelDaConexao.servico, banco: bancoServico);
      await app.iniciar();
      await servico.iniciar();
      // instante da troca de dono: as duas conexoes acham que notificam
      expect(app.notificaAlertas && servico.notificaAlertas, isTrue);
      app.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
      servico.tratarMensagem(_alertas, alerta('ep_1', 'atencao'));
      await Future.wait([app.notificacoesPendentes, servico.notificacoesPendentes]);
      expect([...nApp.titulos, ...nServico.titulos], ['Atenção']);
    });

    test('a opcao "Alertas sonoros" e lida do disco a cada alerta (mudada pelo outro lado)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final servico = RegistroDeNotificacoes(banco: banco, alertasSonoros: alertasSonorosDoDisco(prefs));
      await prefs.setBool(RegistroDeNotificacoes.chaveAlertasSonoros, false); // o app desligou
      final d = await servico.decidir(alertaDe('ep_1', 'atencao'));
      expect(d!.comSom, isFalse);
    });

    test('grava no banco logo ao decidir (antes de mostrar)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      await registro(banco).decidir(alertaDe('ep_9', 'atencao'));
      expect((await banco.notificados())['ep_9']?.nivel, NivelRisco.atencao);
    });

    test('guarda no maximo 100 (os mais recentes)', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final r = registro(banco);
      final inicio = DateTime.now();
      for (var i = 0; i < 105; i++) {
        await r.decidir(alertaDe('ep_$i', 'atencao'), agora: inicio.add(Duration(milliseconds: i)));
      }
      final guardados = await banco.notificados();
      expect(guardados.length, BancoPuzzleBand.maxNotificados);
      expect(guardados.containsKey('ep_0'), isFalse);
      expect(guardados.containsKey('ep_104'), isTrue);
    });

    test('alerta com mais de 10 minutos nao notifica', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final velho = Alerta.tryParse(
        alerta('ep_v', 'alto_risco', quando: DateTime.now().subtract(const Duration(minutes: 11))),
      )!;
      expect(await registro(banco).decidir(velho), isNull);
    });
  });

  group('"Nao perturbe": par de canais de alerta', () {
    test('a subida usa o par da notificacao original, mesmo que o acesso mude no meio', () async {
      final banco = BancoPuzzleBand.emMemoria();
      addTearDown(banco.close);
      final r = registro(banco);
      // sem acesso no "Atencao"; o tutor libera; a subida continua no par normal
      final atencao = await r.decidir(alertaDe('ep_1', 'atencao'), naoPerturbeLiberado: false);
      expect(atencao!.ignoraNaoPerturbe, isFalse);
      final subida = await r.decidir(alertaDe('ep_1', 'alto_risco'), naoPerturbeLiberado: true);
      expect(subida!.atualizacao, isTrue);
      expect(subida.ignoraNaoPerturbe, isFalse, reason: 'mesma notificacao, mesmo canal-par');
      expect(subida.id, atencao.id);

      // ao contrario: com acesso no "Atencao", revogado antes da subida
      final outra = await r.decidir(alertaDe('ep_2', 'atencao'), naoPerturbeLiberado: true);
      expect(outra!.ignoraNaoPerturbe, isTrue);
      final subida2 = await r.decidir(alertaDe('ep_2', 'alto_risco'), naoPerturbeLiberado: false);
      expect(subida2!.ignoraNaoPerturbe, isTrue);

      // episodio novo segue o acesso atual
      final nova = await r.decidir(alertaDe('ep_3', 'atencao'), naoPerturbeLiberado: true);
      expect(nova!.ignoraNaoPerturbe, isTrue);
    });

    test('o par usado e lido pelo outro lado (app x servico); o importado do formato antigo vale como par normal', () async {
      final (bancoApp, bancoServico) = await appEServico();
      // vindo da lista antiga do shared_preferences ([id, nivel])
      await bancoServico.importarNotificado('ep_velho', NivelRisco.atencao, ignoraNaoPerturbe: false, em: DateTime.now());
      final servico = registro(bancoServico);
      final app = registro(bancoApp);
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
