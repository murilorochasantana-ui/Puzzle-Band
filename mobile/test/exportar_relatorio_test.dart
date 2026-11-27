// Tela "Exportar relatorio" (flutter test): gerar, os dois botoes ("Salvar
// no celular" e "Compartilhar") com o aviso de dados de saude antes de cada
// um, "Relatorio salvo" com "Abrir", cancelar a janela "Salvar como" sem erro
// (sistema falso), o limite de 31 dias, as entradas pelo Historico e pelos
// Ajustes, a opcao "Guardar historico por" e os goldens.
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
import 'apoio/sistema_falso.dart';

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

const _salvar = ValueKey('salvar-relatorio');
const _compartilhar = ValueKey('compartilhar-relatorio');

/// Toca em "Gerar relatorio" e espera o arquivo ficar pronto (banco e disco de
/// verdade, fora do relogio falso) ate os dois botoes aparecerem.
Future<void> gerar(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('gerar-relatorio')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('gerar-relatorio')));
  for (var i = 0; i < 100 && find.byKey(_salvar).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byKey(_salvar), findsOneWidget, reason: 'o arquivo deveria ficar pronto');
  await tester.pumpAndSettle();
}

/// Espera as chamadas ao sistema falso (fora do relogio falso) e redesenha.
Future<void> esperar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
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
  late DocumentosFalsos documentos;

  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  Future<ServicoFalso> abrirTela(WidgetTester tester, {bool escuro = false, double altura = 852}) async {
    pasta = pastaTemporaria();
    compartilhar = CompartilharFalso();
    documentos = DocumentosFalsos();
    final servico = await calmo();
    await mostrar(
      tester,
      servico,
      escuro: escuro,
      altura: altura,
      tela: ExportarRelatorioScreen(compartilhar: compartilhar.call, pasta: () async => pasta, documentos: documentos),
    );
    return servico;
  }

  group('exportar', () {
    testWidgets('padrao: hoje; gerar mostra "Relatorio pronto" com os dois botoes, sem aviso ainda', (tester) async {
      await abrirTela(tester);
      expect(find.text('Hoje, 5 de novembro de 2026'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('dia-seguinte'))).onPressed, isNull,
          reason: 'nao passa de hoje');
      expect(find.byKey(_salvar), findsNothing, reason: 'os botoes so aparecem depois de gerar');
      expect(find.byKey(_compartilhar), findsNothing);

      await gerar(tester);
      expect(find.text('Relatório pronto'), findsOneWidget);
      expect(find.text('puzzleband_relatorio_C01_2026-11-05.xlsx'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(_salvar)), isA<FilledButton>(), reason: 'salvar e o principal');
      expect(tester.widget<ButtonStyleButton>(find.byKey(_compartilhar)), isA<OutlinedButton>());
      expect(find.text(avisoDeDadosDeSaude), findsNothing);
      expect(documentos.salvos, isEmpty);
      expect(compartilhar.chamadas, isEmpty);
    });

    testWidgets('Salvar no celular: aviso antes; "Salvar como" com o nome e o tipo; "Relatorio salvo" e Abrir', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      expect(find.text(avisoDeDadosDeSaude), findsOneWidget);
      expect(find.text('Antes de salvar'), findsOneWidget);
      expect(documentos.salvos, isEmpty, reason: 'a janela do sistema so abre depois do aviso');

      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      final (caminho, nome, tipo, existia) = documentos.salvos.single;
      expect(nome, 'puzzleband_relatorio_C01_2026-11-05.xlsx');
      expect(tipo, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(caminho, endsWith(nome));
      expect(existia, isTrue);
      expect(find.text('Relatório salvo'), findsOneWidget);
      expect(compartilhar.chamadas, isEmpty);

      await tester.tap(find.text('Abrir'));
      await esperar(tester);
      expect(documentos.abertos, [DocumentosFalsos.uriSalva]);
      expect(find.text(semAppDePlanilhas), findsNothing);
      // o relatorio continua pronto: da para compartilhar tambem
      expect(find.byKey(_compartilhar), findsOneWidget);
    });

    testWidgets('Abrir sem app de planilhas: avisa em portugues', (tester) async {
      await abrirTela(tester);
      documentos.temAppDePlanilhas = false;
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      await tester.tap(find.text('Abrir'));
      await esperar(tester);
      expect(find.text(semAppDePlanilhas), findsOneWidget);
    });

    testWidgets('cancelar a janela "Salvar como": nada acontece, sem erro; da para tocar de novo', (tester) async {
      await abrirTela(tester);
      documentos.resultado = ResultadoDoSalvar.cancela;
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      expect(documentos.salvos, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Não foi possível'), findsNothing);
      expect(find.text('Relatório pronto'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(_salvar)).onPressed, isNotNull);

      // tocar de novo (como depois de a Activity ser recriada com a janela aberta)
      documentos.resultado = ResultadoDoSalvar.salva;
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      expect(documentos.salvos, hasLength(2));
      expect(find.text('Relatório salvo'), findsOneWidget);
    });

    testWidgets('erro ao salvar: mensagem em portugues e o relatorio continua pronto', (tester) async {
      await abrirTela(tester);
      documentos.resultado = ResultadoDoSalvar.erro;
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      expect(find.text('Não foi possível salvar o arquivo. Tente de novo.'), findsOneWidget);
      expect(find.text('Relatório salvo'), findsNothing);
      expect(find.byKey(_salvar), findsOneWidget);
    });

    testWidgets('Compartilhar: aviso antes; depois o menu do Android com o arquivo', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.byKey(_compartilhar));
      expect(find.text(avisoDeDadosDeSaude), findsOneWidget);
      expect(find.text('Antes de compartilhar'), findsOneWidget);
      expect(compartilhar.chamadas, isEmpty, reason: 'o menu de compartilhar so abre depois do aviso');

      await tocar(tester, find.widgetWithText(FilledButton, 'Compartilhar'));
      await esperar(tester);
      final (arquivo, assunto, existia) = compartilhar.chamadas.single;
      expect(arquivo.path, endsWith('puzzleband_relatorio_C01_2026-11-05.xlsx'));
      expect(existia, isTrue);
      expect(assunto, contains('5 de novembro de 2026'));
      expect(documentos.salvos, isEmpty);
      final bytes = (await tester.runAsync(arquivo.readAsBytes))!;
      expect(bytes.sublist(0, 2), [0x50, 0x4B], reason: 'um zip (.xlsx)');
    });

    testWidgets('cancelar o aviso (salvar ou compartilhar): nada acontece', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.text('Cancelar'));
      await tocar(tester, find.byKey(_compartilhar));
      await tocar(tester, find.text('Cancelar'));
      await esperar(tester);
      expect(documentos.salvos, isEmpty);
      expect(compartilhar.chamadas, isEmpty);
      expect(find.text('Relatório pronto'), findsOneWidget);
    });

    testWidgets('trocar o dia descarta o relatorio pronto (apaga o arquivo); sair da tela tambem', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      bool temXlsx() => pasta.listSync().whereType<File>().any((f) => f.path.endsWith('.xlsx'));
      expect(temXlsx(), isTrue);
      await tocar(tester, find.byKey(const ValueKey('dia-anterior')));
      expect(find.byKey(_salvar), findsNothing);
      expect(find.byKey(const ValueKey('gerar-relatorio')), findsOneWidget);
      expect(temXlsx(), isFalse);

      await gerar(tester);
      expect(temXlsx(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink()); // a tela sai
      expect(temXlsx(), isFalse);
    });

    testWidgets('periodo: ate 31 dias; mais que isso desliga o botao e explica', (tester) async {
      await abrirTela(tester, altura: 1000);
      await tocar(tester, find.text('Últimos 7 dias'));
      expect(find.text('De'), findsOneWidget);
      expect(find.text('Gerar relatório (7 dias)'), findsOneWidget);
      await tocar(tester, find.text('Últimos 31 dias'));
      expect(find.text('Gerar relatório (31 dias)'), findsOneWidget);
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

    testWidgets('relatorio pronto: os dois botoes', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tester.ensureVisible(find.byKey(_compartilhar));
      await tester.pumpAndSettle();
      await imagem('exportar_relatorio_pronto');
    });

    testWidgets('aviso antes de salvar', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await imagem('exportar_relatorio_aviso');
    });

    testWidgets('relatorio salvo (SnackBar com Abrir)', (tester) async {
      await abrirTela(tester);
      await gerar(tester);
      await tocar(tester, find.byKey(_salvar));
      await tocar(tester, find.widgetWithText(FilledButton, 'Salvar'));
      await esperar(tester);
      await imagem('exportar_relatorio_salvo');
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
  expect(find.text('puzzleband_relatorio_C01_2026-10-06_a_2026-11-05.xlsx'), findsOneWidget);
}
