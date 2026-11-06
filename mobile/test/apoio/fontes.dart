// Carrega as fontes reais nos testes (sem isso o flutter test desenha cada
// letra como um bloco): as fontes do app (FontManifest.json, inclui os icones
// do Material) e uma fonte de fallback com o nome "Roboto" para glifos que a
// Atkinson Hyperlegible Next nao tem (ex.: a seta "→" do texto do gatilho).
// No Android quem cobre esses glifos e a fonte de simbolos do sistema; aqui
// usamos a Segoe UI no Windows (a Roboto do SDK nao tem a seta) ou, fora do
// Windows, a Roboto do SDK.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> carregarFontes() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifesto = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final item in manifesto.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(item['family'] as String);
    for (final fonte in (item['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(fonte['asset'] as String));
    }
    await loader.load();
  }

  final arquivos = <File>[
    if (Platform.isWindows) ...[
      File(r'C:\Windows\Fonts\segoeui.ttf'),
      File(r'C:\Windows\Fonts\seguisb.ttf'),
      File(r'C:\Windows\Fonts\segoeuib.ttf'),
    ],
  ].where((f) => f.existsSync()).toList();
  if (arquivos.isEmpty) {
    final pasta = _fontesDoSdk();
    if (pasta == null) return;
    for (final nome in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
      final arquivo = File('${pasta.path}${Platform.pathSeparator}$nome');
      if (arquivo.existsSync()) arquivos.add(arquivo);
    }
  }
  final fallback = FontLoader('Roboto');
  for (final arquivo in arquivos) {
    fallback.addFont(Future.value(ByteData.sublistView(arquivo.readAsBytesSync())));
  }
  await fallback.load();
}

Directory? _fontesDoSdk() {
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final candidatos = [
    if (raiz != null) '$raiz/bin/cache/artifacts/material_fonts',
    // o flutter_tester fica em <flutter>/bin/cache/artifacts/engine/<plataforma>/
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts',
  ];
  for (final caminho in candidatos) {
    final pasta = Directory(caminho);
    if (pasta.existsSync()) return pasta;
  }
  return null;
}
