import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo (fita de quebra-cabeca) num selo branco. O PNG nao tem
/// transparencia: o selo branco funciona no tema claro e no escuro. A fita
/// ocupa so o terco central do PNG (margem branca dos lados), por isso o
/// recorte quadrado (BoxFit.cover) mostra a fita inteira e maior.
class LogoSelo extends StatelessWidget {
  const LogoSelo({super.key, this.tamanho = 40, this.raio = 12});

  final double tamanho;
  final double raio;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: tamanho,
        height: tamanho,
        padding: EdgeInsets.all(tamanho * 0.06),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CoresApp.fundoDoLogo,
          borderRadius: BorderRadius.circular(raio),
          border: Border.all(color: CoresApp.of(context).divisoria),
        ),
        child: Image.asset('lib/assets/autismo.png', fit: BoxFit.cover),
      ),
    );
  }
}

/// Cabecalho fixo de todas as telas: logo + logotipo "PUZZLE BAND".
class Cabecalho extends StatelessWidget {
  const Cabecalho({super.key});

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    return Semantics(
      header: true,
      label: 'Puzzle Band',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Espaco.tela, Espaco.m, Espaco.tela, Espaco.s),
        child: Row(
          children: [
            const LogoSelo(),
            const SizedBox(width: Espaco.m),
            Flexible(
              child: Text(
                'PUZZLE BAND',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Tipografia.logotipo(cores.tinta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titulo da tela (caixa normal) com uma frase opcional de apoio.
class TituloTela extends StatelessWidget {
  const TituloTela(this.titulo, {super.key, this.apoio});

  final String titulo;
  final String? apoio;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(titulo, style: texto.headlineSmall)),
        if (apoio != null) ...[
          const SizedBox(height: Espaco.xs),
          Text(apoio!, style: texto.bodyMedium!.copyWith(color: CoresApp.of(context).tintaSuave)),
        ],
      ],
    );
  }
}

/// Corpo rolavel padrao: margens da tela e largura maxima.
class CorpoTela extends StatelessWidget {
  const CorpoTela({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaco.tela, Espaco.s, Espaco.tela, Espaco.xxl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Espaco.larguraMaxima),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

/// Estrutura comum: cabecalho fixo + corpo rolavel.
class EstruturaTela extends StatelessWidget {
  const EstruturaTela({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Cabecalho(),
            Expanded(child: CorpoTela(children: children)),
          ],
        ),
      ),
    );
  }
}
