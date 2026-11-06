// Imagens das telas (testes golden) em test/goldens/. Para gerar de novo
// depois de mudar o visual:
//   flutter test --update-goldens test/goldens_test.dart
// As imagens dependem da renderizacao de fontes do sistema operacional: foram
// geradas no Windows; em outro sistema, gere de novo antes de comparar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/screens/login_screen.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/utils/relogio.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';

Future<void> imagem(String nome) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nome.png'));

/// Nome de exemplo no cabecalho do Inicio (o padrao seria o CHILD_ID) e,
/// se pedido, um lembrete do dia (com aviso) e um do episodio das 14:32.
Future<PreferenciasLocais> comNome(ServicoFalso servico, {bool lembretes = false}) async {
  final preferencias = preferenciasDe(servico);
  await preferencias.definirNomeCrianca('Lia');
  if (lembretes) {
    await preferencias.salvarLembrete(
      PreferenciasLocais.chaveDia(agoraFixo),
      'Levar o abafador de ruído para a aula de música.',
      avisarEm: DateTime(2026, 11, 5, 17, 30),
      tituloDoAviso: 'Lembrete do dia',
    );
    await preferencias.salvarLembrete(
      PreferenciasLocais.chaveEpisodio('ep_4'),
      'Começou quando o sinal do recreio tocou.',
      tituloDoAviso: 'Lembrete do episódio',
    );
  }
  return preferencias;
}

/// Inicio com o nome de exemplo.
Future<void> inicio(
  WidgetTester tester,
  ServicoFalso servico, {
  bool escuro = false,
  double escala = 1.0,
  double altura = 852,
  bool lembretes = false,
}) async {
  final preferencias = await tester.runAsync(() => comNome(servico, lembretes: lembretes));
  await mostrar(tester, servico, escuro: escuro, escala: escala, altura: altura, preferencias: preferencias);
}

/// Abre o painel "Hoje" (rolando ate ele, se preciso). `noTopo`: rola para o
/// painel ficar no alto da tela (capturas de altura normal).
Future<void> abrirPainel(WidgetTester tester, {bool noTopo = false}) async {
  final botao = find.textContaining(RegExp(r'^Hoje: '));
  await tester.ensureVisible(botao);
  await tester.pumpAndSettle();
  await tester.tap(botao);
  await tester.pumpAndSettle();
  if (noTopo) {
    await Scrollable.ensureVisible(tester.element(botao), alignment: 0.15);
    await tester.pumpAndSettle();
  }
}

/// Toca em "Estou ciente" e mostra o quadro seguinte (a confirmacao, antes
/// dos 5 s).
Future<void> tocarCiente(WidgetTester tester) async {
  await tester.tap(find.text('Estou ciente'));
  await tester.pump();
  await tester.pump();
}

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
      await inicio(tester, await calmo());
      await imagem('inicio_calmo');
    });

    testWidgets('inicio: atencao', (tester) async {
      await inicio(tester, await atencao());
      await imagem('inicio_atencao');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await inicio(tester, await possivelCrise());
      await imagem('inicio_possivel_crise');
    });

    testWidgets('inicio: possivel crise logo depois de "Estou ciente"', (tester) async {
      await inicio(tester, await possivelCrise());
      await tocarCiente(tester);
      await imagem('inicio_possivel_crise_ciente');
    });

    testWidgets('inicio: painel "Hoje" aberto, com lembretes (captura longa)', (tester) async {
      await inicio(tester, await calmo(), altura: 1560, lembretes: true);
      await abrirPainel(tester);
      await imagem('inicio_painel_aberto');
    });

    testWidgets('inicio: painel "Hoje" aberto sem episodios hoje', (tester) async {
      await inicio(tester, await semEpisodiosHoje());
      await abrirPainel(tester, noTopo: true);
      await imagem('inicio_painel_vazio');
    });

    testWidgets('inicio: nome padrao (CHILD_ID) no cabecalho', (tester) async {
      await mostrar(tester, await calmo());
      await imagem('inicio_nome_padrao');
    });

    testWidgets('episodio: detalhe aberto pelo painel, com lembrete (captura longa)', (tester) async {
      await inicio(tester, await calmo(), lembretes: true);
      await abrirPainel(tester);
      final item = find.text('Das 14:32 às 14:33');
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(393 * 2, 940 * 2);
      await tester.pumpAndSettle();
      await imagem('episodio_detalhe');
    });

    testWidgets('lembrete: editor do lembrete do dia', (tester) async {
      await inicio(tester, await calmo());
      await abrirPainel(tester);
      await tester.ensureVisible(find.text('Adicionar lembrete do dia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar lembrete do dia'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Levar o abafador de ruído para a aula de música.');
      await tester.pumpAndSettle();
      await imagem('lembrete_editor');
    });

    testWidgets('inicio: conectando', (tester) async {
      await inicio(tester, await conectando());
      await imagem('inicio_conectando');
    });

    testWidgets('inicio: sem conexao com o servidor', (tester) async {
      await inicio(tester, await semConexao());
      await imagem('inicio_sem_conexao');
    });

    testWidgets('inicio: painel (site) e pulseira offline', (tester) async {
      await inicio(tester, await painelEPulseiraOffline());
      await imagem('inicio_painel_e_pulseira_offline');
    });

    testWidgets('inicio: erro de configuracao (env.json)', (tester) async {
      await inicio(tester, await erroDeConfiguracao());
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
      await inicio(tester, await calmo(), escuro: true);
      await imagem('escuro_inicio_calmo');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await inicio(tester, await possivelCrise(), escuro: true);
      await imagem('escuro_inicio_possivel_crise');
    });

    testWidgets('inicio: painel "Hoje" aberto (captura longa)', (tester) async {
      await inicio(tester, await calmo(), escuro: true, altura: 1560, lembretes: true);
      await abrirPainel(tester);
      await imagem('escuro_inicio_painel_aberto');
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

    testWidgets('inicio: calmo', (tester) async {
      await inicio(tester, await calmo(), escala: 1.3);
      await imagem('fonte_130_inicio_calmo');
    });

    testWidgets('inicio: atencao', (tester) async {
      await inicio(tester, await atencao(), escala: 1.3);
      await imagem('fonte_130_inicio_atencao');
    });

    testWidgets('inicio: possivel crise', (tester) async {
      await inicio(tester, await possivelCrise(), escala: 1.3);
      await imagem('fonte_130_inicio_possivel_crise');
    });

    testWidgets('inicio: possivel crise (captura longa)', (tester) async {
      await inicio(tester, await possivelCrise(), escala: 1.3, altura: 1300);
      await imagem('fonte_130_inicio_possivel_crise_inteira');
    });

    testWidgets('inicio: logo depois de "Estou ciente" (captura longa)', (tester) async {
      await inicio(tester, await possivelCrise(), escala: 1.3, altura: 1300);
      await tocarCiente(tester);
      await imagem('fonte_130_inicio_possivel_crise_ciente');
    });

    testWidgets('inicio: painel "Hoje" aberto (captura longa)', (tester) async {
      await inicio(tester, await calmo(), escala: 1.3, altura: 2000, lembretes: true);
      await abrirPainel(tester);
      await imagem('fonte_130_inicio_painel_aberto');
    });

    testWidgets('inicio: painel "Hoje" aberto sem episodios hoje (captura longa)', (tester) async {
      await inicio(tester, await semEpisodiosHoje(), escala: 1.3, altura: 1300);
      await abrirPainel(tester);
      await imagem('fonte_130_inicio_painel_vazio');
    });

    testWidgets('inicio: sem conexao', (tester) async {
      await inicio(tester, await semConexao(), escala: 1.3);
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
