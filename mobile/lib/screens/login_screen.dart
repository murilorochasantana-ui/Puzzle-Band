import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/cabecalho.dart';

/// Login de demonstracao: so navega para a Home (sem autenticacao real,
/// limitacao documentada em docs/app.md).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuario = TextEditingController();
  final _senha = TextEditingController();

  @override
  void dispose() {
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _entrar() => Navigator.pushReplacementNamed(context, '/home');

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        // O unico movimento de abertura do app: um fade curto do conteudo.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Movimento.de(context, Movimento.entrada),
          curve: Movimento.curva,
          builder: (context, opacidade, child) => Opacity(opacity: opacidade, child: child),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Espaco.xxl, vertical: Espaco.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: LogoSelo(tamanho: 136, raio: Raio.logoGrande)),
                      const SizedBox(height: Espaco.xl),
                      Semantics(
                        header: true,
                        label: 'Puzzle Band',
                        excludeSemantics: true,
                        child: Text(
                          'PUZZLE BAND',
                          textAlign: TextAlign.center,
                          style: Tipografia.logotipo(cores.tinta, tamanho: 24),
                        ),
                      ),
                      const SizedBox(height: Espaco.s),
                      Text(
                        'App do cuidador',
                        textAlign: TextAlign.center,
                        style: texto.bodyMedium!.copyWith(color: cores.tintaSuave),
                      ),
                      const SizedBox(height: Espaco.xxl),
                      TextField(
                        controller: _usuario,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Usuário',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: Espaco.l),
                      TextField(
                        controller: _senha,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _entrar(),
                        decoration: const InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: Espaco.xl),
                      FilledButton(
                        onPressed: _entrar,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Toque.principal)),
                        child: const Text('Entrar'),
                      ),
                      const SizedBox(height: Espaco.l),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 20, color: cores.tintaSuave),
                          const SizedBox(width: Espaco.s),
                          Expanded(
                            child: Text(
                              'Versão de demonstração: qualquer usuário e senha entram.',
                              style: texto.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
