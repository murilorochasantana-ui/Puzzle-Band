// Testes de tela: o que o cuidador ve e consegue fazer, e as regras de
// acessibilidade (leitor de tela, alvos de toque, contraste, fonte ampliada,
// movimento). Os cenarios estao em test/apoio/cenarios.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/screens/login_screen.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/theme/app_theme.dart';
import 'package:puzzleband/utils/formatters.dart';
import 'package:puzzleband/utils/relogio.dart';
import 'package:puzzleband/widgets/cartao_episodio_ativo.dart';
import 'package:puzzleband/widgets/faixa_estado.dart';
import 'package:puzzleband/widgets/gatilho_simples.dart';
import 'package:puzzleband/widgets/painel_do_dia.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio/cenarios.dart';
import 'apoio/fontes.dart';
import 'apoio/servico_falso.dart';

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
