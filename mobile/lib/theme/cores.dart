// Paleta "Sala calma" (docs/design-app.md): cores pouco saturadas, sem
// vermelho nem amarelo decorativos - essas cores ficam reservadas para os
// niveis de risco. Contrastes WCAG conferidos em docs/design-app.md.

import 'package:flutter/material.dart';

/// Tons de um nivel: texto/icone, fundo tingido e cor de grafico.
@immutable
class TomRisco {
  const TomRisco({required this.texto, required this.fundo, required this.grafico});

  /// Texto e icone do nivel (>= 4.5:1 sobre [fundo] e sobre a superficie).
  final Color texto;

  /// Fundo tingido (faixa de estado, selos).
  final Color fundo;

  /// Barras e marcas de grafico (>= 3:1 sobre a superficie).
  final Color grafico;

  static TomRisco lerp(TomRisco a, TomRisco b, double t) => TomRisco(
        texto: Color.lerp(a.texto, b.texto, t)!,
        fundo: Color.lerp(a.fundo, b.fundo, t)!,
        grafico: Color.lerp(a.grafico, b.grafico, t)!,
      );
}

/// Cores do app, acessiveis por `CoresApp.of(context)` em qualquer tela.
@immutable
class CoresApp extends ThemeExtension<CoresApp> {
  const CoresApp({
    required this.fundo,
    required this.superficie,
    required this.superficieAlta,
    required this.tinta,
    required this.tintaSuave,
    required this.contorno,
    required this.divisoria,
    required this.primaria,
    required this.sobrePrimaria,
    required this.primariaSuave,
    required this.sobrePrimariaSuave,
    required this.calmo,
    required this.atencao,
    required this.crise,
    required this.semDados,
    required this.informativo,
    required this.informativoBorda,
    required this.balao,
    required this.balaoBorda,
    required this.sombraElevada,
  });

  /// Fundo das telas ("nevoa").
  final Color fundo;

  /// Cartoes e secoes.
  final Color superficie;

  /// Areas de destaque neutras (avisos de conexao, linha de avaliacao).
  final Color superficieAlta;

  /// Texto principal.
  final Color tinta;

  /// Texto secundario.
  final Color tintaSuave;

  /// Contorno de campos e controles (>= 3:1).
  final Color contorno;

  /// Divisorias e linhas de grade (decorativas).
  final Color divisoria;

  /// Cor de acao (azul ardosia, vindo do azul da fita do logo).
  final Color primaria;
  final Color sobrePrimaria;
  final Color primariaSuave;
  final Color sobrePrimariaSuave;

  final TomRisco calmo;
  final TomRisco atencao;
  final TomRisco crise;
  final TomRisco semDados;

  /// Fundo azulado de uma linha informativa (probabilidade estimada).
  final Color informativo;

  /// Borda decorativa da linha informativa (nao e controle: abaixo de 3:1).
  final Color informativoBorda;

  /// Baloes dos graficos e avisos (SnackBar). No claro, o inverso (fundo
  /// escuro); no escuro, uma superficie elevada, sem bloco claro que ofusque a
  /// vista a noite.
  final ParCor balao;

  /// Contorno do balao: so no escuro, para separar da superficie (>= 3:1).
  final Color balaoBorda;

  /// Sombra suave e azulada das pecas "ao vivo" (faixa de estado e cartao do
  /// episodio). Vazia no tema escuro: ali as pecas se separam pelo tom.
  final List<BoxShadow> sombraElevada;

  static CoresApp of(BuildContext context) => Theme.of(context).extension<CoresApp>()!;

  /// Fundo do selo do logo nos dois temas: o PNG da fita tem fundo branco.
  static const fundoDoLogo = Color(0xFFFFFFFF);

  static const claro = CoresApp(
    fundo: Color(0xFFF0F3F5),
    superficie: Color(0xFFFFFFFF),
    superficieAlta: Color(0xFFE4E9ED),
    tinta: Color(0xFF1B2A35),
    tintaSuave: Color(0xFF4B5B67),
    contorno: Color(0xFF7A8994),
    divisoria: Color(0xFFD6DDE2),
    primaria: Color(0xFF2D5B86),
    sobrePrimaria: Color(0xFFFFFFFF),
    primariaSuave: Color(0xFFDCE7F2),
    sobrePrimariaSuave: Color(0xFF12324F),
    calmo: TomRisco(texto: Color(0xFF2B6A4E), fundo: Color(0xFFE2F1E9), grafico: Color(0xFF2B9066)),
    atencao: TomRisco(texto: Color(0xFF8A5200), fundo: Color(0xFFFCEFD6), grafico: Color(0xFFC08A00)),
    crise: TomRisco(texto: Color(0xFFA3304F), fundo: Color(0xFFFBE6EC), grafico: Color(0xFFC73E66)),
    semDados: TomRisco(texto: Color(0xFF56636D), fundo: Color(0xFFE6EBEE), grafico: Color(0xFF7A8994)),
    informativo: Color(0xFFEDF6FF),
    informativoBorda: Color(0xFFABBFD2),
    balao: ParCor(fundo: Color(0xFF1B2A35), texto: Color(0xFFF0F3F5)),
    balaoBorda: Color(0x00000000),
    sombraElevada: [
      BoxShadow(color: Color(0x0F2D5B86), offset: Offset(0, 1), blurRadius: 3),
      BoxShadow(color: Color(0x1F2D5B86), offset: Offset(0, 4), blurRadius: 16),
    ],
  );

  static const escuro = CoresApp(
    fundo: Color(0xFF11181D),
    superficie: Color(0xFF1A232A),
    superficieAlta: Color(0xFF26313A),
    tinta: Color(0xFFE8EEF2),
    tintaSuave: Color(0xFFAEBBC5),
    contorno: Color(0xFF6B7A86),
    divisoria: Color(0xFF2E3A44),
    primaria: Color(0xFF9DC2E6),
    sobrePrimaria: Color(0xFF0E2A44),
    primariaSuave: Color(0xFF23415E),
    sobrePrimariaSuave: Color(0xFFD6E6F5),
    calmo: TomRisco(texto: Color(0xFF8FD3AE), fundo: Color(0xFF16352A), grafico: Color(0xFF3F9E72)),
    atencao: TomRisco(texto: Color(0xFFF3C46B), fundo: Color(0xFF3A2B10), grafico: Color(0xFFB88A1E)),
    crise: TomRisco(texto: Color(0xFFF5A3B6), fundo: Color(0xFF44192A), grafico: Color(0xFFD65C78)),
    semDados: TomRisco(texto: Color(0xFFA7B3BC), fundo: Color(0xFF263038), grafico: Color(0xFF6B7A86)),
    informativo: Color(0xFF172736),
    informativoBorda: Color(0xFF34506A),
    balao: ParCor(fundo: Color(0xFF2B3741), texto: Color(0xFFE8EEF2)),
    balaoBorda: Color(0xFF7B8A96),
    sombraElevada: [],
  );

  @override
  CoresApp copyWith({
    Color? fundo,
    Color? superficie,
    Color? superficieAlta,
    Color? tinta,
    Color? tintaSuave,
    Color? contorno,
    Color? divisoria,
    Color? primaria,
    Color? sobrePrimaria,
    Color? primariaSuave,
    Color? sobrePrimariaSuave,
    TomRisco? calmo,
    TomRisco? atencao,
    TomRisco? crise,
    TomRisco? semDados,
    Color? informativo,
    Color? informativoBorda,
    ParCor? balao,
    Color? balaoBorda,
    List<BoxShadow>? sombraElevada,
  }) {
    return CoresApp(
      fundo: fundo ?? this.fundo,
      superficie: superficie ?? this.superficie,
      superficieAlta: superficieAlta ?? this.superficieAlta,
      tinta: tinta ?? this.tinta,
      tintaSuave: tintaSuave ?? this.tintaSuave,
      contorno: contorno ?? this.contorno,
      divisoria: divisoria ?? this.divisoria,
      primaria: primaria ?? this.primaria,
      sobrePrimaria: sobrePrimaria ?? this.sobrePrimaria,
      primariaSuave: primariaSuave ?? this.primariaSuave,
      sobrePrimariaSuave: sobrePrimariaSuave ?? this.sobrePrimariaSuave,
      calmo: calmo ?? this.calmo,
      atencao: atencao ?? this.atencao,
      crise: crise ?? this.crise,
      semDados: semDados ?? this.semDados,
      informativo: informativo ?? this.informativo,
      informativoBorda: informativoBorda ?? this.informativoBorda,
      balao: balao ?? this.balao,
      balaoBorda: balaoBorda ?? this.balaoBorda,
      sombraElevada: sombraElevada ?? this.sombraElevada,
    );
  }

  @override
  CoresApp lerp(ThemeExtension<CoresApp>? other, double t) {
    if (other is! CoresApp) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return CoresApp(
      fundo: c(fundo, other.fundo),
      superficie: c(superficie, other.superficie),
      superficieAlta: c(superficieAlta, other.superficieAlta),
      tinta: c(tinta, other.tinta),
      tintaSuave: c(tintaSuave, other.tintaSuave),
      contorno: c(contorno, other.contorno),
      divisoria: c(divisoria, other.divisoria),
      primaria: c(primaria, other.primaria),
      sobrePrimaria: c(sobrePrimaria, other.sobrePrimaria),
      primariaSuave: c(primariaSuave, other.primariaSuave),
      sobrePrimariaSuave: c(sobrePrimariaSuave, other.sobrePrimariaSuave),
      calmo: TomRisco.lerp(calmo, other.calmo, t),
      atencao: TomRisco.lerp(atencao, other.atencao, t),
      crise: TomRisco.lerp(crise, other.crise, t),
      semDados: TomRisco.lerp(semDados, other.semDados, t),
      informativo: c(informativo, other.informativo),
      informativoBorda: c(informativoBorda, other.informativoBorda),
      balao: ParCor.lerp(balao, other.balao, t),
      balaoBorda: c(balaoBorda, other.balaoBorda),
      sombraElevada: BoxShadow.lerpList(sombraElevada, other.sombraElevada, t) ?? const [],
    );
  }
}

/// Fundo + texto (dias do calendario, selo e botao "Descartado").
@immutable
class ParCor {
  const ParCor({required this.fundo, required this.texto});

  final Color fundo;

  /// Texto e icone sobre [fundo] (>= 4.5:1).
  final Color texto;

  static ParCor lerp(ParCor a, ParCor b, double t) =>
      ParCor(fundo: Color.lerp(a.fundo, b.fundo, t)!, texto: Color.lerp(a.texto, b.texto, t)!);
}

/// Cores dos graficos, do calendario e da avaliacao do cuidador
/// (`CoresDados.of(context)`). Contrastes em docs/design-app.md.
@immutable
class CoresDados extends ThemeExtension<CoresDados> {
  const CoresDados({
    required this.metricas,
    required this.diaAmarelo,
    required this.diaVermelho,
    required this.pendente,
    required this.descartado,
    required this.descartadoTinta,
    required this.barraConfirmada,
    required this.barraPendente,
    required this.barraPendenteListra,
  });

  /// Uma cor por metrica do grafico ao vivo, na ordem de `Metrica`
  /// (models/sinais.dart). Tons frios e neutros: nenhum vermelho, ambar ou
  /// verde dos niveis. >= 3:1 sobre a superficie e sobre as faixas de nivel.
  final List<Color> metricas;

  /// Dia com 1 a 5 crises confirmadas.
  final ParCor diaAmarelo;

  /// Dia com mais de 5 crises confirmadas.
  final ParCor diaVermelho;

  /// Possivel crise aguardando confirmacao: bolinha do calendario, contorno,
  /// icone e texto do selo "a confirmar" (>= 4.5:1 sobre a superficie).
  final Color pendente;

  /// Botao "Descartado" (selecionado) e selo "Descartado" do cartao resumido:
  /// vermelho tijolo cheio, diferente do framboesa de "Possivel crise" e da
  /// pilula tingida do nivel (ΔE >= 17 no escuro).
  final ParCor descartado;

  /// Icone de "descartado" sobre superficies neutras (linha da avaliacao).
  final Color descartadoTinta;

  /// Grafico de 7 dias: crises confirmadas (cor solida).
  final Color barraConfirmada;

  /// Grafico de 7 dias: aguardando confirmacao (fundo claro + listras).
  final Color barraPendente;
  final Color barraPendenteListra;

  static CoresDados of(BuildContext context) => Theme.of(context).extension<CoresDados>()!;

  static const claro = CoresDados(
    metricas: [
      Color(0xFF4376B6), // batimentos
      Color(0xFF9A5A94), // suor (EDA)
      Color(0xFF025884), // HRV
      Color(0xFF6E67BD), // movimento
      Color(0xFF845011), // regularidade
      Color(0xFF3A4D91), // luz
      Color(0xFF108EA3), // ruido
      Color(0xFF8160B5), // probabilidade
    ],
    diaAmarelo: ParCor(fundo: Color(0xFFF3C54E), texto: Color(0xFF1B2A35)),
    diaVermelho: ParCor(fundo: Color(0xFFB02E52), texto: Color(0xFFFFFFFF)),
    pendente: Color(0xFF1E66B0),
    descartado: ParCor(fundo: Color(0xFFB3261E), texto: Color(0xFFFFFFFF)),
    descartadoTinta: Color(0xFFB3261E),
    barraConfirmada: Color(0xFF2D5B86),
    barraPendente: Color(0xFFDCE7F2),
    barraPendenteListra: Color(0xFF5F86AD),
  );

  static const escuro = CoresDados(
    metricas: [
      Color(0xFF407BC5),
      Color(0xFFB57BAF),
      Color(0xFF069CE4),
      Color(0xFF736DC3),
      Color(0xFFC2823E),
      Color(0xFF6076BE),
      Color(0xFF33A3B4),
      Color(0xFF8766BB),
    ],
    diaAmarelo: ParCor(fundo: Color(0xFFE0B13F), texto: Color(0xFF1B1607)),
    diaVermelho: ParCor(fundo: Color(0xFFE7849A), texto: Color(0xFF1F0A11)),
    pendente: Color(0xFF8CC3F2),
    descartado: ParCor(fundo: Color(0xFF9E3418), texto: Color(0xFFFCEAE6)),
    descartadoTinta: Color(0xFFFF9F85),
    barraConfirmada: Color(0xFF9DC2E6),
    barraPendente: Color(0xFF23415E),
    barraPendenteListra: Color(0xFF7FA6CC),
  );

  @override
  CoresDados copyWith({
    List<Color>? metricas,
    ParCor? diaAmarelo,
    ParCor? diaVermelho,
    Color? pendente,
    ParCor? descartado,
    Color? descartadoTinta,
    Color? barraConfirmada,
    Color? barraPendente,
    Color? barraPendenteListra,
  }) {
    return CoresDados(
      metricas: metricas ?? this.metricas,
      diaAmarelo: diaAmarelo ?? this.diaAmarelo,
      diaVermelho: diaVermelho ?? this.diaVermelho,
      pendente: pendente ?? this.pendente,
      descartado: descartado ?? this.descartado,
      descartadoTinta: descartadoTinta ?? this.descartadoTinta,
      barraConfirmada: barraConfirmada ?? this.barraConfirmada,
      barraPendente: barraPendente ?? this.barraPendente,
      barraPendenteListra: barraPendenteListra ?? this.barraPendenteListra,
    );
  }

  @override
  CoresDados lerp(ThemeExtension<CoresDados>? other, double t) {
    if (other is! CoresDados) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return CoresDados(
      metricas: [for (var i = 0; i < metricas.length; i++) c(metricas[i], other.metricas[i])],
      diaAmarelo: ParCor.lerp(diaAmarelo, other.diaAmarelo, t),
      diaVermelho: ParCor.lerp(diaVermelho, other.diaVermelho, t),
      pendente: c(pendente, other.pendente),
      descartado: ParCor.lerp(descartado, other.descartado, t),
      descartadoTinta: c(descartadoTinta, other.descartadoTinta),
      barraConfirmada: c(barraConfirmada, other.barraConfirmada),
      barraPendente: c(barraPendente, other.barraPendente),
      barraPendenteListra: c(barraPendenteListra, other.barraPendenteListra),
    );
  }
}
