// Imagens das telas (testes golden) em test/goldens/. Para gerar de novo
// depois de mudar o visual:
//   flutter test --update-goldens test/goldens_test.dart
// As imagens dependem da renderizacao de fontes do sistema operacional: foram
// geradas no Windows; em outro sistema, gere de novo antes de comparar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/screens/login_screen.dart';
import 'package:puzzleband/utils/relogio.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';

Future<void> imagem(String nome) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nome.png'));

void main() {
  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  group('tema claro', () {
    testWidgets('login', (tester) async {
      await mostrar(tester, await calmo(), tela: const LoginScreen());
      await imagem('login');
    });

    testWidgets('inicio: calmo', (tester) async {
      await mostrar(tester, await calmo());
      await imagem('inicio_calmo');
    });

    testWidgets('inicio: atencao', (tester) async {
      await mostrar(tester, await atencao());
      await imagem('inicio_atencao');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await mostrar(tester, await possivelCrise());
      await imagem('inicio_possivel_crise');
    });

    testWidgets('inicio: possivel crise depois de "Estou ciente"', (tester) async {
      await mostrar(tester, await possivelCrise());
      await tester.tap(find.text('Estou ciente'));
      await tester.pumpAndSettle();
      await imagem('inicio_possivel_crise_ciente');
    });

    testWidgets('inicio: conectando', (tester) async {
      await mostrar(tester, await conectando());
      await imagem('inicio_conectando');
    });

    testWidgets('inicio: sem conexao com o servidor', (tester) async {
      await mostrar(tester, await semConexao());
      await imagem('inicio_sem_conexao');
    });

    testWidgets('inicio: painel (site) e pulseira offline', (tester) async {
      await mostrar(tester, await painelEPulseiraOffline());
      await imagem('inicio_painel_e_pulseira_offline');
    });

    testWidgets('inicio: erro de configuracao (env.json)', (tester) async {
      await mostrar(tester, await erroDeConfiguracao());
      await imagem('inicio_erro_configuracao');
    });

    testWidgets('graficos', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1);
      await imagem('graficos');
    });

    testWidgets('graficos: sem dados ainda', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 1);
      await imagem('graficos_sem_dados');
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await imagem('historico');
    });

    testWidgets('historico: lista inteira (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, altura: 2300);
      await imagem('historico_completo');
    });

    testWidgets('historico: depois de confirmar o gatilho', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await tester.tap(find.text('Confirmar gatilho').first);
      await tester.pumpAndSettle();
      await imagem('historico_confirmado');
    });

    testWidgets('historico: vazio', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 2);
      await imagem('historico_vazio');
    });

    testWidgets('historico: sem conexao (copia salva)', (tester) async {
      await mostrar(tester, await semConexao(), aba: 2);
      await imagem('historico_sem_conexao');
    });

    testWidgets('ajustes', (tester) async {
      await mostrar(tester, await painelEPulseiraOffline(), aba: 3, altura: 1100);
      await imagem('ajustes');
    });

    testWidgets('ajustes: erro de configuracao', (tester) async {
      await mostrar(tester, await erroDeConfiguracao(), aba: 3, altura: 1100);
      await imagem('ajustes_erro_configuracao');
    });
  });

  group('tema escuro', () {
    testWidgets('inicio: calmo', (tester) async {
      await mostrar(tester, await calmo(), escuro: true);
      await imagem('escuro_inicio_calmo');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await mostrar(tester, await possivelCrise(), escuro: true);
      await imagem('escuro_inicio_possivel_crise');
    });

    testWidgets('graficos', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1, escuro: true);
      await imagem('escuro_graficos');
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escuro: true);
      await imagem('escuro_historico');
    });
  });

  group('fonte do sistema ampliada (1,3x)', () {
    testWidgets('login', (tester) async {
      await mostrar(tester, await calmo(), tela: const LoginScreen(), escala: 1.3);
      await imagem('fonte_130_login');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await mostrar(tester, await possivelCrise(), escala: 1.3);
      await imagem('fonte_130_inicio_possivel_crise');
    });

    testWidgets('inicio: sem conexao', (tester) async {
      await mostrar(tester, await semConexao(), escala: 1.3);
      await imagem('fonte_130_inicio_sem_conexao');
    });

    testWidgets('graficos', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1, escala: 1.3);
      await imagem('fonte_130_graficos');
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escala: 1.3);
      await imagem('fonte_130_historico');
    });

    testWidgets('historico: vazio', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 2, escala: 1.3);
      await imagem('fonte_130_historico_vazio');
    });

    testWidgets('ajustes', (tester) async {
      await mostrar(tester, await calmo(), aba: 3, escala: 1.3, altura: 1100);
      await imagem('fonte_130_ajustes');
    });
  });
}
