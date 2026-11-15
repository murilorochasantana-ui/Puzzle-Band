// Onde fica o banco local no celular (separado de banco.dart para que o
// esquema possa ser exportado e testado sem o Flutter: dart run drift_dev
// make-migrations).

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'banco.dart';

/// `files/banco/puzzleband.db` (Context.getFilesDir). Pasta propria, para as
/// regras de backup excluirem o banco e os arquivos -wal e -shm de uma vez
/// (android/app/src/main/res/xml/regras_de_backup*.xml).
Future<File> arquivoDoBanco() async {
  final pasta = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}banco');
  await pasta.create(recursive: true);
  return File('${pasta.path}${Platform.pathSeparator}${BancoPuzzleBand.nomeDoArquivo}');
}

/// O banco do app. As telas e o servico em primeiro plano abrem o mesmo
/// arquivo, cada um com a sua conexao (num isolate proprio, para nao travar
/// a tela).
Future<BancoPuzzleBand> abrirBancoDoApp() async => BancoPuzzleBand.noArquivo(await arquivoDoBanco());
