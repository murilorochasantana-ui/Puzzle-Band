// Cenarios das telas (dados realistas, horario fixo) e a montagem do app num
// celular de 393 x 852 dp.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/main.dart';
import 'package:puzzleband/models/models.dart';
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

/// BPM dos ultimos 5 minutos (um ponto a cada 2 s), subindo no fim se `pico`.
/// O ultimo ponto e o BPM ao vivo mostrado na Home.
List<BpmPonto> serieBpm({required double base, double pico = 0, required double atual}) => [
      for (var i = 0; i < 149; i++)
        BpmPonto(
          agoraFixo.subtract(Duration(seconds: 300 - i * 2)),
          base + 3 * sin(i / 6) + 2 * sin(i / 2.3) + (i > 110 ? pico * min(1, (i - 110) / 20) : 0),
        ),
      BpmPonto(agoraFixo, atual),
    ];

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
  ..bpm = serieBpm(base: 80, atual: 82)
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
  ..bpm = serieBpm(base: 82, pico: 22, atual: 104);

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
  ..bpm = serieBpm(base: 84, pico: 42, atual: 128);

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
  ..bpm = const [];

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
  ..bpm = const [];

/// Calmo e ao vivo; o historico tem episodios, mas nenhum de hoje.
Future<ServicoFalso> semEpisodiosHoje() async {
  final servico = await calmo();
  return servico..episodios = [for (final e in servico.episodios) if (e.inicio.day != agoraFixo.day) e];
}

/// Preferencias locais (nome da crianca e lembretes) no mesmo
/// shared_preferences do servico, com o aviso falso.
PreferenciasLocais preferenciasDe(ServicoFalso servico, {AvisoFalso? aviso}) =>
    PreferenciasLocais(prefs: servico.prefs, nomePadrao: servico.config.childId, aviso: aviso ?? AvisoFalso());

/// Monta o app (tema real, fontes reais) e espera assentar. `aba`: 0 Inicio,
/// 1 Graficos, 2 Historico, 3 Ajustes. `tela` substitui a navegacao (Login).
Future<void> mostrar(
  WidgetTester tester,
  ServicoFalso servico, {
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
