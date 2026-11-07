// Cenarios de ponta a ponta com o modelo real (ver cenarios.mjs). Rodam
// junto com "npm test"; para o relatorio completo: node scripts/cenarios.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SCENARIOS, runScenario } from './cenarios.mjs';

const SEEDS = 10;

for (const [name, scenario] of Object.entries(SCENARIOS)) {
  test(`cenario ${name} -> ${scenario.esperado} (${SEEDS} sementes)`, () => {
    for (let seed = 1; seed <= SEEDS; seed += 1) {
      const result = runScenario(name, seed);
      assert.equal(result.episodes.length, 1, `semente ${seed}: um unico episodio`);
      assert.equal(result.episode.encerramento, 'normalizou', `semente ${seed}: episodio encerrado`);
      assert.equal(result.episode.gatilho.tipo, scenario.esperado, `semente ${seed}: ${result.episode.gatilho.texto}`);
    }
  });
}

test('crise_ruido processado em lotes de 4 leituras da o mesmo resultado', () => {
  for (let seed = 1; seed <= 5; seed += 1) {
    const result = runScenario('crise_ruido', seed, { speed: 4 });
    assert.equal(result.episodes.length, 1);
    assert.equal(result.episode.gatilho.tipo, 'ruido');
  }
});

test('alerta MQTT leva o gatilho do episodio', () => {
  const { alerts, episode } = runScenario('crise_ruido', 1);
  assert.ok(alerts.length >= 1);
  const [first] = alerts;
  assert.ok(['atencao', 'alto_risco'].includes(first.nivel));
  assert.equal(first.episodio_id, episode.id);
  assert.equal(first.gatilho.tipo, 'ruido');
  assert.ok(first.leituras && Number.isFinite(first.probabilidade));
});

test('ruido_depois: o ruido aparece como possivel consequencia', () => {
  const { episode } = runScenario('ruido_depois', 1);
  assert.equal(episode.gatilho.sinais.ruido.status, 'possivel_consequencia');
  assert.ok(episode.gatilho.sinais.ruido.antecedencia_s <= -20);
});
