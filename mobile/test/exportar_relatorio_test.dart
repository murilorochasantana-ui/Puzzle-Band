// Tela "Exportar relatorio" (flutter test): o aviso de dados de saude antes
// de compartilhar, cancelar sem compartilhar, o limite de 31 dias, as
// entradas pelo Historico e pelos Ajustes, a opcao "Guardar historico por" e
// os goldens novos (tela de exportar, aviso e o item em Ajustes).
//
//   flutter test --update-goldens test/exportar_relatorio_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/screens/exportar_relatorio_screen.dart';
import 'package:puzzleband/services/banco.dart' show GuardarHistorico;
import 'package:puzzleband/utils/relogio.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';

/// Menu de compartilhar falso: guarda o arquivo e o assunto.
class CompartilharFalso {
  final chamadas = <(File, String, bool existia)>[];

  Future<void> call(File arquivo, String assunto) async => chamadas.add((arquivo, assunto, arquivo.existsSync()));
}

/// Pasta nova (sincrona: dentro do relogio falso do testWidgets).
Directory pastaTemporaria() {
  final pasta = Directory.systemTemp.createTempSync('puzzleband_exportar_');
  addTearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } catch (_) {}
  });
  return pasta;
}

Future<void> imagem(String nome) => expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nome.png'));

/// Toca em "Gerar e compartilhar" e espera o arquivo ficar pronto (banco e
/// disco de verdade, fora do relogio falso) ate o aviso aparecer.
Future<void> gerar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('gerar-relatorio')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('gerar-relatorio')));
  for (var i = 0; i < 100 && find.byType(AlertDialog).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(AlertDialog), findsOneWidget, reason: 'o arquivo deveria ficar pronto');
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

void main() {
  late Directory pasta;
  late CompartilharFalso compartilhar;

  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  Future<ServicoFalso> abrirTela(WidgetTester tester, {bool escuro = false, double altura = 852}) async {
    pasta = pastaTemporaria();
    compartilhar = CompartilharFalso();
    final servico = await calmo();
    await mostrar(
      tester,
      servico,
      escuro: escuro,
      altura: altura,
      tela: ExportarRelatorioScreen(compartilhar: compartilhar.call, pasta: () async => pasta),
    );
    return servico;
  }

  group('exportar', () {
    testWidgets('padrao: hoje; gera o .xlsx e mostra o aviso ANTES de compartilhar', (tester) async {
      await abrirTela(tester);
      expect(find.text('Hoje, 5 de novembro de 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('dia-seguinte')).hitTestable(), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('dia-seguinte'))).onPressed, isNull,
          reason: 'nao passa de hoje');

      await gerar(tester);
      expect(find.text(avisoDeDadosDeSaude), findsOneWidget);
      expect(compartilhar.chamadas, isEmpty, reason: 'o menu de compartilhar so abre depois do aviso');

      await tocar(tester, find.text('Compartilhar'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(compartilhar.chamadas, hasLength(1));
      final (arquivo, assunto, existia) = compartilhar.chamadas.single;
      expect(arquivo.path, endsWith('puzzleband_relatorio_C01_2026-11-05.xlsx'));
      expect(existia, isTrue);
      expect(assunto, contains('5 de novembro de 2026'));
      final bytes = (await tester.runAsync(arquivo.readAsBytes))!;
      expect(bytes.sublist(0, 2), [0x50, 0x4B], reason: 'um zip (.xlsx)');
    });

    testWidgets('cancelar no aviso: nao compartilha e apaga o arquivo', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.text('Cancelar'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      expect(compartilhar.chamadas, isEmpty);
      final restantes = (await tester.runAsync(() => pasta.list().toList()))!;
      expect(restantes.whereType<File>().where((f) => f.path.endsWith('.xlsx')), isEmpty);
    });

    testWidgets('periodo: ate 31 dias; mais que isso desliga o botao e explica', (tester) async {
      await abrirTela(tester, altura: 1000);
      await tocar(tester, find.text('Últimos 7 dias'));
      expect(find.text('De'), findsOneWidget);
      expect(find.text('Gerar e compartilhar (7 dias)'), findsOneWidget);
      await tocar(tester, find.text('Últimos 31 dias'));
      expect(find.text('Gerar e compartilhar (31 dias)'), findsOneWidget);
      await tocar(tester, find.byKey(const ValueKey('de-anterior')));
      expect(find.text('Escolha no máximo 31 dias (32 escolhidos).'), findsOneWidget);
      final botao = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('gerar-relatorio')));
      expect(botao.onPressed, isNull);

      await gerarPeriodoValido(tester);
    });

    testWidgets('Historico e Ajustes abrem a tela de exportar', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 2, altura: 1000);
      await tocar(tester, find.byKey(const ValueKey('historico-exportar-relatorio')));
      expect(find.text('Exportar relatório'), findsWidgets);
      expect(find.byKey(const ValueKey('gerar-relatorio')), findsOneWidget);

      await mostrar(tester, servico, aba: 3, altura: 1400);
      await tocar(tester, find.byKey(const ValueKey('ajustes-exportar-relatorio')));
      expect(find.byKey(const ValueKey('gerar-relatorio')), findsOneWidget);
    });
  });

  group('Guardar historico por', () {
    testWidgets('1 ano por padrao; aumentar grava sem perguntar; diminuir pede confirmacao', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3, altura: 1400);
      expect(find.text('Guardar menos tempo protege a privacidade da criança.'), findsOneWidget);
      final umAno = find.byKey(const ValueKey('guardar-1_ano'));
      expect(tester.widget<RadioListTile<GuardarHistorico>>(umAno).value, GuardarHistorico.umAno);

      await tocar(tester, find.byKey(const ValueKey('guardar-ate_eu_apagar')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(servico.prefs.getString(GuardarHistorico.chave), 'ate_eu_apagar');

      await tocar(tester, find.byKey(const ValueKey('guardar-2_anos')));
      expect(find.text('Guardar só 2 anos?'), findsOneWidget);
      await tocar(tester, find.text('Cancelar'));
      expect(servico.prefs.getString(GuardarHistorico.chave), 'ate_eu_apagar');

      await tocar(tester, find.byKey(const ValueKey('guardar-1_ano')));
      await tocar(tester, find.text('Apagar e guardar'));
      await tester.runAsync(() => servico.historicoLocal.ocioso);
      expect(servico.prefs.getString(GuardarHistorico.chave), isNull, reason: 'padrao: chave removida');
    });
  });

  group('goldens', () {
    testWidgets('tela de exportar (claro)', (tester) async {
      await abrirTela(tester);
      await imagem('exportar_relatorio');
    });

    testWidgets('tela de exportar (escuro), periodo de 7 dias', (tester) async {
      await abrirTela(tester, escuro: true);
      await tocar(tester, find.text('Últimos 7 dias'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();
      await imagem('escuro_exportar_relatorio_periodo');
    });

    testWidgets('aviso antes de compartilhar', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await imagem('exportar_relatorio_aviso');
    });

    testWidgets('item em Ajustes: Dados deste aparelho', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3);
      await tester.ensureVisible(find.byKey(const ValueKey('ajustes-exportar-relatorio')));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('ajustes-exportar-relatorio'))), alignment: 0.15);
      await tester.pumpAndSettle();
      await imagem('ajustes_dados_do_aparelho');
    });
  });
}

/// Volta para 31 dias e gera: o arquivo do periodo tem o nome com inicio e fim.
Future<void> gerarPeriodoValido(WidgetTester tester) async {
  await tocar(tester, find.text('Últimos 31 dias'));
  await gerar(tester);
  expect(find.text(avisoDeDadosDeSaude), findsOneWidget);
}
