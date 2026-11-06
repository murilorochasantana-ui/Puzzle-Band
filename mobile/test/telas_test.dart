// Testes de tela: o que o cuidador ve e consegue fazer, e as regras de
// acessibilidade (leitor de tela, alvos de toque, contraste, fonte ampliada,
// movimento). Os cenarios estao em test/apoio/cenarios.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/screens/login_screen.dart';
import 'package:puzzleband/theme/app_theme.dart';
import 'package:puzzleband/utils/formatters.dart';
import 'package:puzzleband/utils/relogio.dart';
import 'package:puzzleband/widgets/faixa_estado.dart';
import 'package:puzzleband/widgets/gatilho_simples.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';

void main() {
  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  group('Início', () {
    testWidgets('leitor de tela: estado, BPM e gatilho em nós próprios', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await possivelCrise());

      expect(find.bySemanticsLabel('Estado da criança: Possível crise'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Frequência cardíaca: 128 batimentos por minuto, ao vivo')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Provável gatilho: barulho\. Provável gatilho: ruído')), findsOneWidget);

      // So o nivel e anunciado sozinho (liveRegion); o BPM, que muda 1x/s, nao.
      final nivel = tester.getSemantics(find.bySemanticsLabel('Estado da criança: Possível crise'));
      expect(nivel.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      final bpm = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Frequência cardíaca')));
      expect(bpm.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      semantica.dispose();
    });

    testWidgets('nível sempre com ícone + texto (nunca só cor)', (tester) async {
      for (final (cenario, rotulo, icone) in [
        (await calmo(), 'Calmo', Icons.check_circle_outline_rounded),
        (await atencao(), 'Atenção', Icons.warning_amber_rounded),
        (await possivelCrise(), 'Possível crise', Icons.error_rounded),
      ]) {
        await mostrar(tester, cenario);
        final faixa = find.byType(FaixaEstado);
        expect(find.descendant(of: faixa, matching: find.text(rotulo)), findsOneWidget);
        expect(find.descendant(of: faixa, matching: find.byIcon(icone)), findsOneWidget);
      }
    });

    testWidgets('"Estou ciente": botão grande, envia e mostra a confirmação', (tester) async {
      final servico = await possivelCrise();
      await mostrar(tester, servico);

      final botao = find.widgetWithText(FilledButton, 'Estou ciente');
      expect(tester.getSize(botao).height, greaterThanOrEqualTo(Toque.principal));
      await tester.tap(botao);
      await tester.pumpAndSettle();

      expect(servico.cientes.keys, ['ep_5']);
      expect(find.text('Estou ciente'), findsNothing);
      expect(find.text('Você avisou que está ciente às 15:00.'), findsOneWidget);
    });

    testWidgets('"Estou ciente" sem conexão avisa que não foi enviado', (tester) async {
      final servico = (await possivelCrise())..envioFunciona = false;
      await mostrar(tester, servico);
      await tester.tap(find.text('Estou ciente'));
      await tester.pump();
      expect(find.textContaining('o aviso não foi enviado'), findsOneWidget);
      expect(find.text('Estou ciente'), findsOneWidget);
    });

    testWidgets('sem episódio não há botão "Estou ciente"', (tester) async {
      await mostrar(tester, await calmo());
      expect(find.text('Estou ciente'), findsNothing);
      expect(find.text('Tudo conectado'), findsOneWidget);
    });

    testWidgets('estados da conexão dizem o que aconteceu e o que fazer', (tester) async {
      await mostrar(tester, await conectando());
      expect(find.text('Conectando…'), findsOneWidget);

      await mostrar(tester, await semConexao());
      expect(find.text('Sem conexão'), findsOneWidget);
      expect(find.text('Último dado recebido às 14:52:10.'), findsOneWidget);

      await mostrar(tester, await painelEPulseiraOffline());
      expect(find.text('Sem dados ao vivo'), findsOneWidget);
      expect(find.textContaining('O painel (site) parou de enviar às 14:40'), findsOneWidget);
      expect(find.text('Pulseira: desconectada'), findsOneWidget);

      await mostrar(tester, await erroDeConfiguracao());
      expect(find.text('Configuração incompleta'), findsOneWidget);
      expect(find.text('Falta preencher no env.json: MQTT_PASS.'), findsOneWidget);
    });

    testWidgets('nada se move sozinho: a tela assenta (sem animação em loop)', (tester) async {
      // Sem "reduzir movimento": se houvesse pulso continuo, o pumpAndSettle
      // estouraria o tempo.
      await mostrar(tester, await possivelCrise(), reduzirMovimento: false);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('Histórico', () {
    testWidgets('cartão mostra nível, data, duração, gatilho e avaliação', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo(), aba: 2, altura: 2300);
      expect(find.bySemanticsLabel('Nível: Possível crise'), findsNWidgets(2));
      expect(find.text('Hoje, 14:32'), findsOneWidget);
      expect(find.text('Ontem, 18:05'), findsOneWidget);
      expect(find.text('Duração: 1 min 57 s'), findsOneWidget);
      expect(find.text('Provável gatilho: barulho'), findsOneWidget);
      expect(find.text('Gatilho confirmado por você às 09:20.'), findsOneWidget);
      expect(find.text('Indicação descartada no painel às 18:30.'), findsOneWidget);
      expect(find.text('Alerta visto pelo cuidador às 14:33.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('confirmar gatilho: envia com a observação e mostra a confirmação', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 2);

      await tester.tap(find.text('Adicionar observação').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Sirene da escola');
      await tester.tap(find.text('Confirmar gatilho').first);
      await tester.pumpAndSettle();

      expect(servico.avaliacoes.single, ('ep_4', Avaliacao.confirmado, 'Sirene da escola'));
      expect(find.text('Gatilho confirmado por você às 15:00.'), findsOneWidget);
      expect(find.text('Gatilho confirmado e enviado ao painel.'), findsOneWidget);
      expect(find.text('Observação: Sirene da escola'), findsOneWidget);
    });

    testWidgets('descartar sem conexão avisa que não foi enviado', (tester) async {
      final servico = (await calmo())..envioFunciona = false;
      await mostrar(tester, servico, aba: 2);
      await tester.tap(find.text('Descartar').first);
      await tester.pump();
      expect(find.textContaining('a avaliação não foi enviada'), findsOneWidget);
      expect(find.text('Avaliação pendente.'), findsWidgets);
    });

    testWidgets('vazio e sem conexão têm mensagem própria', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 2);
      expect(find.text('Nenhum episódio ainda'), findsOneWidget);

      await mostrar(tester, await semConexao(), aba: 2);
      expect(find.text('Sem conexão: mostrando a última cópia salva, de 05/11 14:50.'), findsOneWidget);
    });
  });

  group('Gráficos e Ajustes', () {
    testWidgets('gráficos com faixa de tempo, resumo em texto e descrição para leitor de tela', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await possivelCrise(), aba: 1);
      expect(find.text('Últimos 5 minutos, ao vivo. Média: 96 bpm.'), findsOneWidget);
      expect(find.text('4 episódios nos últimos 7 dias, 2 de possível crise. Em novembro: 4 episódios.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico da frequência cardíaca.*última leitura 128')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico de episódios por dia: .*Hoje, 2 episódios \(Possível crise\)')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('gráficos sem dados mostram estado vazio', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 1);
      expect(find.text('Aguardando leituras ao vivo'), findsOneWidget);
      expect(find.text('Nenhum episódio nos últimos 7 dias'), findsOneWidget);
    });

    testWidgets('ajustes: título igual à aba e "Alertas sonoros" liga/desliga', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3, altura: 1100);
      expect(find.text('Ajustes'), findsNWidgets(2)); // titulo + aba
      expect(find.text('Privacidade'), findsNothing);
      await tester.tap(find.text('Alertas sonoros'));
      await tester.pumpAndSettle();
      expect(servico.sonoros, isFalse);
    });

    testWidgets('ajustes mostra o erro de configuração', (tester) async {
      await mostrar(tester, await erroDeConfiguracao(), aba: 3, altura: 1100);
      expect(find.text('Servidor: não configurado'), findsOneWidget);
      expect(find.textContaining('Configuração ausente: MQTT_PASS'), findsOneWidget);
    });
  });

  group('Acessibilidade (todas as telas, tema claro e escuro)', () {
    final telas = <String, Future<void> Function(WidgetTester, bool)>{
      'login': (t, e) async => mostrar(t, await calmo(), tela: const LoginScreen(), escuro: e),
      'início (crise)': (t, e) async => mostrar(t, await possivelCrise(), escuro: e),
      'início (sem conexão)': (t, e) async => mostrar(t, await semConexao(), escuro: e),
      'gráficos': (t, e) async => mostrar(t, await possivelCrise(), aba: 1, escuro: e),
      'histórico': (t, e) async => mostrar(t, await calmo(), aba: 2, escuro: e),
      'ajustes': (t, e) async => mostrar(t, await painelEPulseiraOffline(), aba: 3, escuro: e, altura: 1100),
    };

    for (final escuro in [false, true]) {
      for (final MapEntry(key: nome, value: abrir) in telas.entries) {
        testWidgets('$nome${escuro ? ' (escuro)' : ''}: toque >= 48 dp, rótulos e contraste AA', (tester) async {
          final semantica = tester.ensureSemantics();
          await abrir(tester, escuro);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }

    testWidgets('fonte do sistema em 1,3x: nenhuma tela corta nem sobrepõe texto, em todos os estados', (tester) async {
      // Um texto cortado/sobreposto (RenderFlex overflow) vira excecao.
      await mostrar(tester, await calmo(), tela: const LoginScreen(), escala: 1.3);
      expect(tester.takeException(), isNull);
      for (final cenario in [calmo, atencao, possivelCrise, semConexao, conectando, painelEPulseiraOffline, erroDeConfiguracao, semDadosAinda]) {
        for (final aba in [0, 1, 2, 3]) {
          await mostrar(tester, await cenario(), aba: aba, escala: 1.3);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('"reduzir movimento" zera as durações', (tester) async {
      late Duration comMovimento;
      late Duration semMovimento;
      Widget sonda(bool reduzir, void Function(Duration) guardar) => MediaQuery(
            data: MediaQueryData(disableAnimations: reduzir),
            child: Builder(builder: (c) {
              guardar(Movimento.de(c, Movimento.medio));
              return const SizedBox();
            }),
          );
      await tester.pumpWidget(sonda(false, (d) => comMovimento = d));
      await tester.pumpWidget(sonda(true, (d) => semMovimento = d));
      expect(comMovimento, Movimento.medio);
      expect(semMovimento, Duration.zero);
    });
  });

  group('Textos', () {
    test('manchete do gatilho em linguagem simples, sempre "provável"', () {
      expect(mancheteDoGatilho(gatilhoRuido).manchete, 'Provável gatilho: barulho');
      expect(mancheteDoGatilho(gatilhoLuz).manchete, 'Provável gatilho: luz forte ou piscando');
      expect(mancheteDoGatilho(gatilhoDuplo).manchete, 'Provável gatilho: barulho e luz');
      expect(mancheteDoGatilho(gatilhoNenhum).manchete, 'Som e luz não mudaram');
      expect(mancheteDoGatilho(const Gatilho(tipo: 'novo', texto: 'x')).manchete, 'Provável gatilho');
      expect(mancheteDoGatilho(null, emAndamento: true).manchete, 'Gatilho ainda em cálculo');
      expect(mancheteDoGatilho(null).manchete, 'Gatilho não calculado');
    });

    test('datas relativas e contagem', () {
      expect(diaRelativo(DateTime(2026, 11, 5, 14, 32), agoraFixo), 'Hoje, 14:32');
      expect(diaRelativo(DateTime(2026, 11, 4, 9, 5), agoraFixo), 'Ontem, 09:05');
      expect(diaRelativo(DateTime(2026, 11, 2, 10, 40), agoraFixo), '02/11, 10:40');
      expect(contarEpisodios(0), 'nenhum episódio');
      expect(contarEpisodios(1), '1 episódio');
      expect(contarEpisodios(3), '3 episódios');
      expect(nomeDoMes(3), 'março');
    });
  });
}
