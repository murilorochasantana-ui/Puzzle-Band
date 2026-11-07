// Modo controle remoto (controle.js): validacao da mensagem, rampa e
// leituras seguindo os valores-alvo do painel. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEdgeLink, createEdgeProcessor } from '../borda.js';
import { RAMPA_CONTROLE_S, controlTicks, createControl } from '../controle.js';
import { parseControl } from '../../frontend/src/hooks/parseMessages.js';
import { CALM_CONTROL } from '../../frontend/src/model/simulate.js';
import { FakeClient, runTicks } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;
const mean = (list) => list.reduce((a, b) => a + b, 0) / list.length;

// Leva o generator de ticks por `n` leituras (controlTicks nao tem fim)
function* take(gen, n) {
  for (let i = 0; i < n; i += 1) yield gen.next().value;
}

function controlLink() {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD, source: 'manual' });
  const control = createControl();
  const link = createEdgeLink({ client, processor, control });
  client.connect();
  const ticks = controlTicks(control);
  const readings = [];
  let offset = 0;
  const run = (n, seed = 7) => {
    runTicks(take(ticks, n), seed + offset, (r) => {
      readings.push(r);
      link.step(r);
    }, { offset });
    offset += n;
  };
  return { client, processor, control, link, readings, run };
}

test('controle: valida campo a campo e ignora valores fora da faixa', () => {
  const msg = parseControl(JSON.stringify({
    bpm: 135, eda: 9.5, hrv: 500, movimento: -1, regularidade: 0.8, luz: 'muita', ruido: 88, idade: 7.5,
    origem: 'site', extra: 1,
  }));
  assert.deepEqual(msg.valores, { bpm: 135, eda: 9.5, regularidade: 0.8, ruido: 88 });
  assert.deepEqual(msg.ignorados, ['hrv', 'movimento', 'luz', 'idade']);
  assert.deepEqual(parseControl('{}'), { valores: {}, ignorados: [] });
  assert.equal(parseControl('nao e json'), null);
  assert.equal(parseControl('[1,2]'), null);
  assert.deepEqual(parseControl(JSON.stringify({ bpm: 50, idade: 12 })).valores, { bpm: 50, idade: 12 }); // limites valem
  assert.deepEqual(parseControl(JSON.stringify({ bpm: Number.NaN, eda: null })).ignorados, ['bpm', 'eda']);
});

test('controle: cada sinal vai ao novo alvo numa rampa de 20 s; a idade muda na hora', () => {
  const control = createControl();
  assert.deepEqual(control.next(), { ...CALM_CONTROL }); // sem comando: calmo
  control.set({ bpm: 138, idade: 10 });
  const values = [];
  for (let i = 0; i <= RAMPA_CONTROLE_S; i += 1) values.push(control.next());
  assert.equal(values[0].bpm, 78); // a rampa comeca no valor atual
  assert.equal(values[10].bpm, 108); // metade do caminho
  assert.equal(values[RAMPA_CONTROLE_S].bpm, 138);
  assert.ok(values.every((v) => v.idade === 10));
  assert.ok(values.every((v, i) => i === 0 || v.bpm >= values[i - 1].bpm), 'sobe sem saltos');

  // novo comando no meio da rampa: parte de onde esta
  const c2 = createControl();
  c2.next();
  c2.set({ ruido: 85 });
  for (let i = 0; i < 10; i += 1) c2.next();
  c2.set({ ruido: 45 });
  assert.equal(c2.next().ruido, 65);
});

test('modo controle: assina controle e as leituras seguem os valores-alvo (com o mesmo ruido)', () => {
  const { client, processor, readings, run } = controlLink();
  assert.ok(client.subscribed.has(TOPIC('controle')));

  run(40); // sem comando: calmo
  const calmas = readings.slice(-20);
  assert.ok(Math.abs(mean(calmas.map((r) => r.bpm)) - CALM_CONTROL.bpm) < 2);
  assert.ok(Math.abs(mean(calmas.map((r) => r.ruido_db)) - CALM_CONTROL.ruido) < 2);

  client.deliver(TOPIC('controle'), { bpm: 120, eda: 8, ruido: 85, luz: 5000, origem: 'site' }); // luz fora da faixa
  run(RAMPA_CONTROLE_S + 30);
  const depois = readings.slice(-25);
  assert.ok(Math.abs(mean(depois.map((r) => r.bpm)) - 120) < 2, 'bpm no alvo');
  assert.ok(Math.abs(mean(depois.map((r) => r.eda_uS)) - 8) < 0.3, 'eda no alvo');
  assert.ok(Math.abs(mean(depois.map((r) => r.ruido_db)) - 85) < 2, 'ruido no alvo');
  assert.ok(Math.abs(mean(depois.map((r) => r.luz_lux)) - CALM_CONTROL.luz) < 15, 'luz fora da faixa foi ignorada');
  // mesmo ruido de sensor do gerador: as leituras variam em torno do alvo
  assert.ok(new Set(depois.map((r) => r.bpm)).size > 1);

  // transicao suave: nenhum salto grande de um segundo para o outro na subida
  const subida = readings.slice(40, 40 + RAMPA_CONTROLE_S);
  assert.ok(subida.every((r, i) => i === 0 || Math.abs(r.bpm - subida[i - 1].bpm) <= 7));

  // o estado sai como "manual" (o app mostra "Simulador manual")
  assert.equal(client.lastJson(TOPIC('estado')).fonte, 'manual');
  assert.equal(processor.source, 'manual');

  // mensagem invalida: ignorada, o controle segue onde estava
  client.deliver(TOPIC('controle'), 'nao e json');
  run(10);
  assert.ok(Math.abs(mean(readings.slice(-10).map((r) => r.bpm)) - 120) < 3);
});

test('modo controle: uma crise feita pelo painel vira alerta e episodio, sem o site processar nada', () => {
  const { client, processor, run } = controlLink();
  run(150); // linha de base calma para o gatilho
  client.deliver(TOPIC('controle'), { ruido: 88 });
  run(15); // ruido sobe antes da fisiologia
  client.deliver(TOPIC('controle'), { bpm: 135, eda: 11, hrv: 25 });
  run(90);
  const alertas = client.sent(TOPIC('alertas')).map((m) => JSON.parse(m.payload));
  assert.ok(alertas.length >= 1, 'publicou alerta');
  assert.equal(alertas[0].fonte, 'manual');
  const ep = processor.openEpisode();
  assert.ok(ep, 'episodio em andamento');
  assert.equal(client.lastJson(TOPIC('historico')).episodios[0].id, ep.id);
});
