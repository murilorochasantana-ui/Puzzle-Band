// Migracoes do esquema do banco local (lib/services/banco.dart), com o
// esquema de cada versao salvo em drift_schemas/banco/ e os ajudantes em
// generated/ (dart run drift_dev make-migrations, a cada versao nova).
//
//   v1: episodios, lembretes, episodios_notificados;
//   v2: + episodio_metricas e resumo_minuto (relatorio em Excel).
//
// Ao criar a v3: subir schemaVersion, escrever o passo em onUpgrade, rodar
// make-migrations e acrescentar aqui o teste "v2 -> v3", conferindo que os
// dados da v2 continuam.
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/metricas.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/banco.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  int us(DateTime d) => d.microsecondsSinceEpoch;
  final inicio = DateTime.utc(2026, 11, 20, 14, 30);
  final agora = DateTime.utc(2026, 11, 25, 12);

  test('o esquema criado pelo app e igual ao salvo para a versao atual (v2)', () async {
    final banco = BancoPuzzleBand.emMemoria();
    addTearDown(banco.close);
    await banco.validateDatabaseSchema();
    expect(banco.schemaVersion, 2);
    expect(GeneratedHelper.versions, [1, 2]);
  });

  test('v1 -> v2: o esquema migrado e igual ao de um banco novo na v2', () async {
    final conexao = await verifier.startAt(1);
    final banco = BancoPuzzleBand(conexao);
    addTearDown(banco.close);
    await verifier.migrateAndValidate(banco, 2);
  });

  test('v1 -> v2 nao perde dados: episodios (com avaliacao local), lembretes e notificados continuam', () async {
    final v1 = await verifier.schemaAt(1);
    v1.rawDatabase
      ..execute(
        'INSERT INTO episodios (id, crianca, fonte, inicio, fim, duracao_s, encerramento, nivel_maximo, '
        'probabilidade_maxima, gatilho_tipo, gatilho_texto, avaliacao, observacao, avaliacao_origem, avaliacao_em, '
        'visto_em, recebido_em, na_pulseira, avaliacao_local, observacao_local, avaliacao_local_em) '
        "VALUES ('ep_1', 'C01', 'pulseira', ?, ?, 102, 'normalizou', 'alto_risco', 0.874, 'ruido', "
        "'Provável gatilho: ruído', 'confirmado', 'sirene', 'site', ?, ?, ?, 0, 'descartado', 'nao foi', ?)",
        [
          us(inicio),
          us(inicio.add(const Duration(seconds: 102))),
          us(inicio.add(const Duration(minutes: 5))),
          us(inicio.add(const Duration(minutes: 1))),
          us(agora),
          us(inicio.add(const Duration(minutes: 10))),
        ],
      )
      ..execute(
        "INSERT INTO lembretes (chave, texto, salvo_em, avisar_em) VALUES ('episodio:ep_1', 'levar o fone', ?, NULL)",
        [us(agora)],
      )
      ..execute(
        'INSERT INTO episodios_notificados (episodio_id, nivel, par_de_canais, notificado_em, vezes) '
        "VALUES ('ep_1', 'alto_risco', 'ignora_nao_perturbe', ?, 2)",
        [us(inicio)],
      );

    final banco = BancoPuzzleBand(v1.newConnection());
    addTearDown(banco.close);
    await verifier.migrateAndValidate(banco, 2);

    final ep = await banco.episodio('ep_1');
    expect(ep, isNotNull);
    expect(ep!.inicio, inicio.toLocal());
    expect(ep.duracaoS, 102);
    expect(ep.nivelMaximo, NivelRisco.altoRisco);
    expect(ep.gatilho?.tipo, 'ruido');
    expect(ep.naPulseira, isFalse);
    // avaliacao local pendente de confirmacao continua valendo
    expect(ep.avaliacao, Avaliacao.descartado);
    expect(ep.observacao, 'nao foi');
    expect((await banco.lembretesSalvos())['episodio:ep_1']?.texto, 'levar o fone');
    final notificados = await banco.notificados();
    expect(notificados['ep_1']?.nivel, NivelRisco.altoRisco);
    expect(notificados['ep_1']?.ignoraNaoPerturbe, isTrue);

    // tabelas novas vazias e prontas para uso
    expect(await banco.metricasDe(['ep_1']), isEmpty);
    expect(await banco.resumosEntre(DateTime.utc(2000), DateTime.utc(2100)), isEmpty);
    await banco.gravarResumos([
      ResumoDoMinuto(
        minuto: DateTime.utc(2026, 11, 25, 11, 59),
        nivelMaximo: NivelRisco.atencao,
        nLeituras: 60,
        sinais: const {Sinal.bpm: (media: 101.5, n: 60)},
      ),
    ], agora);
    expect((await banco.resumosEntre(DateTime.utc(2000), DateTime.utc(2100))).single.sinais[Sinal.bpm]?.media, 101.5);

    final versao = await banco.customSelect('PRAGMA user_version').getSingle();
    expect(versao.read<int>('user_version'), 2);
  });

  test('v1 -> v2 com as tabelas novas ja criadas pela outra conexao (app e servico) nao falha', () async {
    final v1 = await verifier.schemaAt(1);
    // a outra conexao criou as tabelas e ainda nao gravou a versao
    final v2 = await verifier.schemaAt(2);
    for (final linha in v2.rawDatabase.select(
      "SELECT sql FROM sqlite_master WHERE name IN ('episodio_metricas', 'resumo_minuto') AND sql IS NOT NULL",
    )) {
      v1.rawDatabase.execute(linha['sql'] as String);
    }
    v2.rawDatabase.close();
    final banco = BancoPuzzleBand(v1.newConnection());
    addTearDown(banco.close);
    await verifier.migrateAndValidate(banco, 2);
  });

  test('abrir um banco que ja esta na v2 (abertura seguinte) nao muda nada', () async {
    final conexao = await verifier.startAt(2);
    final banco = BancoPuzzleBand(conexao);
    addTearDown(banco.close);
    await verifier.migrateAndValidate(banco, 2);
  });

  test('versao do esquema gravada no arquivo (user_version)', () async {
    final banco = BancoPuzzleBand.emMemoria();
    addTearDown(banco.close);
    final versao = await banco.customSelect('PRAGMA user_version').getSingle();
    expect(versao.read<int>('user_version'), 2);
  });
}
