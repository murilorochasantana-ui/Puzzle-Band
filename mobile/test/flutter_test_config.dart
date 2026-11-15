// Configuracao de todos os testes (flutter test carrega este arquivo antes de
// cada um). Os testes abrem varios bancos ao mesmo tempo de proposito (um por
// cenario; dois no mesmo arquivo para simular o app e o servico): o aviso do
// drift sobre "mais de uma instancia do banco" nao se aplica.
import 'dart:async';

import 'package:drift/drift.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
