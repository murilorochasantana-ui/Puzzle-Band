// Tela "Configurar alertas" (flutter test), com um sistema Android falso:
// nada concedido, parcial, tudo concedido, Samsung e nao Samsung; o ✓ ao
// voltar para o app; "Continuar sem isso" e o aviso fixo do Inicio; a opcao
// dos Ajustes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/screens/configurar_alertas_screen.dart';
import 'package:puzzleband/services/configuracao_de_alertas.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';
import 'apoio/sistema_falso.dart';

/// Monta a tela com o sistema falso. Devolve a configuracao e quantas vezes
/// a tela pediu para sair (aoConcluir).
Future<(ConfiguracaoDeAlertas, List<int>)> montar(WidgetTester tester, SistemaFalso sistema) async {
  final servico = await calmo();
  final c = await configuracaoDe(servico.prefs, sistema, mqtt: servico);
  final saidas = <int>[];
  await mostrar(
    tester,
    servico,
    alertas: c,
    tela: ConfigurarAlertasScreen(aoConcluir: () => saidas.add(1)),
    altura: 1200,
  );
  return (c, saidas);
}

FilledButton botaoComecar(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Começar'));

void main() {
  setUpAll(carregarFontes);

  testWidgets('nada concedido: 2 passos sem ✓ e "Começar" desabilitado', (tester) async {
    await montar(tester, SistemaFalso());
    expect(find.text('Permitir notificações'), findsNWidgets(2)); // titulo e botao
    expect(find.text('Rodar sem restrição de bateria'), findsOneWidget);
    expect(find.text('Feito'), findsNothing);
    expect(find.textContaining('Apps em suspensão'), findsNothing);
    expect(botaoComecar(tester).onPressed, isNull);
    expect(find.textContaining('quando todos os passos estiverem feitos'), findsOneWidget);
  });

  testWidgets('cada botao abre a janela certa e o passo ganha o ✓', (tester) async {
    final sistema = SistemaFalso();
    await montar(tester, sistema);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Permitir notificações'));
    await tester.pumpAndSettle();
    expect(sistema.chamadas, ['pedirNotificacoes']);
    expect(find.text('Feito'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Liberar a bateria'));
    await tester.pumpAndSettle();
    expect(sistema.chamadas.last, 'pedirSemRestricaoDeBateria');
    expect(find.text('Feito'), findsNWidgets(2));
    expect(botaoComecar(tester).onPressed, isNotNull);
  });

  testWidgets('parcial: so as notificacoes concedidas', (tester) async {
    await montar(tester, SistemaFalso(notificacoes: true));
    expect(find.text('Feito'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Permitir notificações'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Liberar a bateria'), findsOneWidget);
    expect(botaoComecar(tester).onPressed, isNull);
  });

  testWidgets('tudo concedido: "Começar" destacado inicia o servico e entra no app', (tester) async {
    final sistema = SistemaFalso(notificacoes: true, bateria: true);
    final (c, saidas) = await montar(tester, sistema);
    expect(find.text('Feito'), findsNWidgets(2));
    expect(botaoComecar(tester).onPressed, isNotNull);
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();
    expect(saidas, [1]);
    expect(c.concluida, isTrue);
    expect(sistema.chamadas, contains('iniciarServico'));
    expect(c.monitoramentoAtivo, isTrue);
  });

  testWidgets('Samsung: terceiro passo com o caminho exato, detalhes do app e "Já fiz"', (tester) async {
    final sistema = SistemaFalso(notificacoes: true, bateria: true, marca: 'samsung');
    await montar(tester, sistema);
    expect(find.text('Tirar dos “Apps em suspensão” (Samsung)'), findsOneWidget);
    expect(
      find.textContaining('Configurações → Bateria → Limites de uso em segundo plano e retire o Puzzle Band de '
          '“Apps em suspensão”'),
      findsOneWidget,
    );
    expect(botaoComecar(tester).onPressed, isNull, reason: 'falta o "Já fiz"');

    await tester.tap(find.text('Abrir os ajustes do app'));
    await tester.pumpAndSettle();
    expect(sistema.chamadas.last, 'abrirDetalhesDoApp');
    expect(find.text('Feito'), findsNWidgets(2), reason: 'nao da para verificar sozinho');

    await tester.tap(find.text('Já fiz'));
    await tester.pumpAndSettle();
    expect(find.text('Feito'), findsNWidgets(3));
    expect(botaoComecar(tester).onPressed, isNotNull);
  });

  testWidgets('nao Samsung: sem o passo dos "Apps em suspensão"', (tester) async {
    await montar(tester, SistemaFalso(notificacoes: true, bateria: true, marca: 'Xiaomi'));
    expect(find.textContaining('Apps em suspensão'), findsNothing);
    expect(find.text('Já fiz'), findsNothing);
  });

  testWidgets('ao voltar para o app (onResume), confere de novo e marca o ✓', (tester) async {
    final sistema = SistemaFalso(notificacoes: true, concederAoPedir: false);
    await montar(tester, sistema);
    expect(find.text('Feito'), findsOneWidget);
    sistema.bateria = true; // o tutor liberou na janela do sistema
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Feito'), findsNWidgets(2));
  });

  testWidgets('"Continuar sem isso": aviso, entra no app e o Inicio mostra "Corrigir"', (tester) async {
    final sistema = SistemaFalso();
    final (c, saidas) = await montar(tester, sistema);
    await tester.tap(find.text('Continuar sem isso'));
    await tester.pumpAndSettle();
    expect(find.textContaining('os alertas só chegam com o app aberto'), findsOneWidget);
    await tester.tap(find.text('Continuar mesmo assim'));
    await tester.pumpAndSettle();
    expect(saidas, [1]);
    expect(c.pulada, isTrue);
    expect(c.mostrarAvisoNoInicio, isTrue);

    final servico = await calmo();
    await mostrar(tester, servico, alertas: c);
    expect(find.text('Alertas com o app fechado desativados'), findsOneWidget);
    await tester.tap(find.text('Corrigir'));
    await tester.pumpAndSettle();
    expect(find.text('Configurar alertas'), findsOneWidget);
  });

  testWidgets('Inicio configurado: sem aviso fixo', (tester) async {
    await mostrar(tester, await calmo());
    expect(find.text('Alertas com o app fechado desativados'), findsNothing);
  });

  testWidgets('Ajustes: "Monitorar com o app fechado" para e inicia o servico', (tester) async {
    final servico = await calmo();
    final sistema = SistemaFalso(notificacoes: true, bateria: true, servico: true);
    final c = await configuracaoDe(servico.prefs, sistema, concluida: true, mqtt: servico);
    await mostrar(tester, servico, alertas: c, aba: 3, altura: 1600);
    final chave = find.widgetWithText(SwitchListTile, 'Monitorar com o app fechado');
    expect(tester.widget<SwitchListTile>(chave).value, isTrue);
    await tester.tap(chave);
    await tester.pumpAndSettle();
    expect(sistema.chamadas, containsAllInOrder(['pararServico', 'cancelarAvisoDePausa']));
    expect(tester.widget<SwitchListTile>(chave).value, isFalse);
    expect(find.text('Desligado: os alertas só chegam com o app aberto.'), findsOneWidget);
    await tester.tap(chave);
    await tester.pumpAndSettle();
    expect(sistema.chamadas.contains('iniciarServico'), isTrue);

    await tester.tap(find.text('Configurar alertas'));
    await tester.pumpAndSettle();
    expect(find.text('Rodar sem restrição de bateria'), findsOneWidget);
  });

  testWidgets('primeira abertura: o portao mostra "Configurar alertas" antes do Inicio', (tester) async {
    final servico = ServicoFalso(prefs: (await calmo()).prefs);
    final c = await configuracaoDe(servico.prefs, SistemaFalso());
    await mostrar(tester, servico, alertas: c, tela: const PortaoDosAlertas(child: Text('INICIO')));
    expect(find.text('Configurar alertas'), findsOneWidget);
    expect(find.text('INICIO'), findsNothing);
    await tester.tap(find.text('Continuar sem isso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar mesmo assim'));
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
  });
}
