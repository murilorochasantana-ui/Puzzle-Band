// Imagens das telas (testes golden) em test/goldens/. Para gerar de novo
// depois de mudar o visual:
//   flutter test --update-goldens test/goldens_test.dart
// As imagens dependem da renderizacao de fontes do sistema operacional: foram
// geradas no Windows; em outro sistema, gere de novo antes de comparar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/screens/graficos_screen.dart';
import 'package:puzzleband/screens/configurar_alertas_screen.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/theme/app_theme.dart';
import 'package:puzzleband/utils/relogio.dart';
import 'package:puzzleband/widgets/selo_avaliacao.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';
import 'apoio/sistema_falso.dart';

Future<void> imagem(String nome) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nome.png'));

/// "Configurar alertas" com o sistema falso (primeira abertura).
Future<void> configurarAlertas(WidgetTester tester, SistemaFalso sistema, {bool escuro = false}) async {
  final servico = await calmo();
  final c = await configuracaoDe(servico.prefs, sistema);
  await mostrar(tester, servico, alertas: c, tela: const ConfigurarAlertasScreen(), escuro: escuro, altura: 1600);
}

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

/// Segura o dedo no grafico ao vivo (80% da largura: no trecho de crise) e
/// mostra o balao. Devolve o gesto para soltar depois da imagem.
Future<TestGesture> abrirBalao(WidgetTester tester) async {
  final area = tester.getRect(find.byType(GraficoSinais));
  final gesto = await tester.startGesture(Offset(area.left + area.width * 0.8, area.center.dy));
  await tester.pump();
  return gesto;
}

/// Solta o dedo e espera o balao sumir (sem timers pendentes no fim do teste).
Future<void> soltarBalao(WidgetTester tester, TestGesture gesto) async {
  await gesto.up();
  await tester.pump(Grafico.balaoVisivel);
  await tester.pumpAndSettle();
}

/// Rola ate o grafico de 7 dias e toca na barra de terca (03/11), abrindo o
/// balao com os totais do dia.
Future<void> abrirSeteDias(WidgetTester tester) async {
  await centralizar(tester, find.byType(GraficoSeteDias));
  final area = tester.getRect(find.byType(GraficoSeteDias));
  await tester.tapAt(Offset(area.left + area.width * 4.5 / 7, area.bottom - 40));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 900)); // fade do balao
}

/// Fecha o balao do grafico de 7 dias (some sozinho depois de 3 s).
Future<void> fecharSeteDias(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Abre o cartao do episodio das 14:32 (possivel crise a confirmar) e
/// descarta; espera o aviso sumir.
Future<void> descartarEp4(WidgetTester tester) async {
  await tocarNoMeio(tester, cartao('ep_4'));
  await tocarNoMeio(tester, find.text('Descartar'));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  // Mostra o cartao inteiro: o selo "Descartado" no resumo e o botao vermelho
  await centralizar(tester, find.descendant(of: cartao('ep_4'), matching: find.text('14:32–14:33')), alinhamento: 0.12);
}

/// Toca no selo "Possivel crise · a confirmar" do episodio das 14:32.
Future<void> abrirPendente(WidgetTester tester) => tocarNoMeio(
      tester,
      find.descendant(of: cartao('ep_4'), matching: find.text(SeloAvaliacao.textoPendente)),
    );

void main() {
  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  group('tema claro', () {
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

    testWidgets('inicio: BPM 190 (grupo centrado)', (tester) async {
      await inicio(tester, await comBpm(atencao(), 190));
      await imagem('inicio_bpm_190');
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

    testWidgets('graficos: BPM ao vivo', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1);
      await imagem('graficos');
    });

    testWidgets('graficos: balao com todas as metricas', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1);
      final gesto = await abrirBalao(tester);
      await imagem('graficos_balao');
      await soltarBalao(tester, gesto);
    });

    testWidgets('graficos: 7 dias, com o balao do dia', (tester) async {
      await mostrar(tester, await calmo(), aba: 1);
      await abrirSeteDias(tester);
      await imagem('graficos_7dias');
      await fecharSeteDias(tester);
    });

    testWidgets('graficos: painel parado (dados congelados)', (tester) async {
      await mostrar(tester, await painelEPulseiraOffline(), aba: 1);
      await imagem('graficos_painel_parado');
    });

    testWidgets('graficos: sem dados ainda', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 1);
      await imagem('graficos_sem_dados');
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await imagem('historico');
    });

    testWidgets('historico: cartao expandido (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, altura: 1300);
      await tocarNoMeio(tester, cartao('ep_3'));
      await centralizar(tester, cartao('ep_3'), alinhamento: 0.2);
      await imagem('historico_cartao_expandido');
    });

    testWidgets('historico: possivel crise aguardando confirmacao (selo tocado)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await abrirPendente(tester);
      await imagem('historico_pendente');
    });

    testWidgets('historico: episodio descartado (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, altura: 1150);
      await descartarEp4(tester);
      await imagem('historico_descartado');
    });

    testWidgets('historico: filtro por dia', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await tocarNoMeio(tester, diaDoCalendario(3));
      await imagem('historico_filtro_dia');
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
      await mostrar(tester, await painelEPulseiraOffline(), aba: 3, altura: 1650);
      await imagem('ajustes');
    });

    testWidgets('configurar alertas: Samsung, so as notificacoes concedidas', (tester) async {
      await configurarAlertas(tester, SistemaFalso(notificacoes: true, marca: 'samsung'));
      await imagem('configurar_alertas');
    });

    testWidgets('configurar alertas: tudo concedido ("Começar" destacado)', (tester) async {
      await configurarAlertas(tester, SistemaFalso(notificacoes: true, bateria: true));
      await imagem('configurar_alertas_pronto');
    });

    testWidgets('inicio: alertas com o app fechado desativados', (tester) async {
      final servico = await calmo();
      final c = await configuracaoDe(servico.prefs, SistemaFalso(notificacoes: true), concluida: true);
      await mostrar(tester, servico, alertas: c, preferencias: await comNome(servico));
      await imagem('inicio_aviso_monitoramento');
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

    testWidgets('graficos: balao', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1, escuro: true);
      final gesto = await abrirBalao(tester);
      await imagem('escuro_graficos_balao');
      await soltarBalao(tester, gesto);
    });

    testWidgets('graficos: 7 dias', (tester) async {
      await mostrar(tester, await calmo(), aba: 1, escuro: true);
      await abrirSeteDias(tester);
      await imagem('escuro_graficos_7dias');
      await fecharSeteDias(tester);
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escuro: true);
      await imagem('escuro_historico');
    });

    testWidgets('historico: descartado (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escuro: true, altura: 1150);
      await descartarEp4(tester);
      await imagem('escuro_historico_descartado');
    });

    // --- Demais telas no escuro (Ajustes > Aparência > Escuro). Os outros
    // estados no escuro sao cobertos pelo teste de contraste (telas_test.dart).

    testWidgets('inicio: atencao', (tester) async {
      await inicio(tester, await atencao(), escuro: true);
      await imagem('escuro_inicio_atencao');
    });

    testWidgets('inicio: sem conexao', (tester) async {
      await inicio(tester, await semConexao(), escuro: true);
      await imagem('escuro_inicio_sem_conexao');
    });

    testWidgets('episodio: detalhe com lembrete (captura longa)', (tester) async {
      await inicio(tester, await calmo(), escuro: true, lembretes: true);
      await abrirPainel(tester);
      final item = find.text('Das 14:32 às 14:33');
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(393 * 2, 940 * 2);
      await tester.pumpAndSettle();
      await imagem('escuro_episodio_detalhe');
    });

    testWidgets('historico: cartao confirmado aberto (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escuro: true, altura: 1300);
      await tocarNoMeio(tester, cartao('ep_3'));
      await centralizar(tester, cartao('ep_3'), alinhamento: 0.2);
      await imagem('escuro_historico_cartao_expandido');
    });

    testWidgets('ajustes, com Aparencia (captura longa)', (tester) async {
      await mostrar(tester, await painelEPulseiraOffline(), aba: 3, escuro: true, altura: 1650);
      await imagem('escuro_ajustes');
    });

    testWidgets('configurar alertas: Samsung, so as notificacoes concedidas', (tester) async {
      await configurarAlertas(tester, SistemaFalso(notificacoes: true, marca: 'samsung'), escuro: true);
      await imagem('escuro_configurar_alertas');
    });

  });

  group('fonte do sistema ampliada (1,3x)', () {
    testWidgets('inicio: possivel crise (captura longa)', (tester) async {
      await inicio(tester, await possivelCrise(), escala: 1.3, altura: 1300);
      await imagem('fonte_130_inicio_possivel_crise_inteira');
    });

    testWidgets('inicio: painel "Hoje" aberto (captura longa)', (tester) async {
      await inicio(tester, await calmo(), escala: 1.3, altura: 2000, lembretes: true);
      await abrirPainel(tester);
      await imagem('fonte_130_inicio_painel_aberto');
    });

    testWidgets('inicio: BPM 190', (tester) async {
      await inicio(tester, await comBpm(atencao(), 190), escala: 1.3);
      await imagem('fonte_130_inicio_bpm_190');
    });

    testWidgets('graficos: balao', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1, escala: 1.3);
      await centralizar(tester, find.byType(GraficoSinais), alinhamento: 0.3);
      final gesto = await abrirBalao(tester);
      await imagem('fonte_130_graficos_balao');
      await soltarBalao(tester, gesto);
    });

    testWidgets('graficos: 7 dias', (tester) async {
      await mostrar(tester, await calmo(), aba: 1, escala: 1.3);
      await abrirSeteDias(tester);
      await imagem('fonte_130_graficos_7dias');
      await fecharSeteDias(tester);
    });

    testWidgets('historico', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escala: 1.3);
      await imagem('fonte_130_historico');
    });

    testWidgets('historico: cartao expandido (captura longa)', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, escala: 1.3, altura: 1500);
      await abrirPendente(tester);
      await centralizar(tester, cartao('ep_4'), alinhamento: 0.1);
      await imagem('fonte_130_historico_expandido');
    });

    testWidgets('ajustes', (tester) async {
      await mostrar(tester, await calmo(), aba: 3, escala: 1.3, altura: 2000);
      await imagem('fonte_130_ajustes');
    });
  });
}
