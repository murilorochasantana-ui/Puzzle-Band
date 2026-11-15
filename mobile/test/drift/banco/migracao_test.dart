// Migracoes do esquema do banco local (lib/services/banco.dart), com o
// esquema de cada versao salvo em drift_schemas/banco/ e os ajudantes em
// generated/ (dart run drift_dev make-migrations, a cada versao nova).
//
// Hoje so existe a v1. Ao criar a v2: subir schemaVersion, escrever o passo
// em onUpgrade, rodar make-migrations e acrescentar aqui um teste
// "v1 -> v2" (verifier.startAt(1) + migrateAndValidate(db, 2)), conferindo
// tambem que os dados da v1 continuam (verifier.schemaAt(1) + insert).
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/services/banco.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('o esquema criado pelo app e igual ao salvo para a versao atual', () async {
    final banco = BancoPuzzleBand.emMemoria();
    addTearDown(banco.close);
    await banco.validateDatabaseSchema();
    expect(banco.schemaVersion, GeneratedHelper.versions.last);
  });

  test('abrir um banco que ja esta na v1 (abertura seguinte) nao muda nada', () async {
    final conexao = await verifier.startAt(1);
    final banco = BancoPuzzleBand(conexao);
    addTearDown(banco.close);
    await verifier.migrateAndValidate(banco, 1);
  });

  test('versao do esquema gravada no arquivo (user_version)', () async {
    final banco = BancoPuzzleBand.emMemoria();
    addTearDown(banco.close);
    final versao = await banco.customSelect('PRAGMA user_version').getSingle();
    expect(versao.read<int>('user_version'), 1);
  });
}
