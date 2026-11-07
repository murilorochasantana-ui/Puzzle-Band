// Cenarios das telas (dados realistas, horario fixo) e a montagem do app num
// celular de 393 x 852 dp.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/main.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/sinais.dart';
import 'package:puzzleband/services/app_scope.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'servico_falso.dart';

/// Quinta-feira, 05/11/2026, 15:00.
final agoraFixo = DateTime(2026, 11, 5, 15, 0);

const gatilhoRuido = Gatilho(
  tipo: 'ruido',
  texto: 'Provável gatilho: ruído (45 → 88 dB, cerca de 12 s antes da alteração fisiológica).',
);
const gatilhoLuz = Gatilho(
  tipo: 'luminosidade',
  texto: 'Provável gatilho: luminosidade (300 → 1150 lux, cerca de 8 s antes da alteração fisiológica).',
);
const gatilhoNenhum = Gatilho(
  tipo: 'nenhum_ambiental',
  texto: 'Sem gatilho ambiental aparente: luz e ruído estáveis. '
      'A causa pode ser outra (social, rotina, desconforto físico).',
);
const gatilhoDuplo = Gatilho(
  tipo: 'ruido_e_luminosidade',
  texto: 'Provável gatilho: ruído (50 → 84 dB, cerca de 6 s antes da alteração fisiológica) e '
      'luminosidade (oscilando entre 120 e 900 lux, cerca de 4 s antes da alteração fisiológica).',
);

/// Sinais dos ultimos 5 minutos (uma amostra a cada 2 s). Com `pico`, os
/// sinais sobem no fim (o barulho como gatilho) e o nivel passa por Atencao
/// (e por Possivel crise, se `pico` >= 40). A probabilidade so existe depois
/// dos primeiros 30 s, como no site. A ultima amostra e o BPM ao vivo
/// mostrado na Home.
List<AmostraSinais> serieSinais({required double base, double pico = 0, required double atual}) => [
      for (var i = 0; i < 150; i++) _amostra(i, base: base, pico: pico, atual: atual),
    ];

AmostraSinais _amostra(int i, {required double base, required double pico, required double atual}) {
  final subida = i > 110 ? min(1.0, (i - 110) / 20) : 0.0;
  final k = subida * pico / 42; // 0 (calmo) a 1 (crise)
  final nivel = pico == 0 || subida <= 0.2
      ? NivelRisco.baixoRisco
      : (subida > 0.6 && pico >= 40 ? NivelRisco.altoRisco : NivelRisco.atencao);
  return AmostraSinais(
    hora: agoraFixo.subtract(Duration(seconds: 298 - i * 2)),
    nivel: nivel,
    bpm: i == 149 ? atual : base + 3 * sin(i / 6) + 2 * sin(i / 2.3) + pico * subida,
    edaUs: 2.4 + 0.2 * sin(i / 7) + 6.5 * k,
    hrvMs: 52 + 3 * sin(i / 5) - 26 * k,
    gyroDps: 1.2 + 0.4 * sin(i / 3) + 4.5 * k,
    regularidade: 0.18 + 0.03 * sin(i / 4) + 0.5 * k,
    luzLux: 310 + 15 * sin(i / 9),
    ruidoDb: 46 + 2 * sin(i / 2.7) + 40 * k,
    probabilidade: i < 15 ? null : 0.1 + 0.02 * sin(i / 5) + 0.73 * k,
  );
}

/// Episodio curto confirmado no painel (dias anteriores do calendario).
Episodio _confirmado(String id, DateTime inicio, int segundos, NivelRisco nivel, Gatilho gatilho) => Episodio(
      id: id,
      fonte: 'pulseira',
      inicio: inicio,
      duracaoS: segundos.toDouble(),
      encerramento: 'normalizou',
      nivelMaximo: nivel,
      probabilidadeMaxima: nivel == NivelRisco.altoRisco ? 0.81 : 0.6,
      gatilho: gatilho,
      avaliacao: Avaliacao.confirmado,
      avaliacaoOrigem: 'site',
      avaliacaoEm: inicio.add(const Duration(minutes: 20)),
    );

List<Episodio> historicoExemplo() => [
      Episodio(
        id: 'ep_4',
        fonte: 'pulseira',
        inicio: DateTime(2026, 11, 5, 14, 32),
        duracaoS: 117,
        encerramento: 'normalizou',
        nivelMaximo: NivelRisco.altoRisco,
        probabilidadeMaxima: 0.86,
        gatilho: gatilhoRuido,
        vistoEm: DateTime(2026, 11, 5, 14, 33),
      ),
      Episodio(
        id: 'ep_3',
        fonte: 'pulseira',
        inicio: DateTime(2026, 11, 5, 9, 10),
        duracaoS: 65,
        encerramento: 'normalizou',
        nivelMaximo: NivelRisco.atencao,
        probabilidadeMaxima: 0.61,
        gatilho: gatilhoLuz,
        avaliacao: Avaliacao.confirmado,
        observacao: 'A luz do refeitório piscou antes.',
        avaliacaoOrigem: 'app',
        avaliacaoEm: DateTime(2026, 11, 5, 9, 20),
      ),
      Episodio(
        id: 'ep_2',
        fonte: 'manual',
        inicio: DateTime(2026, 11, 4, 18, 5),
        duracaoS: 42,
        encerramento: 'normalizou',
        nivelMaximo: NivelRisco.atencao,
        probabilidadeMaxima: 0.55,
        gatilho: gatilhoNenhum,
        avaliacao: Avaliacao.descartado,
        avaliacaoOrigem: 'site',
        avaliacaoEm: DateTime(2026, 11, 4, 18, 30),
      ),
      // 03/11: 7 crises confirmadas (dia vermelho no calendario)
      _confirmado('ep_3n_7', DateTime(2026, 11, 3, 18, 45), 95, NivelRisco.altoRisco, gatilhoRuido),
      _confirmado('ep_3n_6', DateTime(2026, 11, 3, 16, 20), 48, NivelRisco.atencao, gatilhoLuz),
      _confirmado('ep_3n_5', DateTime(2026, 11, 3, 13, 15), 130, NivelRisco.altoRisco, gatilhoDuplo),
      _confirmado('ep_3n_4', DateTime(2026, 11, 3, 11, 30), 40, NivelRisco.atencao, gatilhoRuido),
      _confirmado('ep_3n_3', DateTime(2026, 11, 3, 10, 5), 72, NivelRisco.atencao, gatilhoNenhum),
      _confirmado('ep_3n_2', DateTime(2026, 11, 3, 9, 40), 150, NivelRisco.altoRisco, gatilhoRuido),
      _confirmado('ep_3n_1', DateTime(2026, 11, 3, 8, 12), 55, NivelRisco.atencao, gatilhoLuz),
      Episodio(
        id: 'ep_1',
        fonte: 'manual',
        inicio: DateTime(2026, 11, 2, 10, 40),
        duracaoS: 180,
        encerramento: 'interrompido',
        nivelMaximo: NivelRisco.altoRisco,
        probabilidadeMaxima: 0.79,
        gatilho: gatilhoDuplo,
      ),
      // 01/11: 3 crises confirmadas (dia amarelo no calendario)
      _confirmado('ep_1n_3', DateTime(2026, 11, 1, 17, 55), 66, NivelRisco.atencao, gatilhoRuido),
      _confirmado('ep_1n_2', DateTime(2026, 11, 1, 14, 10), 110, NivelRisco.altoRisco, gatilhoLuz),
      _confirmado('ep_1n_1', DateTime(2026, 11, 1, 9, 30), 45, NivelRisco.atencao, gatilhoNenhum),
    ];

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<ServicoFalso> calmo() async => ServicoFalso(prefs: await _prefs())
  ..estadoAtual = EstadoAtual(
    timestamp: agoraFixo,
    fonte: 'pulseira',
    nivel: NivelRisco.baixoRisco,
    probabilidade: 0.12,
    leituras: const Leituras(timestamp: 'l1', bpm: 82),
    mediaBpm5min: 79,
  )
  ..recebidoEm = agoraFixo
  ..sinais = serieSinais(base: 80, atual: 82)
  ..episodios = historicoExemplo()
  ..historicoEm = agoraFixo;

Future<ServicoFalso> atencao() async => (await calmo())
  ..estadoAtual = EstadoAtual(
    timestamp: agoraFixo,
    fonte: 'pulseira',
    nivel: NivelRisco.atencao,
    probabilidade: 0.58,
    leituras: const Leituras(timestamp: 'l2', bpm: 104),
    mediaBpm5min: 88,
    gatilho: gatilhoLuz,
    episodio: EpisodioAtivo(id: 'ep_5', inicio: DateTime(2026, 11, 5, 14, 56), nivelMaximo: NivelRisco.atencao),
  )
  ..sinais = serieSinais(base: 82, pico: 22, atual: 104);

Future<ServicoFalso> possivelCrise() async => (await calmo())
  ..estadoAtual = EstadoAtual(
    timestamp: agoraFixo,
    fonte: 'pulseira',
    nivel: NivelRisco.altoRisco,
    probabilidade: 0.83,
    leituras: const Leituras(timestamp: 'l3', bpm: 128),
    mediaBpm5min: 96,
    gatilho: gatilhoRuido,
    episodio: EpisodioAtivo(id: 'ep_5', inicio: DateTime(2026, 11, 5, 14, 58), nivelMaximo: NivelRisco.altoRisco),
  )
  ..sinais = serieSinais(base: 84, pico: 42, atual: 128);

Future<ServicoFalso> semConexao() async => (await calmo())
  ..broker = BrokerStatus.desconectado
  ..aoVivo = false
  ..recebidoEm = DateTime(2026, 11, 5, 14, 52, 10)
  ..historicoVivo = false
  ..historicoEm = DateTime(2026, 11, 5, 14, 50);

Future<ServicoFalso> conectando() async => (await calmo())
  ..broker = BrokerStatus.conectando
  ..aoVivo = false
  ..estadoAtual = null
  ..recebidoEm = null
  ..sinais = const [];

/// Broker conectado, mas o painel (site) parou e a pulseira caiu.
Future<ServicoFalso> painelEPulseiraOffline() async => (await calmo())
  ..aoVivo = false
  ..presenca = Presenca.offline
  ..recebidoEm = DateTime(2026, 11, 5, 14, 40);

Future<ServicoFalso> erroDeConfiguracao() async => ServicoFalso(prefs: await _prefs(), config: configSemSenha)
  ..broker = BrokerStatus.naoConfigurado
  ..aoVivo = false
  ..historicoVivo = false
  ..erro = 'Configuração ausente: MQTT_PASS. Rode com --dart-define-from-file=env.json (ver docs/app.md).';

/// Conectado e ao vivo, mas ainda sem nenhum episodio nem leitura de BPM.
Future<ServicoFalso> semDadosAinda() async => (await calmo())
  ..episodios = const []
  ..sinais = const [];

/// Calmo e ao vivo; o historico tem episodios, mas nenhum de hoje.
Future<ServicoFalso> semEpisodiosHoje() async {
  final servico = await calmo();
  return servico..episodios = [for (final e in servico.episodios) if (e.inicio.day != agoraFixo.day) e];
}

/// Preferencias locais (nome da crianca e lembretes) no mesmo
/// shared_preferences do servico, com o aviso falso.
PreferenciasLocais preferenciasDe(MqttService servico, {AvisoFalso? aviso}) =>
    PreferenciasLocais(prefs: servico.prefs, nomePadrao: servico.config.childId, aviso: aviso ?? AvisoFalso());

/// Monta o app (tema real, fontes reais) e espera assentar. `aba`: 0 Inicio,
/// 1 Graficos, 2 Historico, 3 Ajustes. `tela` substitui a navegacao (Login).
Future<void> mostrar(
  WidgetTester tester,
  MqttService servico, {
  int aba = 0,
  Widget? tela,
  bool escuro = false,
  double escala = 1.0,
  double altura = 852,
  bool reduzirMovimento = true,
  PreferenciasLocais? preferencias,
}) async {
  tester.view.physicalSize = Size(393 * 2, altura * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  // Desmonta a tela anterior: sem isso, chamar mostrar() de novo no mesmo
  // teste reaproveitava a rota inicial (a aba e a tela antigas).
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    AppScope(
      service: servico,
      child: PreferenciasScope(
        preferencias: preferencias ?? preferenciasDe(servico),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.claro(),
          darkTheme: AppTheme.escuro(),
          themeMode: escuro ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(escala),
              disableAnimations: reduzirMovimento,
            ),
            child: child!,
          ),
          routes: {'/home': (_) => const MainNavigation()},
          home: tela ?? MainNavigation(initialIndex: aba),
        ),
      ),
    ),
  );
  await carregarImagens(tester);
  await tester.pumpAndSettle();
}

/// Decodifica as imagens da tela (o logo): no teste isso so termina fora do
/// relogio falso do testWidgets.
Future<void> carregarImagens(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final elemento in find.byType(Image).evaluate()) {
      await precacheImage((elemento.widget as Image).image, elemento);
    }
  });
  await tester.pump();
}

/// O mesmo cenario com outro BPM ao vivo (null: sem leitura de BPM).
Future<ServicoFalso> comBpm(Future<ServicoFalso> cenario, double? bpm) async {
  final servico = await cenario;
  final e = servico.estadoAtual!;
  return servico
    ..estadoAtual = EstadoAtual(
      timestamp: e.timestamp,
      fonte: e.fonte,
      nivel: e.nivel,
      probabilidade: e.probabilidade,
      leituras: Leituras(timestamp: 'bpm-$bpm', bpm: bpm, edaUs: 3, ruidoDb: 50),
      mediaBpm5min: e.mediaBpm5min,
      gatilho: e.gatilho,
      episodio: e.episodio,
    );
}

/// Rola ate [alvo] ficar no meio da tela (longe dos cabecalhos fixos do
/// Historico) e toca nele.
Future<void> tocarNoMeio(WidgetTester tester, Finder alvo) async {
  await centralizar(tester, alvo);
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

Future<void> centralizar(WidgetTester tester, Finder alvo, {double alinhamento = 0.5}) async {
  // Listas preguicosas so constroem o que esta perto da tela: rola ate achar
  if (alvo.evaluate().isEmpty) {
    final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(alvo, 300, scrollable: vertical.first);
  }
  await Scrollable.ensureVisible(tester.element(alvo), alignment: alinhamento);
  await tester.pumpAndSettle();
}

/// Cartao resumido de um episodio no Historico e um dia do calendario de
/// novembro de 2026.
Finder cartao(String id) => find.byKey(ValueKey(id));
Finder diaDoCalendario(int dia) => find.byKey(ValueKey('dia-2026-11-$dia'));
