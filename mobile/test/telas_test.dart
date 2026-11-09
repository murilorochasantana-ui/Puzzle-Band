// Testes de tela: o que o cuidador ve e consegue fazer, e as regras de
// acessibilidade (leitor de tela, alvos de toque, contraste, fonte ampliada,
// movimento). Os cenarios estao em test/apoio/cenarios.dart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/main.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/models/resumo.dart';
import 'package:puzzleband/models/sinais.dart';
import 'package:puzzleband/screens/graficos_screen.dart';
import 'package:puzzleband/screens/configurar_alertas_screen.dart';
import 'package:puzzleband/services/app_scope.dart';
import 'package:puzzleband/services/mqtt_service.dart';
import 'package:puzzleband/services/notification_service.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/theme/app_theme.dart';
import 'package:puzzleband/utils/formatters.dart';
import 'package:puzzleband/utils/relogio.dart';
import 'package:puzzleband/widgets/calendario_crises.dart';
import 'package:puzzleband/widgets/cartao_episodio.dart';
import 'package:puzzleband/widgets/cartao_episodio_ativo.dart';
import 'package:puzzleband/widgets/cartao_episodio_resumido.dart';
import 'package:puzzleband/widgets/faixa_estado.dart';
import 'package:puzzleband/widgets/gatilho_simples.dart';
import 'package:puzzleband/widgets/painel_do_dia.dart';
import 'package:puzzleband/widgets/selo_avaliacao.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';

/// MqttService de verdade (historico, ordem de reset, limpeza), so com o
/// estado ao vivo fixo: o que as telas mostram vem da lista real.
class ServicoComLimpeza extends MqttService {
  ServicoComLimpeza({required super.prefs, required this.estadoFixo})
      : super(config: configSemSenha, notificacoes: NotificationService());

  final EstadoAtual estadoFixo;

  /// Faz o papel do aoApagarDados (PreferenciasLocais.apagarDados).
  ApagarDadosLocais? limpezaExtra;

  @override
  BrokerStatus get brokerStatus => BrokerStatus.conectado;
  @override
  String? get ultimoErro => null;
  @override
  Presenca get pulseira => Presenca.online;
  @override
  EstadoAtual? get estado => estadoFixo;
  @override
  bool get estadoAoVivo => true;

  @override
  Future<void> apagarDadosLocais({required bool manterPreferencias}) async {
    await super.apagarDadosLocais(manterPreferencias: manterPreferencias);
    await limpezaExtra?.call(manterPreferencias: manterPreferencias);
  }
}

/// Historico como a pulseira publica (origem "pulseira").
String mensagemDaPulseira(List<Episodio> episodios) =>
    jsonEncode({'origem': 'pulseira', 'episodios': [for (final e in episodios) e.toJson()]});

/// Rola ate [alvo] e toca nele (o que fica abaixo da tela nao recebe toque).
Future<void> tocarVisivel(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.pumpAndSettle();
  await tester.tap(alvo);
  await tester.pumpAndSettle();
}

/// Abre o painel "Hoje" pelo rotulo do botao.
Future<void> abrirPainel(WidgetTester tester, String rotulo) => tocarVisivel(tester, find.text(rotulo));

/// O mesmo estado ao vivo, com outro episodio em andamento.
EstadoAtual comEpisodio(EstadoAtual e, EpisodioAtivo episodio) => EstadoAtual(
      timestamp: e.timestamp,
      fonte: e.fonte,
      nivel: e.nivel,
      probabilidade: e.probabilidade,
      leituras: e.leituras,
      mediaBpm5min: e.mediaBpm5min,
      gatilho: e.gatilho,
      episodio: episodio,
    );

void main() {
  setUpAll(carregarFontes);
  setUp(() => relogio = () => agoraFixo);
  tearDown(() => relogio = DateTime.now);

  group('Início', () {
    testWidgets('leitor de tela: estado, BPM e gatilho em nós próprios', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await possivelCrise());

      expect(find.bySemanticsLabel('Estado da criança: Possível crise'), findsOneWidget);
      expect(find.bySemanticsLabel('Batimentos: 128 bpm'), findsOneWidget);
      expect(find.bySemanticsLabel('Ao vivo. Média de 5 minutos: 96 bpm.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Provável gatilho: barulho\. Provável gatilho: ruído')), findsOneWidget);

      // So o nivel e anunciado sozinho (liveRegion); o BPM, que muda 1x/s, nao.
      final nivel = tester.getSemantics(find.bySemanticsLabel('Estado da criança: Possível crise'));
      expect(nivel.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      final bpm = tester.getSemantics(find.bySemanticsLabel('Batimentos: 128 bpm'));
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

    testWidgets('BPM: grupo centrado, coração a 8 dp do número; divisória e "Ao vivo" fixos com 9, 90, 190 e "—"',
        (tester) async {
      final semantica = tester.ensureSemantics();
      for (final escala in [1.0, 1.3]) {
        (Offset, Offset?, Size)? referencia;
        for (final bpm in [9.0, 90.0, 190.0, null]) {
          await mostrar(tester, await comBpm(atencao(), bpm), escala: escala);
          expect(tester.takeException(), isNull);
          final faixa = find.byType(FaixaEstado);
          final numero = find.byKey(chaveNumeroBpm);
          expect(tester.widget<Text>(numero).data, bpm == null ? '—' : '${bpm.round()}');
          final caso = 'BPM $bpm em ${escala}x';

          // Coração, número e "bpm" juntos: 8 dp do coração ao primeiro
          // algarismo; "bpm" logo depois do número
          final coracao = tester.getRect(find.byKey(chaveCoracaoBpm));
          final rNumero = tester.getRect(numero);
          final unidade = tester.getRect(find.descendant(of: faixa, matching: find.text('bpm')));
          expect(rNumero.left - coracao.right, moreOrLessEquals(FaixaBpm.espacoCoracao, epsilon: 0.01), reason: caso);
          expect(unidade.left - rNumero.right, moreOrLessEquals(FaixaBpm.espacoUnidade, epsilon: 0.01), reason: caso);

          // O coração fica centrado na altura dos algarismos
          final pintor = TextPainter(
            text: TextSpan(text: '0', style: tester.widget<Text>(numero).style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(escala),
          )..layout();
          final linhaDeBase = rNumero.top + pintor.computeDistanceToActualBaseline(TextBaseline.alphabetic);
          final algarismos = TextScaler.linear(escala).scale(pintor.text!.style!.fontSize!) * Tipografia.alturaDosAlgarismos;
          pintor.dispose();
          expect(coracao.center.dy, moreOrLessEquals(linhaDeBase - algarismos / 2, epsilon: 0.5), reason: caso);
          expect(coracao.height * FaixaBpm.coracaoAltura / algarismos, moreOrLessEquals(0.55, epsilon: 0.01));

          // O grupo fica no centro da área à esquerda (1 dp de tolerância)
          final area = tester.getRect(find.byKey(chaveAreaBpm));
          final grupo = tester.getRect(find.byKey(chaveGrupoBpm));
          expect(grupo.center.dx, moreOrLessEquals(area.center.dx, epsilon: 1), reason: caso);
          expect(grupo.center.dy, moreOrLessEquals(area.center.dy, epsilon: 1), reason: caso);

          // Divisória e "Ao vivo" não se mexem; a faixa não muda de altura
          final divisoria = find.byKey(chaveDivisoriaBpm);
          final medida = (
            tester.getTopLeft(find.descendant(of: faixa, matching: find.text('Ao vivo'))),
            divisoria.evaluate().isEmpty ? null : tester.getTopLeft(divisoria),
            tester.getSize(faixa),
          );
          if (referencia == null) {
            referencia = medida;
          } else {
            expect(medida.$1, referencia.$1, reason: '"Ao vivo" com $caso');
            expect(medida.$2, referencia.$2, reason: 'divisória com $caso');
            if (escala == 1.0) expect(medida.$3, referencia.$3, reason: 'altura da faixa com $caso');
          }
          if (divisoria.evaluate().isNotEmpty) {
            // A coluna "Ao vivo" fica centrada na mesma altura do grupo
            final direita = tester.getRect(find.bySemanticsLabel(RegExp(r'^Ao vivo\.')).first);
            expect(direita.center.dy, moreOrLessEquals(grupo.center.dy, epsilon: 1), reason: caso);
          }
        }
        // 393 dp: lado a lado (com divisória); 1,3x: "Ao vivo" desce
        expect(referencia!.$2 != null, escala == 1.0);
      }
      semantica.dispose();
    });

    testWidgets('BPM: algarismos de mesma largura, coração neutro e "Batimentos: 79 bpm" para o leitor de tela',
        (tester) async {
      final semantica = tester.ensureSemantics();
      for (final escuro in [false, true]) {
        await mostrar(tester, await comBpm(atencao(), 79), escuro: escuro);
        final numero = tester.widget<Text>(find.byKey(chaveNumeroBpm));
        expect(numero.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
        final coracao = tester.widget<Icon>(find.descendant(of: find.byKey(chaveCoracaoBpm), matching: find.byType(Icon)));
        final cores = escuro ? CoresApp.escuro : CoresApp.claro;
        expect(coracao.color, cores.tintaSuave, reason: 'neutro: vermelho é cor de risco');
        expect(find.bySemanticsLabel('Batimentos: 79 bpm'), findsOneWidget);
      }
      semantica.dispose();
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
      expect(find.text('Ciente às 15:00'), findsOneWidget);
    });

    testWidgets('"Estou ciente": a confirmação some depois de 5 s e o botão não volta para o mesmo episódio',
        (tester) async {
      final semantica = tester.ensureSemantics();
      final servico = await possivelCrise();
      await mostrar(tester, servico);

      await tester.tap(find.text('Estou ciente'));
      await tester.pump();
      expect(find.text('Ciente às 15:00'), findsOneWidget);
      final aviso = tester.getSemantics(find.bySemanticsLabel('Aviso enviado. Ciente às 15:00.'));
      expect(aviso.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Ciente às 15:00'), findsNothing);
      expect(find.text('Estou ciente'), findsNothing);
      expect(servico.cientes.keys, ['ep_5']);
      // O cartao do episodio continua (so a confirmacao saiu)
      expect(find.text('Episódio em andamento desde 14:58'), findsOneWidget);

      // Episodio novo: o botao aparece de novo
      servico.estadoAtual = comEpisodio(
        servico.estadoAtual!,
        EpisodioAtivo(id: 'ep_6', inicio: DateTime(2026, 11, 5, 15, 10), nivelMaximo: NivelRisco.altoRisco),
      );
      servico.notifyListeners();
      await tester.pump();
      expect(find.text('Estou ciente'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('"Estou ciente" com animação: a confirmação sai com um fade curto', (tester) async {
      await mostrar(tester, await possivelCrise(), reduzirMovimento: false);
      await tester.tap(find.text('Estou ciente'));
      await tester.pumpAndSettle();
      expect(find.text('Ciente às 15:00'), findsOneWidget);
      await tester.pump(CartaoEpisodioAtivo.tempoDaConfirmacao);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Ciente às 15:00'), findsOneWidget); // no meio do fade
      await tester.pumpAndSettle();
      expect(find.text('Ciente às 15:00'), findsNothing);
    });

    testWidgets('"Estou ciente": sair da tela antes dos 5 s cancela o timer', (tester) async {
      await mostrar(tester, await possivelCrise());
      await tester.tap(find.text('Estou ciente'));
      await tester.pump();
      await tester.tap(find.text('Gráficos'));
      await tester.pumpAndSettle();
      // Se o timer nao fosse cancelado no dispose, o teste falharia aqui com
      // "A Timer is still pending even after the widget tree was disposed".
      expect(find.byType(CartaoEpisodioAtivo), findsNothing);
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

    testWidgets('sem episódio agora: o cartão resume o último episódio real e abre o detalhe', (tester) async {
      await mostrar(tester, await calmo());
      expect(find.text('Nenhum episódio agora'), findsOneWidget);
      expect(find.text('Último episódio: hoje às 14:32.'), findsOneWidget);
      await tocarVisivel(tester, find.text('Nenhum episódio agora'));
      expect(find.text('Episódio de hoje às 14:32'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      await mostrar(tester, await semDadosAinda());
      expect(find.text('Nenhum episódio registrado ainda.'), findsOneWidget);
    });

    testWidgets('probabilidade e fonte numa linha própria', (tester) async {
      await mostrar(tester, await atencao());
      expect(find.text('Probabilidade estimada: 58%'), findsOneWidget);
      expect(find.text('Fonte: pulseira'), findsOneWidget);
    });
  });

  group('Início: painel "Hoje"', () {
    testWidgets('abre e fecha no lugar, com estado para o leitor de tela', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo());
      expect(find.text('Das 14:32 às 14:33'), findsNothing);
      final botao = find.bySemanticsLabel('Hoje: 2 episódios');
      expect(tester.getSemantics(botao), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));

      await abrirPainel(tester, 'Hoje: 2 episódios');
      expect(find.text('Das 14:32 às 14:33'), findsOneWidget);
      expect(tester.getSemantics(botao), isSemantics(hasExpandedState: true, isExpanded: true));

      await tocarVisivel(tester, find.text('Hoje: 2 episódios'));
      expect(find.text('Das 14:32 às 14:33'), findsNothing);
      expect(tester.getSemantics(botao), isSemantics(hasExpandedState: true, isExpanded: false));
      semantica.dispose();
    });

    testWidgets('lista todos os episódios de hoje, do mais recente para o mais antigo, com o relatório',
        (tester) async {
      await mostrar(tester, await calmo(), altura: 1600);
      await abrirPainel(tester, 'Hoje: 2 episódios');
      final painel = find.byType(PainelDoDia);
      Finder noPainel(Finder f) => find.descendant(of: painel, matching: f);

      final recente = noPainel(find.text('Das 14:32 às 14:33'));
      final antigo = noPainel(find.text('Das 09:10 às 09:11'));
      expect(recente, findsOneWidget);
      expect(antigo, findsOneWidget);
      expect(tester.getTopLeft(recente).dy, lessThan(tester.getTopLeft(antigo).dy));
      // O de ontem nao entra
      expect(noPainel(find.textContaining('18:05')), findsNothing);

      // Nivel maximo com icone + texto
      expect(noPainel(find.text('Possível crise')), findsOneWidget);
      expect(noPainel(find.byIcon(Icons.error_rounded)), findsOneWidget);
      expect(noPainel(find.text('Atenção')), findsOneWidget);
      expect(noPainel(find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
      // Duracao, probabilidade maxima, gatilho (simples + tecnico) e avaliacao
      expect(noPainel(find.text('Duração: 1 min 57 s')), findsOneWidget);
      expect(noPainel(find.text('Probabilidade máxima: 86%')), findsOneWidget);
      expect(noPainel(find.text('Provável gatilho: barulho')), findsOneWidget);
      expect(noPainel(find.text(gatilhoRuido.texto)), findsOneWidget);
      expect(noPainel(find.text('Avaliação pendente.')), findsOneWidget);
      expect(noPainel(find.text('Gatilho confirmado por você às 09:20.')), findsOneWidget);
    });

    testWidgets('episódio em andamento aparece como "em andamento"', (tester) async {
      final servico = await possivelCrise();
      servico.episodios = [
        Episodio(id: 'ep_5', inicio: DateTime(2026, 11, 5, 14, 58), nivelMaximo: NivelRisco.altoRisco),
        ...servico.episodios,
      ];
      await mostrar(tester, servico, altura: 2000);
      await abrirPainel(tester, 'Hoje: 3 episódios');
      expect(find.text('Desde 14:58, em andamento'), findsOneWidget);
    });

    testWidgets('sem episódios hoje: "Hoje: nenhum episódio" e estado vazio', (tester) async {
      await mostrar(tester, await semEpisodiosHoje());
      await abrirPainel(tester, 'Hoje: nenhum episódio');
      expect(find.text('Nenhum episódio hoje'), findsOneWidget);
      expect(find.text('Adicionar lembrete do dia'), findsOneWidget);
    });

    testWidgets('tocar num episódio abre o detalhe com "Confirmar gatilho" e "Descartar"', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico);
      await abrirPainel(tester, 'Hoje: 2 episódios');
      await tocarVisivel(tester, find.text('Das 14:32 às 14:33'));

      expect(find.text('Episódio de hoje às 14:32'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
      await tocarVisivel(tester, find.text('Confirmar gatilho'));
      expect(servico.avaliacoes.single, ('ep_4', Avaliacao.confirmado, ''));
      expect(find.text('Gatilho confirmado por você às 15:00.'), findsOneWidget);

      // Voltar: o painel continua aberto e ja mostra a avaliacao
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(PainelDoDia), matching: find.text('Gatilho confirmado por você às 15:00.')),
        findsOneWidget,
      );
    });
  });

  group('Lembretes (só no celular)', () {
    testWidgets('lembrete do dia: salva, mostra no painel, edita e apaga', (tester) async {
      final servico = await calmo();
      final preferencias = preferenciasDe(servico);
      final chave = PreferenciasLocais.chaveDia(agoraFixo);
      await mostrar(tester, servico, preferencias: preferencias);
      await abrirPainel(tester, 'Hoje: 2 episódios');

      await tocarVisivel(tester, find.text('Adicionar lembrete do dia'));
      await tester.enterText(find.byType(TextField), 'Levar o abafador');
      await tester.tap(find.text('Salvar lembrete'));
      await tester.pumpAndSettle();

      expect(find.text('Levar o abafador'), findsOneWidget);
      expect(find.text('Lembrete salvo neste celular.'), findsOneWidget);
      expect(preferencias.lembrete(chave)?.texto, 'Levar o abafador');
      expect(servico.prefs.getString('lembretes_v1'), contains('Levar o abafador'));
      // Nada vai para o MQTT
      expect(servico.cientes, isEmpty);
      expect(servico.avaliacoes, isEmpty);

      await tocarVisivel(tester, find.text('Editar'));
      expect(find.text('Levar o abafador'), findsWidgets); // campo ja preenchido
      await tester.enterText(find.byType(TextField), 'Levar o abafador e a garrafa');
      await tester.tap(find.text('Salvar lembrete'));
      await tester.pumpAndSettle();
      expect(find.text('Levar o abafador e a garrafa'), findsOneWidget);

      await tocarVisivel(tester, find.text('Editar'));
      await tester.tap(find.text('Apagar lembrete'));
      await tester.pumpAndSettle();
      expect(find.text('Lembrete apagado.'), findsOneWidget);
      expect(find.text('Adicionar lembrete do dia'), findsOneWidget);
      expect(preferencias.lembrete(chave), isNull);
    });

    testWidgets('lembrete do episódio: salvo no detalhe, aparece no detalhe e no painel', (tester) async {
      final servico = await calmo();
      final preferencias = preferenciasDe(servico);
      await mostrar(tester, servico, preferencias: preferencias);
      await abrirPainel(tester, 'Hoje: 2 episódios');
      await tocarVisivel(tester, find.text('Das 14:32 às 14:33'));

      await tocarVisivel(tester, find.text('Adicionar lembrete'));
      await tester.enterText(find.byType(TextField).last, 'Sinal do recreio');
      await tester.tap(find.text('Salvar lembrete'));
      await tester.pumpAndSettle();
      expect(find.text('Lembrete: Sinal do recreio'), findsOneWidget);
      expect(preferencias.lembrete(PreferenciasLocais.chaveEpisodio('ep_4'))?.texto, 'Sinal do recreio');

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Lembrete: Sinal do recreio'), findsOneWidget);

      // Apagar no detalhe
      await tocarVisivel(tester, find.text('Das 14:32 às 14:33'));
      await tocarVisivel(tester, find.text('Apagar lembrete'));
      expect(find.text('Lembrete: Sinal do recreio'), findsNothing);
      expect(find.text('Adicionar lembrete'), findsOneWidget);
    });

    testWidgets('aviso do lembrete: agenda no horário, cancela ao tirar ou apagar, e fica salvo', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final aviso = AvisoFalso();
      final preferencias = PreferenciasLocais(prefs: prefs, nomePadrao: 'C01', aviso: aviso);
      final chave = PreferenciasLocais.chaveEpisodio('ep_4');
      final id = PreferenciasLocais.idDoAviso(chave);
      final as17 = DateTime(2026, 11, 5, 17, 0);

      expect(await preferencias.salvarLembrete(chave, 'Dar água', avisarEm: as17, tituloDoAviso: 'Lembrete'),
          ResultadoLembrete.salvoComAviso);
      expect(aviso.agendados[id], (as17, 'Lembrete', 'Dar água'));

      // Recarregado do shared_preferences (app reaberto)
      final reaberto = PreferenciasLocais(prefs: prefs, nomePadrao: 'C01', aviso: aviso);
      expect(reaberto.lembrete(chave)?.texto, 'Dar água');
      expect(reaberto.lembrete(chave)?.avisarEm, as17);

      // Sem horario: o aviso anterior e cancelado
      expect(await preferencias.salvarLembrete(chave, 'Dar água', tituloDoAviso: 'Lembrete'), ResultadoLembrete.salvo);
      expect(aviso.agendados, isEmpty);

      // Horario que ja passou nao agenda
      await preferencias.salvarLembrete(chave, 'Dar água', avisarEm: DateTime(2026, 11, 5, 14, 0), tituloDoAviso: 'L');
      expect(aviso.agendados, isEmpty);

      // Aparelho que nao agenda: o lembrete fica salvo, sem aviso
      aviso.funciona = false;
      expect(await preferencias.salvarLembrete(chave, 'Dar água', avisarEm: as17, tituloDoAviso: 'L'),
          ResultadoLembrete.avisoFalhou);
      expect(preferencias.lembrete(chave)?.avisarEm, isNull);

      // Apagar cancela o aviso
      aviso.funciona = true;
      await preferencias.salvarLembrete(chave, 'Dar água', avisarEm: as17, tituloDoAviso: 'L');
      await preferencias.apagarLembrete(chave);
      expect(aviso.agendados, isEmpty);
      expect(preferencias.lembrete(chave), isNull);

      // Texto vazio apaga; texto longo e cortado em 120
      expect(await preferencias.salvarLembrete(chave, '   ', tituloDoAviso: 'L'), ResultadoLembrete.apagado);
      await preferencias.salvarLembrete(chave, 'x' * 300, tituloDoAviso: 'L');
      expect(preferencias.lembrete(chave)?.texto.length, PreferenciasLocais.maxLembrete);
    });
  });

  group('Nome da criança', () {
    testWidgets('Ajustes salva o nome e o Início mostra; vazio volta ao CHILD_ID', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3, altura: 1100);
      final campo = find.widgetWithText(TextField, 'Nome da criança');
      await tester.enterText(campo, '  Lia  ');
      await tester.pumpAndSettle();
      expect(servico.prefs.getString('nome_crianca'), 'Lia');

      await tester.tap(find.text('Início'));
      await tester.pumpAndSettle();
      expect(find.text('Lia'), findsOneWidget);
      expect(find.text('PUZZLE BAND'), findsNothing);

      await tester.tap(find.text('Ajustes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Nome da criança'), '');
      await tester.tap(find.text('Início'));
      await tester.pumpAndSettle();
      expect(find.text('C01'), findsOneWidget);
      expect(servico.prefs.getString('nome_crianca'), isNull);
    });

    testWidgets('as outras telas continuam com o logotipo', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      expect(find.text('PUZZLE BAND'), findsOneWidget);
    });
  });

  group('Início: conexão e movimento', () {

    testWidgets('estados da conexão dizem o que aconteceu e o que fazer', (tester) async {
      await mostrar(tester, await conectando());
      expect(find.text('Conectando…'), findsOneWidget);

      await mostrar(tester, await semConexao());
      expect(find.text('Sem conexão'), findsOneWidget);
      expect(find.text('Último dado recebido às 14:52:10.'), findsOneWidget);

      await mostrar(tester, await painelEPulseiraOffline());
      expect(find.text('Sem dados ao vivo'), findsOneWidget);
      expect(find.textContaining('A pulseira parou de enviar às 14:40'), findsOneWidget);
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

  group('Histórico: calendário', () {
    DiaDoCalendario dia(WidgetTester tester, int d) => tester.widget<DiaDoCalendario>(diaDoCalendario(d));
    BoxDecoration pintura(WidgetTester tester, int d) =>
        tester.widget<Ink>(find.descendant(of: diaDoCalendario(d), matching: find.byType(Ink))).decoration! as BoxDecoration;

    testWidgets('cor só pelas crises confirmadas: 0, 3 e 7 → sem cor, amarelo e vermelho', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      expect(find.text('Novembro de 2026'), findsOneWidget);
      // 04/11: só um descartado (0 confirmadas); 01/11: 3; 03/11: 7
      expect(dia(tester, 4).cor, CorDoDia.nenhuma);
      expect(dia(tester, 1).cor, CorDoDia.amarelo);
      expect(dia(tester, 3).cor, CorDoDia.vermelho);
      expect(dia(tester, 10).cor, CorDoDia.nenhuma);
      expect(pintura(tester, 4).color, isNull);
      expect(pintura(tester, 1).color, CoresDados.claro.diaAmarelo.fundo);
      expect(pintura(tester, 3).color, CoresDados.claro.diaVermelho.fundo);
      // A cor nunca vem sozinha: a quantidade aparece no dia
      expect(find.descendant(of: diaDoCalendario(3), matching: find.text('7')), findsOneWidget);
      expect(find.descendant(of: diaDoCalendario(1), matching: find.text('3')), findsOneWidget);
    });

    testWidgets('leitor de tela: cada dia diz quantas crises e quantas aguardam confirmação', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo(), aba: 2);
      expect(find.bySemanticsLabel('3 de novembro: 7 crises confirmadas'), findsOneWidget);
      expect(find.bySemanticsLabel('2 de novembro: 1 possível crise aguardando confirmação'), findsOneWidget);
      expect(find.bySemanticsLabel('4 de novembro: nenhuma crise'), findsOneWidget);
      expect(
        find.bySemanticsLabel('5 de novembro, hoje: 1 crise confirmada e 1 possível crise aguardando confirmação'),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('bolinha azul só no dia que tem apenas possíveis crises; hoje tem contorno', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      Finder bolinha(int d) => find.descendant(of: diaDoCalendario(d), matching: find.byKey(const ValueKey('bolinha-azul')));
      expect(bolinha(2), findsOneWidget, reason: '02/11: só pendente');
      expect(bolinha(5), findsNothing, reason: '05/11: tem confirmada');
      expect(bolinha(3), findsNothing);
      expect(bolinha(4), findsNothing, reason: 'descartado não conta');
      expect(dia(tester, 2).cor, CorDoDia.nenhuma, reason: 'pendente não entra na cor');
      expect(pintura(tester, 5).border, isNotNull, reason: 'hoje');
      expect(pintura(tester, 6).border, isNull);
    });

    testWidgets('descartado não tem efeito no calendário nem no gráfico de 7 dias', (tester) async {
      final semantica = tester.ensureSemantics();
      final servico = await calmo();
      await mostrar(tester, servico, aba: 2, altura: 1400);
      // Descarta a única possível crise de 02/11
      await tocarNoMeio(tester, diaDoCalendario(2));
      await tocarNoMeio(tester, cartao('ep_1'));
      await tocarNoMeio(tester, find.text('Descartar'));
      expect(servico.avaliacoes.single, ('ep_1', Avaliacao.descartado, ''));
      expect(dia(tester, 2).bolinha, isFalse);
      expect(dia(tester, 2).cor, CorDoDia.nenhuma);
      expect(find.bySemanticsLabel('2 de novembro: nenhuma crise'), findsOneWidget);
      // O episódio continua na lista, com o selo "Descartado"
      expect(find.descendant(of: cartao('ep_1'), matching: find.text('Descartado')), findsWidgets);

      await tester.tap(find.text('Gráficos'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico de crises por dia: .*Seg, nenhuma; Ter, 7 crises confirmadas; Qua, nenhuma;')),
          findsOneWidget);
      expect(find.textContaining('Nos últimos 7 dias: 11 crises confirmadas e 1 aguardando sua confirmação.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('meses: volta até o primeiro mês com episódio e não passa do mês atual', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      final anterior = find.byTooltip('Mês anterior');
      final proximo = find.byTooltip('Próximo mês');
      expect(tester.widget<IconButton>(find.ancestor(of: proximo, matching: find.byType(IconButton))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.ancestor(of: anterior, matching: find.byType(IconButton))).onPressed, isNull,
          reason: 'todos os episódios são de novembro');
      await tester.tap(find.byTooltip('Recolher calendário'));
      await tester.pumpAndSettle();
      expect(diaDoCalendario(3), findsNothing);
      expect(find.text('Em novembro: 11 crises confirmadas e 2 aguardando sua confirmação.'), findsOneWidget);
      await tester.tap(find.byTooltip('Mostrar calendário'));
      await tester.pumpAndSettle();
      expect(diaDoCalendario(3), findsOneWidget);
    });
  });

  group('Histórico: lista por dia', () {
    testWidgets('separada por dia, do mais recente ao mais antigo, com o número de episódios', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, altura: 4000);
      final cabecalhos = ['Hoje', 'Ontem', 'Ter, 3 de nov.', 'Seg, 2 de nov.', 'Dom, 1 de nov.'];
      final ys = [for (final c in cabecalhos) tester.getTopLeft(find.text(c)).dy];
      expect(ys, [...ys]..sort(), reason: 'ordem dos dias');
      expect(find.text('7 episódios'), findsOneWidget);
      expect(find.text('2 episódios'), findsOneWidget);
      // Todos os 14 episódios aparecem, inclusive o descartado
      expect(find.byType(CartaoEpisodioResumido), findsNWidgets(14));
      expect(tester.getTopLeft(cartao('ep_4')).dy, lessThan(tester.getTopLeft(cartao('ep_3')).dy));
    });

    testWidgets('cartão resumido: horário, nível, duração, gatilho e avaliação', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo(), aba: 2, altura: 1600);
      Finder no(String id, String texto) => find.descendant(of: cartao(id), matching: find.text(texto));
      expect(no('ep_4', '14:32–14:33'), findsOneWidget);
      expect(no('ep_4', 'Possível crise'), findsOneWidget); // nível do modelo
      expect(no('ep_4', '1 min 57 s'), findsOneWidget);
      expect(no('ep_4', 'Provável gatilho: barulho'), findsOneWidget);
      expect(no('ep_4', SeloAvaliacao.textoPendente), findsOneWidget);
      expect(no('ep_3', 'Confirmado'), findsOneWidget);
      expect(no('ep_2', 'Descartado'), findsOneWidget);
      // Resumido: sem botões nem texto técnico
      expect(find.text('Confirmar gatilho'), findsNothing);
      expect(find.textContaining('45 → 88 dB'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Das 14:32 às 14:33\. Nível: Possível crise\. Duração: 1 min 57 s\. '
            r'Provável gatilho: barulho\. Avaliação: Possível crise aguardando sua confirmação\.$')),
        findsOneWidget,
      );
      semantica.dispose();
    });

    testWidgets('cartão expande e recolhe no lugar; só um aberto por vez', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo(), aba: 2, altura: 1600);
      await tocarNoMeio(tester, cartao('ep_3'));
      expect(find.text('Confirmado'), findsNWidgets(2), reason: 'selo + botão escolhido');
      expect(find.text('Descartar'), findsOneWidget);
      expect(find.text(AvaliacaoEpisodio.explicacao), findsOneWidget);
      expect(find.text('Probabilidade máxima: 61%.'), findsOneWidget);
      expect(find.textContaining('luminosidade (300 → 1150 lux'), findsOneWidget);
      expect(find.text('Observação: A luz do refeitório piscou antes.'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Das 09:10'))),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));

      // Abrir outro fecha o primeiro
      await tocarNoMeio(tester, cartao('ep_4'));
      expect(find.text('Observação: A luz do refeitório piscou antes.'), findsNothing);
      expect(find.text('Alerta visto pelo cuidador às 14:33.'), findsOneWidget);
      expect(find.text(AvaliacaoEpisodio.explicacao), findsOneWidget);

      // Tocar de novo recolhe
      await tocarNoMeio(tester, find.text('Provável gatilho: barulho').first);
      expect(find.text(AvaliacaoEpisodio.explicacao), findsNothing);
      semantica.dispose();
    });

    testWidgets('"Possível crise · a confirmar" abre o cartão já nos botões', (tester) async {
      await mostrar(tester, await calmo(), aba: 2);
      await tocarNoMeio(tester, find.descendant(of: cartao('ep_4'), matching: find.text(SeloAvaliacao.textoPendente)));
      final botao = find.text('Confirmar gatilho');
      expect(botao, findsOneWidget);
      final limite = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(tester.getCenter(botao).dy, inInclusiveRange(0, limite), reason: 'o botão ficou visível');
      expect(tester.getBottomLeft(find.text('Descartar')).dy, lessThanOrEqualTo(limite));
    });

    testWidgets('confirmar gatilho: envia com a observação e o botão vira "Confirmado"', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 2, altura: 1600);
      await tocarNoMeio(tester, cartao('ep_4'));
      await tocarNoMeio(tester, find.text('Adicionar observação'));
      await tester.enterText(find.byType(TextField).first, 'Sirene da escola');
      await tocarNoMeio(tester, find.text('Confirmar gatilho'));

      expect(servico.avaliacoes.single, ('ep_4', Avaliacao.confirmado, 'Sirene da escola'));
      expect(find.text('Gatilho confirmado por você às 15:00.'), findsOneWidget);
      expect(find.text('Gatilho confirmado e enviado à pulseira.'), findsOneWidget);
      expect(find.text('Observação: Sirene da escola'), findsOneWidget);
      expect(find.descendant(of: cartao('ep_4'), matching: find.text('Confirmado')), findsNWidgets(2));
    });

    testWidgets('descartar: botão "Descartado" vermelho, selo no resumo, e dá para confirmar depois', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 2, altura: 1600);
      await tocarNoMeio(tester, cartao('ep_4'));
      await tocarNoMeio(tester, find.text('Descartar'));
      expect(servico.avaliacoes.last, ('ep_4', Avaliacao.descartado, ''));
      expect(find.text('Indicação descartada e enviada à pulseira.'), findsOneWidget);

      final botao = find.ancestor(of: find.text('Descartado'), matching: find.byWidgetPredicate((w) => w is FilledButton));
      expect(botao, findsOneWidget);
      final fundo = tester.widget<Material>(find.descendant(of: botao, matching: find.byType(Material)).first).color;
      expect(fundo, CoresDados.claro.descartado.fundo);
      expect(find.descendant(of: botao, matching: find.byIcon(Icons.block_rounded)), findsOneWidget);
      expect(find.descendant(of: find.byType(SeloAvaliacao), matching: find.text('Descartado')), findsWidgets);
      // Mudou de ideia: confirma e a avaliação é reenviada
      await tocarNoMeio(tester, find.text('Confirmar gatilho'));
      expect(servico.avaliacoes.last, ('ep_4', Avaliacao.confirmado, ''));
      expect(find.text('Descartar'), findsOneWidget);
    });

    testWidgets('descartar sem conexão avisa que não foi enviado', (tester) async {
      final servico = (await calmo())..envioFunciona = false;
      await mostrar(tester, servico, aba: 2, altura: 1600);
      await tocarNoMeio(tester, cartao('ep_4'));
      await tocarNoMeio(tester, find.text('Descartar'));
      expect(find.textContaining('a avaliação não foi enviada'), findsOneWidget);
      expect(find.text('Possível crise aguardando sua confirmação.'), findsOneWidget);
    });

    testWidgets('filtro por dia: tocar num dia mostra só ele; "Ver todos" limpa', (tester) async {
      await mostrar(tester, await calmo(), aba: 2, altura: 4000);
      await tocarNoMeio(tester, diaDoCalendario(3));
      expect(find.text('Mostrando só 3 de novembro.'), findsOneWidget);
      expect(find.byType(CartaoEpisodioResumido), findsNWidgets(7));
      expect(find.text('Hoje'), findsNothing);
      expect(tester.widget<DiaDoCalendario>(diaDoCalendario(3)).escolhido, isTrue);

      // Dia sem episódios
      await tocarNoMeio(tester, diaDoCalendario(10));
      expect(find.text('Nenhum episódio em 10 de novembro'), findsOneWidget);
      expect(find.byType(CartaoEpisodioResumido), findsNothing);

      await tocarNoMeio(tester, find.text('Ver todos'));
      expect(find.text('Mostrando só 10 de novembro.'), findsNothing);
      expect(find.byType(CartaoEpisodioResumido), findsNWidgets(14));
    });

    testWidgets('vazio e sem conexão têm mensagem própria', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 2);
      expect(find.text('Nenhum episódio ainda'), findsOneWidget);
      expect(find.byType(CalendarioCrises), findsNothing);

      await mostrar(tester, await semConexao(), aba: 2);
      expect(find.text('Sem conexão: mostrando a última cópia salva, de 05/11 14:50.'), findsOneWidget);
      expect(find.byType(CalendarioCrises), findsOneWidget);
    });
  });

  group('Gráficos', () {
    testWidgets('seletor troca a série, o eixo, a cor e o resumo', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await possivelCrise(), aba: 1);
      SfCartesianChart grafico() =>
          tester.widget<SfCartesianChart>(find.descendant(of: find.byType(GraficoSinais), matching: find.byType(SfCartesianChart)));
      ChoiceChip chip(Metrica m) => tester.widget<ChoiceChip>(find.byKey(ValueKey('metrica-${m.name}')));

      expect(chip(Metrica.bpm).selected, isTrue);
      for (final m in Metrica.values) {
        expect(find.text(m.rotulo), findsOneWidget, reason: 'nome por extenso e unidade');
      }
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico de batimentos cardíacos nos últimos 5 minutos: atual 128 bpm')),
          findsOneWidget);
      expect((grafico().series.first as SplineAreaSeries).borderColor, CoresDados.claro.metricas[Metrica.bpm.index]);

      await tocarNoMeio(tester, find.byKey(const ValueKey('metrica-ruido')));
      expect(chip(Metrica.ruido).selected, isTrue);
      expect(chip(Metrica.bpm).selected, isFalse);
      final eixo = grafico().primaryYAxis as NumericAxis;
      expect(eixo.title.text, 'dB');
      expect([eixo.minimum, eixo.maximum], [20, 100]);
      expect((grafico().series.first as SplineAreaSeries).borderColor, CoresDados.claro.metricas[Metrica.ruido.index]);
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico de ruído ambiente nos últimos 5 minutos: atual \d+ dB')),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Máxima: \d+ dB$')), findsOneWidget);

      await tocarNoMeio(tester, find.byKey(const ValueKey('metrica-regularidade')));
      final regularidade = grafico().primaryYAxis as NumericAxis;
      expect(regularidade.title.text, '0 a 1');
      expect([regularidade.minimum, regularidade.maximum], [0, 1]);
      expect(find.bySemanticsLabel(RegExp(r'^Atual: 0,\d\d$')), findsOneWidget, reason: 'vírgula decimal');
      semantica.dispose();
    });

    testWidgets('cores das métricas: nenhuma é a de um nível de risco', (tester) async {
      for (final dados in [CoresDados.claro, CoresDados.escuro]) {
        final niveis = dados == CoresDados.claro ? CoresApp.claro : CoresApp.escuro;
        for (final cor in dados.metricas) {
          expect(cor, isNot(anyOf(niveis.calmo.grafico, niveis.atencao.grafico, niveis.crise.grafico)));
        }
        expect(dados.metricas.toSet().length, Metrica.values.length);
      }
    });

    // Sem imagem (os goldens das metricas no escuro sairam na limpeza): cada
    // metrica e desenhada no tema escuro, sem erro, com a cor da paleta escura.
    testWidgets('tema escuro: as 8 métricas desenham sem erro, cada uma com a sua cor', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1, escuro: true);
      SfCartesianChart grafico() =>
          tester.widget<SfCartesianChart>(find.descendant(of: find.byType(GraficoSinais), matching: find.byType(SfCartesianChart)));
      expect(Metrica.values, hasLength(8));
      for (final m in Metrica.values) {
        await tocarNoMeio(tester, find.byKey(ValueKey('metrica-${m.name}')));
        expect(tester.takeException(), isNull, reason: '${m.name} no escuro');
        expect(tester.widget<ChoiceChip>(find.byKey(ValueKey('metrica-${m.name}'))).selected, isTrue);
        final serie = grafico().series.first as SplineAreaSeries;
        expect(serie.dataSource, isNotEmpty, reason: '${m.name} tem pontos para desenhar');
        expect(serie.borderColor, CoresDados.escuro.metricas[m.index], reason: '${m.name} usa a cor da paleta escura');
      }
    });

    testWidgets('faixas de fundo nos momentos de Atenção e Possível crise, com legenda', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await possivelCrise(), aba: 1);
      final eixoX = tester
          .widget<SfCartesianChart>(find.descendant(of: find.byType(GraficoSinais), matching: find.byType(SfCartesianChart)))
          .primaryXAxis;
      expect(eixoX.plotBands.length, 2);
      expect(eixoX.plotBands.map((b) => b.color), [CoresApp.claro.atencao.fundo, CoresApp.claro.crise.fundo]);
      expect(find.text('Momentos em Atenção'), findsOneWidget);
      expect(find.text('Momentos em Possível crise'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Nível Atenção das 14:5\d às 14:5\d\. Nível Possível crise das')), findsOneWidget);

      await mostrar(tester, await calmo(), aba: 1);
      expect(find.text('Momentos em Atenção'), findsNothing, reason: 'sem faixa, sem legenda');
      semantica.dispose();
    });

    testWidgets('tocar no gráfico abre o balão com TODAS as métricas do instante', (tester) async {
      await mostrar(tester, await possivelCrise(), aba: 1);
      final area = tester.getRect(find.byType(GraficoSinais));
      final gesto = await tester.startGesture(Offset(area.left + area.width * 0.8, area.center.dy));
      await tester.pump();
      final balao = find.byType(BalaoSinais);
      expect(balao, findsOneWidget);
      for (final m in Metrica.values) {
        expect(find.descendant(of: balao, matching: find.text(m.curto)), findsOneWidget);
      }
      expect(find.descendant(of: balao, matching: find.textContaining(RegExp(r'^\d\d:\d\d:\d\d$'))), findsOneWidget);
      // Arrastar troca o instante
      final antes = tester.widget<BalaoSinais>(balao).amostra.hora;
      await gesto.moveBy(Offset(-area.width * 0.4, 0));
      await tester.pump();
      expect(tester.widget<BalaoSinais>(balao).amostra.hora.isBefore(antes), isTrue);
      // Some sozinho alguns segundos depois de tirar o dedo
      await gesto.up();
      await tester.pump(Grafico.balaoVisivel + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(balao, findsNothing);
    });

    testWidgets('painel parado e sem conexão: gráfico congelado, com aviso', (tester) async {
      await mostrar(tester, await painelEPulseiraOffline(), aba: 1);
      expect(find.text('A pulseira parou de enviar às 15:00. O gráfico mostra os últimos 5 minutos recebidos.'),
          findsOneWidget);
      expect(find.byType(GraficoSinais), findsOneWidget);

      await mostrar(tester, await semConexao(), aba: 1);
      expect(find.text('Sem conexão com o servidor. O gráfico está parado na última leitura, das 15:00.'), findsOneWidget);
      expect(find.byType(GraficoSinais), findsOneWidget);

      await mostrar(tester, await conectando(), aba: 1);
      expect(find.text('Conectando ao servidor…'), findsOneWidget);
      expect(find.byType(GraficoSinais), findsNothing);
    });

    testWidgets('sem dados ainda: estados vazios', (tester) async {
      await mostrar(tester, await semDadosAinda(), aba: 1);
      expect(find.text('Aguardando leituras ao vivo'), findsOneWidget);
      expect(find.text('Nenhuma crise nos últimos 7 dias'), findsOneWidget);
    });

    testWidgets('7 dias: confirmadas e aguardando confirmação empilhadas, sem descartados', (tester) async {
      final semantica = tester.ensureSemantics();
      await mostrar(tester, await calmo(), aba: 1);
      expect(
        find.text('Nos últimos 7 dias: 11 crises confirmadas e 2 aguardando sua confirmação. '
            'Em novembro: 11 crises confirmadas.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Gráfico de crises por dia: Sex, nenhuma; Sáb, nenhuma; '
            r'Dom, 3 crises confirmadas; Seg, 1 possível crise aguardando confirmação; Ter, 7 crises confirmadas; '
            r'Qua, nenhuma; Hoje, 1 crise confirmada e 1 possível crise aguardando confirmação\.$')),
        findsOneWidget,
      );
      final grafico = tester.widget<SfCartesianChart>(
          find.descendant(of: find.byType(GraficoSeteDias), matching: find.byType(SfCartesianChart)));
      expect(grafico.series.length, 2);
      expect(grafico.series.every((s) => s is StackedColumnSeries), isTrue);
      expect(find.text('Crise confirmada'), findsOneWidget);
      expect(find.text('Possível crise aguardando confirmação'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('Ajustes', () {
    testWidgets('ajustes: título igual à aba e "Alertas sonoros" liga/desliga', (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3, altura: 1100);
      expect(find.text('Ajustes'), findsNWidgets(2)); // titulo + aba
      expect(find.text('Privacidade'), findsNothing);
      await tester.tap(find.text('Alertas sonoros'));
      await tester.pumpAndSettle();
      expect(servico.sonoros, isFalse);
    });

    testWidgets('Aparência: a escolha troca o tema na hora, fica salva e as barras do Android acompanham',
        (tester) async {
      final semantica = tester.ensureSemantics();
      final servico = await calmo();
      final preferencias = preferenciasDe(servico);
      tester.view.physicalSize = const Size(393 * 2, 1400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // O app de verdade (main.dart), aberto direto em Ajustes
      await tester.pumpWidget(AppScope(
        service: servico,
        child: PreferenciasScope(preferencias: preferencias, child: const PuzzleBandApp(rotaInicial: '/configuracoes')),
      ));
      await carregarImagens(tester);
      await tester.pumpAndSettle();

      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      Brightness brilho() => Theme.of(tester.element(find.text('Aparência'))).brightness;
      SystemUiOverlayStyle barras() => tester
          .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
          .value;

      expect(app().themeMode, ThemeMode.system, reason: 'padrão: seguir o sistema');
      expect(brilho(), Brightness.light);
      expect(find.bySemanticsLabel(RegExp('Seguir o sistema')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('aparencia-sistema'))),
        isSemantics(isChecked: true, hasCheckedState: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
      );

      await tocarVisivel(tester, find.text('Escuro'));
      expect(app().themeMode, ThemeMode.dark);
      expect(brilho(), Brightness.dark);
      expect(servico.prefs.getString('aparencia'), 'escuro');
      expect(barras().statusBarIconBrightness, Brightness.light, reason: 'ícones claros no escuro');
      expect(barras().systemNavigationBarColor, CoresApp.escuro.superficie);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('aparencia-escuro'))),
        isSemantics(isChecked: true, hasCheckedState: true, isInMutuallyExclusiveGroup: true, hasTapAction: true),
      );
      // Reabrir o app lê a escolha salva
      expect(preferenciasDe(servico).aparencia, Aparencia.escuro);

      await tocarVisivel(tester, find.text('Claro'));
      expect(app().themeMode, ThemeMode.light);
      expect(barras().statusBarIconBrightness, Brightness.dark);

      await tocarVisivel(tester, find.text('Seguir o sistema'));
      expect(app().themeMode, ThemeMode.system);
      expect(servico.prefs.getString('aparencia'), isNull, reason: 'o padrão não precisa ficar salvo');
      semantica.dispose();
    });

    testWidgets('ajustes mostra o erro de configuração', (tester) async {
      await mostrar(tester, await erroDeConfiguracao(), aba: 3, altura: 1100);
      expect(find.text('Servidor: não configurado'), findsOneWidget);
      expect(find.textContaining('Configuração ausente: MQTT_PASS'), findsOneWidget);
    });

    testWidgets('"Apagar dados deste aparelho": pede confirmação; cancelar não apaga; as preferências só com a opção marcada',
        (tester) async {
      final servico = await calmo();
      await mostrar(tester, servico, aba: 3, altura: 1400);
      final botao = find.byKey(const ValueKey('apagar-dados'));
      expect(find.text('Dados deste aparelho'), findsOneWidget);

      // Cancelar: nada muda
      await tocarVisivel(tester, botao);
      expect(find.text('Apagar dados deste aparelho?'), findsOneWidget);
      expect(find.textContaining('Não dá para desfazer'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(servico.apagamentos, isEmpty);
      expect(servico.episodios, isNotEmpty);

      // Apagar (padrão): mantém as preferências
      await tocarVisivel(tester, botao);
      await tester.tap(find.byKey(const ValueKey('confirmar-apagar')));
      await tester.pumpAndSettle();
      expect(servico.apagamentos, [true]);
      expect(servico.episodios, isEmpty);
      expect(find.text('Dados deste aparelho apagados.'), findsOneWidget);

      // Com a opção marcada: também as preferências
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tocarVisivel(tester, botao);
      await tester.tap(find.byKey(const ValueKey('apagar-preferencias')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar-apagar')));
      await tester.pumpAndSettle();
      expect(servico.apagamentos, [true, false]);
    });

    testWidgets('"Apagar dados" com preferências: o campo do nome recomeça vazio e o nome volta ao CHILD_ID', (tester) async {
      final servico = ServicoComLimpeza(prefs: (await calmo()).prefs, estadoFixo: (await calmo()).estadoAtual!);
      final preferencias = preferenciasDe(servico);
      servico.limpezaExtra = preferencias.apagarDados;
      await preferencias.definirNomeCrianca('Ana');
      await mostrar(tester, servico, aba: 3, altura: 1400, preferencias: preferencias);
      expect(find.widgetWithText(TextField, 'Ana'), findsOneWidget);

      await tocarVisivel(tester, find.byKey(const ValueKey('apagar-dados')));
      await tester.tap(find.byKey(const ValueKey('apagar-preferencias')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirmar-apagar')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Ana'), findsNothing, reason: 'o campo recomeça vazio');
      expect(preferencias.nomeCrianca, 'C01');
    });
  });

  group('Histórico vazio da pulseira e ordem de reset (serviço real)', () {
    testWidgets('lista vazia da pulseira: calendário, "Hoje", 7 dias e último episódio ficam vazios', (tester) async {
      final base = await calmo();
      final servico = ServicoComLimpeza(prefs: base.prefs, estadoFixo: base.estadoAtual!);
      await servico.iniciar();
      // Cópia antiga (de antes do --limpar-historico), como a que fica salva no celular
      servico.tratarMensagem('puzzleband/C01/historico', mensagemDaPulseira(base.episodios));

      await mostrar(tester, servico, aba: 2);
      expect(find.byType(CalendarioCrises), findsOneWidget);
      await mostrar(tester, servico);
      expect(find.text('Hoje: 2 episódios'), findsOneWidget);
      expect(find.textContaining('Último episódio:'), findsOneWidget);

      // Chega o histórico vazio publicado pela pulseira
      expect(servico.tratarMensagem('puzzleband/C01/historico', mensagemDaPulseira(const [])), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Hoje: nenhum episódio'), findsOneWidget);
      expect(find.text('Nenhum episódio registrado ainda.'), findsOneWidget);
      await mostrar(tester, servico, aba: 2);
      expect(find.byType(CalendarioCrises), findsNothing);
      expect(find.text('Nenhum episódio ainda'), findsOneWidget);
      await mostrar(tester, servico, aba: 1);
      expect(find.text('Nenhuma crise nos últimos 7 dias'), findsOneWidget);

      // Uma aba antiga do site republicando a lista velha não traz os episódios de volta
      final doSite = jsonEncode({'origem': 'site', 'episodios': [for (final e in base.episodios) e.toJson()]});
      expect(servico.tratarMensagem('puzzleband/C01/historico', doSite), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma crise nos últimos 7 dias'), findsOneWidget);
    });

    testWidgets('ordem de reset no app aberto: SnackBar discreto "Dados apagados para uma nova apresentação."', (tester) async {
      final servico = await calmo();
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppScope(
        service: servico,
        child: PreferenciasScope(preferencias: preferenciasDe(servico), child: const PuzzleBandApp(rotaInicial: '/historico')),
      ));
      await carregarImagens(tester);
      await tester.pumpAndSettle();

      servico.tratarMensagem('puzzleband/C01/comando', '{"acao":"resetar","id":"r1","manter_preferencias":true}');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Dados apagados para uma nova apresentação.'), findsOneWidget);
      expect(servico.apagamentos, [true]);
      expect(servico.resetAplicado, 'r1');

      // a mesma ordem (retida) numa reconexão: nada de novo
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      servico.tratarMensagem('puzzleband/C01/comando', '{"acao":"resetar","id":"r1"}');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Dados apagados para uma nova apresentação.'), findsNothing);
      expect(servico.apagamentos, [true]);
    });
  });

  group('Acessibilidade (todas as telas, tema claro e escuro)', () {
    final telas = <String, Future<void> Function(WidgetTester, bool)>{
      'configurar alertas': (t, e) async => mostrar(t, await calmo(), tela: const ConfigurarAlertasScreen(), escuro: e),
      'início (crise)': (t, e) async => mostrar(t, await possivelCrise(), escuro: e),
      'início (sem conexão)': (t, e) async => mostrar(t, await semConexao(), escuro: e),
      'início (painel "Hoje" aberto, com lembrete)': (t, e) async {
        final servico = await calmo();
        final preferencias = preferenciasDe(servico);
        await preferencias.salvarLembrete(PreferenciasLocais.chaveDia(agoraFixo), 'Levar o abafador',
            avisarEm: DateTime(2026, 11, 5, 17, 30), tituloDoAviso: 'L');
        await mostrar(t, servico, escuro: e, altura: 1600, preferencias: preferencias);
        await abrirPainel(t, 'Hoje: 2 episódios');
      },
      'início (crise, "Estou ciente" enviado)': (t, e) async {
        await mostrar(t, await possivelCrise(), escuro: e);
        await t.tap(find.text('Estou ciente'));
        await t.pump();
      },
      'episódio (detalhe)': (t, e) async {
        await mostrar(t, await calmo(), escuro: e, altura: 1100);
        await tocarVisivel(t, find.text('Nenhum episódio agora'));
      },
      'gráficos': (t, e) async => mostrar(t, await possivelCrise(), aba: 1, escuro: e),
      'gráficos (ruído, 7 dias)': (t, e) async {
        await mostrar(t, await possivelCrise(), aba: 1, escuro: e, altura: 1300);
        await tocarNoMeio(t, find.byKey(const ValueKey('metrica-ruido')));
      },
      'gráficos (painel parado)': (t, e) async => mostrar(t, await painelEPulseiraOffline(), aba: 1, escuro: e),
      'histórico': (t, e) async => mostrar(t, await calmo(), aba: 2, escuro: e),
      'histórico (cartão aberto, possível crise a confirmar)': (t, e) async {
        await mostrar(t, await calmo(), aba: 2, escuro: e, altura: 1600);
        await tocarNoMeio(t, cartao('ep_4'));
      },
      'histórico (descartado)': (t, e) async {
        await mostrar(t, await calmo(), aba: 2, escuro: e, altura: 1600);
        await tocarNoMeio(t, cartao('ep_4'));
        await tocarNoMeio(t, find.text('Descartar'));
        await t.pump(const Duration(seconds: 5)); // o aviso (SnackBar) some
        await t.pumpAndSettle();
      },
      'histórico (filtro por dia, calendário recolhido)': (t, e) async {
        await mostrar(t, await calmo(), aba: 2, escuro: e);
        await tocarNoMeio(t, diaDoCalendario(3));
        await t.tap(find.byTooltip('Recolher calendário'));
        await t.pumpAndSettle();
      },
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
      await mostrar(tester, await calmo(), tela: const ConfigurarAlertasScreen(), escala: 1.3);
      expect(tester.takeException(), isNull);
      for (final cenario in [calmo, atencao, possivelCrise, semConexao, conectando, painelEPulseiraOffline, erroDeConfiguracao, semDadosAinda]) {
        for (final aba in [0, 1, 2, 3]) {
          await mostrar(tester, await cenario(), aba: aba, escala: 1.3);
          expect(tester.takeException(), isNull);
        }
      }
      // Graficos: outra metrica e o balao aberto
      await mostrar(tester, await possivelCrise(), aba: 1, escala: 1.3);
      await tocarNoMeio(tester, find.byKey(const ValueKey('metrica-regularidade')));
      final area = tester.getRect(find.byType(GraficoSinais));
      final gesto = await tester.startGesture(area.center);
      await tester.pump();
      expect(find.byType(BalaoSinais), findsOneWidget);
      expect(tester.takeException(), isNull);
      await gesto.up();
      await tester.pump(Grafico.balaoVisivel);
      await tester.pumpAndSettle();
      // Historico: calendario, cartao aberto e descartado
      await mostrar(tester, await calmo(), aba: 2, escala: 1.3);
      await tocarNoMeio(tester, cartao('ep_4'));
      await tocarNoMeio(tester, find.text('Descartar'));
      expect(find.text('Descartado'), findsWidgets);
      expect(tester.takeException(), isNull);
      // Inicio com o painel aberto, o detalhe do episodio e o editor de lembrete
      for (final (cenario, rotulo) in [
        (calmo, 'Hoje: 2 episódios'),
        (semEpisodiosHoje, 'Hoje: nenhum episódio'),
        (semConexao, 'Hoje: 2 episódios'),
      ]) {
        await mostrar(tester, await cenario(), escala: 1.3);
        await abrirPainel(tester, rotulo);
        expect(tester.takeException(), isNull);
      }
      await mostrar(tester, await calmo(), escala: 1.3);
      await tocarVisivel(tester, find.text('Nenhum episódio agora'));
      expect(tester.takeException(), isNull);
      await tocarVisivel(tester, find.text('Adicionar lembrete'));
      expect(find.text('Salvar lembrete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('celular estreito (360 dp) e largo (440 dp): a faixa se ajusta sem cortar', (tester) async {
      for (final largura in [360.0, 440.0]) {
        for (final escala in [1.0, 1.3]) {
          await mostrar(tester, await possivelCrise(), escala: escala);
          tester.view.physicalSize = Size(largura * 2, 852 * 2);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('128'), findsOneWidget);
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
      expect(quandoEm(DateTime(2026, 11, 5, 14, 32), agoraFixo), 'hoje às 14:32');
      expect(quandoEm(DateTime(2026, 11, 4, 18, 5), agoraFixo), 'ontem às 18:05');
      expect(quandoEm(DateTime(2026, 11, 6, 8, 0), agoraFixo), 'amanhã às 08:00');
      expect(quandoEm(DateTime(2026, 11, 2, 10, 40), agoraFixo), 'em 02/11 às 10:40');
    });

    test('horário do episódio: fim do site ou início + duração; em andamento', () {
      final inicio = DateTime(2026, 11, 5, 14, 32);
      expect(horarioDoEpisodio(Episodio(id: 'a', inicio: inicio, nivelMaximo: NivelRisco.atencao)),
          'Desde 14:32, em andamento');
      expect(
          horarioDoEpisodio(Episodio(
              id: 'b', inicio: inicio, duracaoS: 117, encerramento: 'normalizou', nivelMaximo: NivelRisco.atencao)),
          'Das 14:32 às 14:33');
      expect(
          horarioDoEpisodio(Episodio(
              id: 'c',
              inicio: inicio,
              fim: DateTime(2026, 11, 5, 14, 40),
              duracaoS: 117,
              encerramento: 'normalizou',
              nivelMaximo: NivelRisco.atencao)),
          'Das 14:32 às 14:40');
      expect(horarioDoEpisodio(Episodio(id: 'd', inicio: inicio, encerramento: 'interrompido', nivelMaximo: NivelRisco.atencao)),
          'Às 14:32');
    });
  });
}
