// Testes do historico de episodios (node:test). Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CSV_COLUMNS,
  EPISODE_END_CALM_S,
  HISTORY_LIMIT,
  HISTORY_STORAGE_KEY,
  closeOpenEpisode,
  createEpisodeStore,
  createMonitor,
  episodesToCsv,
  ingestReadings,
  loadEpisodes,
  saveEpisodes,
  stepMonitor,
  summarizeByChild,
  updateEpisode,
  upsertEpisode,
} from './episodes.js';

const T0 = Date.parse('2026-11-02T13:00:00Z');
const PROB = { baixo_risco: 0.1, atencao: 0.5, alto_risco: 0.85 };

const reading = (t) => ({
  timestamp: new Date(T0 + t * 1000).toISOString(),
  bpm: 80, eda_uS: 4, gyro_mag_dps: 5, hrv_ms: 55, accel_mag_g: 2, regularidade: 0.1,
  luz_lux: 300, ruido_db: 45, idade: 8,
});

// Roda o rastreador sobre uma sequencia de niveis, ex.: [['baixo_risco', 40], ['atencao', 20]]
function run(segments, monitor = createMonitor({ childId: 'simulada', source: 'manual' })) {
  let list = [];
  let state = monitor;
  const tierChanges = [];
  for (const [tier, seconds, prob] of segments) {
    for (let i = 0; i < seconds; i += 1) {
      const step = stepMonitor(state, { reading: reading(state.nextT), tier, probability: prob ?? PROB[tier] });
      state = step.monitor;
      if (step.episode) list = upsertEpisode(list, step.episode);
      if (step.tierChange) tierChanges.push(step.tierChange);
    }
  }
  return { list, monitor: state, tierChanges };
}

test('queda curta para baixo_risco (< 30 s) nao parte o episodio (histerese)', () => {
  const { list, monitor } = run([
    ['baixo_risco', 40],
    ['atencao', 20],
    ['baixo_risco', 10],
    ['alto_risco', 15, 0.91],
    ['baixo_risco', EPISODE_END_CALM_S],
  ]);
  assert.equal(list.length, 1);
  const [ep] = list;
  assert.equal(ep.encerramento, 'normalizou');
  assert.equal(ep.nivel_maximo, 'alto_risco');
  assert.equal(ep.probabilidade_maxima, 0.91);
  assert.equal(ep.duracao_s, 45); // de t=40 ate voltar ao normal em t=85
  assert.equal(ep.inicio, reading(40).timestamp);
  assert.equal(ep.fim, reading(85).timestamp);
  assert.equal(ep.crianca, 'simulada');
  assert.equal(ep.fonte, 'manual');
  assert.equal(ep.avaliacao_cuidador, 'pendente');
  assert.ok(ep.gatilho && ep.gatilho.tipo, 'gatilho calculado no inicio');
  assert.equal(monitor.open, null);
});

test('30 s calmos fecham o episodio; o proximo alerta abre outro', () => {
  const { list } = run([
    ['baixo_risco', 40],
    ['atencao', 20],
    ['baixo_risco', EPISODE_END_CALM_S],
    ['atencao', 10],
  ]);
  assert.equal(list.length, 2);
  assert.equal(list[0].encerramento, null); // o mais recente ainda em andamento
  assert.equal(list[1].encerramento, 'normalizou');
});

test('episodio em andamento: 29 s calmos ainda nao encerram', () => {
  const { list } = run([['baixo_risco', 40], ['atencao', 20], ['baixo_risco', EPISODE_END_CALM_S - 1]]);
  assert.equal(list[0].encerramento, null);
  assert.equal(list[0].fim, null);
});

test('mudancas de nivel sao reportadas (base da publicacao MQTT)', () => {
  const { tierChanges } = run([['baixo_risco', 35], ['atencao', 5], ['alto_risco', 5], ['atencao', 5]]);
  assert.deepEqual(tierChanges.map((c) => c.para), ['atencao', 'alto_risco', 'atencao']);
});

test('monitoramento interrompido fecha o episodio como "interrompido"', () => {
  const { monitor } = run([['baixo_risco', 40], ['atencao', 12]]);
  const closed = closeOpenEpisode(monitor);
  assert.equal(closed.encerramento, 'interrompido');
  assert.equal(closed.fim, reading(51).timestamp);
  assert.equal(closeOpenEpisode(createMonitor({ source: 'manual' })), null);
});

test('atualizacao do rastreador preserva avaliacao e observacao do cuidador', () => {
  const first = run([['baixo_risco', 40], ['atencao', 5]]);
  let list = updateEpisode(first.list, first.list[0].id, { avaliacao_cuidador: 'confirmado', observacao: 'sirene' });
  const step = stepMonitor(first.monitor, { reading: reading(45), tier: 'atencao', probability: 0.6 });
  list = upsertEpisode(list, step.episode);
  assert.equal(list[0].avaliacao_cuidador, 'confirmado');
  assert.equal(list[0].observacao, 'sirene');
  assert.equal(list[0].probabilidade_maxima, 0.6);
});

test('avaliacao invalida vira "pendente" e observacao e limitada', () => {
  const list = [{ id: 'a', inicio: reading(0).timestamp }];
  assert.equal(updateEpisode(list, 'a', { avaliacao_cuidador: 'talvez' })[0].avaliacao_cuidador, 'pendente');
  assert.equal(updateEpisode(list, 'a', { observacao: 'x'.repeat(500) })[0].observacao.length, 200);
});

test(`historico limitado a ${HISTORY_LIMIT} episodios (mais recente primeiro)`, () => {
  let list = [];
  for (let i = 0; i < HISTORY_LIMIT + 15; i += 1) {
    list = upsertEpisode(list, { id: `ep${i}`, inicio: reading(i).timestamp });
  }
  assert.equal(list.length, HISTORY_LIMIT);
  assert.equal(list[0].id, `ep${HISTORY_LIMIT + 14}`);
});

function memoryStorage(initial = {}) {
  const data = { ...initial };
  return {
    data,
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => {
      data[k] = String(v);
    },
  };
}

test('persistencia: ida e volta pelo storage, episodio aberto vira "interrompido" ao recarregar', () => {
  const storage = memoryStorage();
  const { list } = run([['baixo_risco', 40], ['atencao', 10]]);
  assert.equal(saveEpisodes(storage, list), true);
  assert.ok(storage.data[HISTORY_STORAGE_KEY]);

  const { episodes, ok } = loadEpisodes(storage);
  assert.equal(ok, true);
  assert.equal(episodes.length, 1);
  assert.equal(episodes[0].encerramento, 'interrompido');
  assert.equal(episodes[0].fim, reading(49).timestamp);
});

test('persistencia: falhas de leitura/escrita nao lancam excecao', () => {
  const broken = {
    getItem: () => {
      throw new Error('SecurityError');
    },
    setItem: () => {
      throw new Error('QuotaExceededError');
    },
  };
  assert.deepEqual(loadEpisodes(broken), { episodes: [], ok: false });
  assert.equal(saveEpisodes(broken, []), false);
  assert.deepEqual(loadEpisodes(null), { episodes: [], ok: false });
  assert.deepEqual(loadEpisodes(memoryStorage({ [HISTORY_STORAGE_KEY]: '{corrompido' })), { episodes: [], ok: false });
  // entradas invalidas sao descartadas
  const mixed = memoryStorage({ [HISTORY_STORAGE_KEY]: JSON.stringify([null, { id: 1 }, { id: 'ok', inicio: reading(0).timestamp }]) });
  assert.equal(loadEpisodes(mixed).episodes.length, 1);
});

test('store: grava a cada atualizacao e segue em memoria se o storage falhar', () => {
  const storage = memoryStorage();
  const store = createEpisodeStore(storage);
  let notified = 0;
  const unsubscribe = store.subscribe(() => {
    notified += 1;
  });
  store.update((list) => upsertEpisode(list, { id: 'a', inicio: reading(0).timestamp }));
  assert.equal(notified, 1);
  assert.equal(store.getSnapshot().storageOk, true);
  assert.equal(JSON.parse(storage.data[HISTORY_STORAGE_KEY]).length, 1);
  store.update((list) => list); // sem mudanca: nao notifica nem grava
  assert.equal(notified, 1);
  unsubscribe();

  const full = { getItem: () => null, setItem: () => { throw new Error('QuotaExceededError'); } };
  const memoryOnly = createEpisodeStore(full);
  memoryOnly.update((list) => upsertEpisode(list, { id: 'b', inicio: reading(0).timestamp }));
  assert.equal(memoryOnly.getSnapshot().storageOk, false);
  assert.equal(memoryOnly.getSnapshot().episodes.length, 1);
});

// ---------- ingestReadings (o que o hook do dashboard chama a cada render) ----------

// Classificador falso: "alerta" quando o BPM passa de 100
const fakeClassify = (readings, i) => (readings[i].bpm > 100
  ? { tier: 'atencao', probability: 0.6 }
  : { tier: 'baixo_risco', probability: 0.1 });
const bpmAt = (t) => (t >= 60 && t < 90 ? 120 : 80); // um episodio de 30 s
const series = (n) => Array.from({ length: n }, (_, t) => ({ ...reading(t), bpm: bpmAt(t) }));

// Simula o buffer do App.jsx: cresce de `batch` em `batch` e e cortado em 300
function feed(readings, batch, maxBuffer = 300) {
  let monitor = createMonitor({ childId: 'C01', source: 'mqtt' });
  let last = null;
  let list = [];
  let buffer = [];
  const alerts = [];
  for (let i = 0; i < readings.length; i += batch) {
    buffer = [...buffer, ...readings.slice(i, i + batch)].slice(-maxBuffer);
    const r = ingestReadings(monitor, last, buffer, fakeClassify);
    monitor = r.monitor;
    last = r.lastReading;
    r.changed.forEach((ep) => {
      list = upsertEpisode(list, ep);
    });
    alerts.push(...r.alerts);
  }
  return { monitor, last, list, alerts };
}

test('ingestReadings: lotes de 1, 4 ou tudo de uma vez dao o mesmo resultado', () => {
  const readings = series(200);
  const one = feed(readings, 1);
  const four = feed(readings, 4);
  const all = feed(readings, 200);
  for (const r of [one, four, all]) {
    assert.equal(r.list.length, 1);
    assert.equal(r.list[0].duracao_s, 30);
    assert.equal(r.list[0].encerramento, 'normalizou');
    assert.equal(r.list[0].crianca, 'C01');
    assert.equal(r.list[0].fonte, 'mqtt');
    assert.equal(r.alerts.length, 1);
    assert.equal(r.alerts[0].episodio_id, r.list[0].id);
    assert.ok(r.alerts[0].gatilho);
    assert.equal(r.monitor.nextT, 200);
  }
});

test('ingestReadings: buffer deslizante (corte em 300) nao perde nem repete leituras', () => {
  const r = feed(series(450), 3);
  assert.equal(r.monitor.nextT, 450);
  assert.equal(r.list.length, 1);
});

test('ingestReadings: buffer esvaziado ou trocado fecha o episodio como interrompido', () => {
  const readings = series(70); // termina no meio do episodio (60-89)
  const r = feed(readings, 1);
  const cleared = ingestReadings(r.monitor, r.last, [], fakeClassify);
  assert.equal(cleared.lastReading, null);
  assert.equal(cleared.changed.length, 1);
  assert.equal(cleared.changed[0].encerramento, 'interrompido');
  assert.equal(cleared.monitor.open, null);
  assert.equal(cleared.monitor.nextT, 0);

  const replaced = ingestReadings(r.monitor, r.last, [reading(0)], fakeClassify);
  assert.equal(replaced.changed[0].encerramento, 'interrompido');
  assert.equal(replaced.monitor.nextT, 1);

  // nada novo: nada muda
  const same = ingestReadings(r.monitor, r.last, readings, fakeClassify);
  assert.equal(same.monitor, r.monitor);
  assert.equal(same.changed.length, 0);
});

const fakeEpisode = (id, crianca, tipo, avaliacao, duracao = 60) => ({
  id, crianca, fonte: 'manual', inicio: reading(0).timestamp, fim: reading(duracao).timestamp, duracao_s: duracao,
  encerramento: 'normalizou', nivel_maximo: 'alto_risco', probabilidade_maxima: 0.873,
  gatilho: { tipo, texto: `texto ${tipo}`, baseline_confiavel: true, fisiologia: { sinal: 'bpm' }, sinais: {} },
  avaliacao_cuidador: avaliacao, observacao: '',
});

test('resumo de padroes por crianca', () => {
  const episodes = [
    fakeEpisode('1', 'C01', 'ruido', 'confirmado', 60),
    fakeEpisode('2', 'C01', 'ruido', 'pendente', 120),
    fakeEpisode('3', 'C01', 'ruido_e_luminosidade', 'confirmado', 90),
    fakeEpisode('4', 'C01', 'nenhum_ambiental', 'descartado', 30),
    fakeEpisode('5', 'simulada', 'luminosidade', 'pendente', 45),
  ];
  const [c01, sim] = summarizeByChild(episodes);
  assert.equal(c01.crianca, 'C01');
  assert.equal(c01.total, 4);
  assert.equal(c01.duracao_media_s, 75);
  assert.deepEqual(c01.gatilhos.ruido, { total: 3, confirmados: 2 });
  assert.deepEqual(c01.gatilhos.luminosidade, { total: 1, confirmados: 1 });
  assert.deepEqual(c01.gatilhos.nenhum_ambiental, { total: 1, confirmados: 0 });
  assert.deepEqual(c01.avaliacao, { confirmado: 2, descartado: 1, pendente: 1 });
  assert.equal(sim.total, 1);
});

test('CSV: BOM, separador ";", virgula decimal e texto escapado', () => {
  const ep = fakeEpisode('1', 'C01', 'ruido', 'confirmado');
  ep.observacao = '=SOMA(A1); "sirene"';
  const csv = episodesToCsv([ep]);
  assert.ok(csv.startsWith('﻿'));
  const [header, row] = csv.slice(1).trim().split('\r\n');
  assert.equal(header, CSV_COLUMNS.join(';'));
  assert.ok(row.includes(';0,873;'));
  assert.ok(row.endsWith(`"'=SOMA(A1); ""sirene"""`));
});
