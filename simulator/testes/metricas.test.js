// Metricas por episodio (antes, durante, recuperacao) e resumo de cada minuto
// (topico resumo_minuto), calculados na pulseira. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEdgeLink, createEdgeProcessor, RESEND_MARGIN_MS } from '../borda.js';
import { historyEntryToEpisode } from '../../frontend/src/hooks/buildMessages.js';
import { parseHistory, parseMinuteSummary } from '../../frontend/src/hooks/parseMessages.js';
import { METRIC_SIGNALS } from '../../frontend/src/model/metricas.js';
import { FakeClient, T0, isoAt } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;

// Leitura sintetica: o nivel vem marcado na propria leitura (classify falso),
// e os 6 sinais seguem `bpm` (os outros = bpm + deslocamento fixo).
function reading(t, tier, bpm) {
  return {
    timestamp: isoAt(t),
    _tier: tier,
    bpm,
    hrv_ms: bpm + 1,
    eda_uS: bpm + 2,
    gyro_mag_dps: bpm + 3,
    luz_lux: bpm + 4,
    ruido_db: bpm + 5,
    regularidade: 0.5,
    accel_mag_g: 1,
    idade: 8,
  };
}

const fakeClassify = (readings, i) => ({ tier: readings[i]._tier, probability: readings[i]._tier === 'baixo_risco' ? 0.1 : 0.8 });

// Sequencia de trechos [n, tier, bpm(i)] -> leituras com t continuo
function* segments(list, start = 0) {
  let t = start;
  for (const [n, tier, bpm] of list) {
    for (let i = 0; i < n; i += 1) {
      yield reading(t, tier, typeof bpm === 'function' ? bpm(i) : bpm);
      t += 1;
    }
  }
}

function run(list, start = 0) {
  const processor = createEdgeProcessor({ childId: CHILD, classify: fakeClassify });
  for (const r of segments(list, start)) processor.ingest(r);
  return processor;
}

const mean = (xs) => xs.reduce((a, b) => a + b, 0) / xs.length;
const r2 = (v) => Math.round(v * 100) / 100;

test('metricas: antes (120 s), durante (com o trecho calmo curto) e recuperacao (30 s calmos finais)', () => {
  const during1 = (i) => 110 + (i % 5); // 110..114
  const processor = run([
    [200, 'baixo_risco', 80], // so as ultimas 120 entram no "antes"
    [40, 'alto_risco', during1],
    [10, 'baixo_risco', 95], // calmo curto: volta para o "durante"
    [5, 'atencao', 130],
    [30, 'baixo_risco', 90], // recuperacao: fecha o episodio
  ]);
  const [ep] = processor.episodes();
  assert.equal(ep.encerramento, 'normalizou');
  const m = ep.metricas;
  assert.deepEqual(Object.keys(m), ['antes', 'durante', 'recuperacao']);

  assert.equal(m.antes.n_leituras, 120);
  assert.deepEqual(m.antes.bpm, { media: 80, n: 120 });
  assert.deepEqual(m.antes.ruido_db, { media: 85, n: 120 });

  const duringValues = [...Array.from({ length: 40 }, (_, i) => during1(i)), ...Array(10).fill(95), ...Array(5).fill(130)];
  assert.equal(m.durante.n_leituras, 55);
  assert.equal(m.durante.n_leituras, ep.duracao_s, 'durante = do inicio ao comeco da calma final');
  assert.deepEqual(m.durante.bpm, { media: r2(mean(duringValues)), min: 95, max: 130, n: 55 });
  assert.deepEqual(m.durante.luz_lux, { media: r2(mean(duringValues) + 4), min: 99, max: 134, n: 55 });

  assert.equal(m.recuperacao.n_leituras, 30);
  assert.deepEqual(m.recuperacao.bpm, { media: 90, n: 30 });
  for (const s of METRIC_SIGNALS) assert.ok(m.antes[s] && m.durante[s] && m.recuperacao[s], s);
});

test('metricas: episodio de mais de 5 min (alem do buffer de 300) soma todas as leituras do durante', () => {
  const bpm = (i) => (i < 100 ? 150 : 120); // o pico fica no comeco: fora do buffer no fim
  const processor = run([[150, 'baixo_risco', 80], [420, 'alto_risco', bpm], [30, 'baixo_risco', 85]]);
  const [ep] = processor.episodes();
  assert.equal(ep.duracao_s, 420);
  assert.equal(processor.readings().length, 300, 'o buffer da pulseira so tem 5 min');
  const m = ep.metricas;
  assert.equal(m.durante.n_leituras, 420);
  assert.equal(m.durante.bpm.max, 150, 'o pico do inicio continua contando');
  assert.equal(m.durante.bpm.min, 120);
  assert.equal(m.durante.bpm.media, r2((100 * 150 + 320 * 120) / 420));
  assert.equal(m.antes.n_leituras, 120);
  assert.equal(m.recuperacao.n_leituras, 30);
});

test('metricas: poucas leituras antes (pulseira acabou de ligar) registra quantas entraram', () => {
  const processor = run([[40, 'baixo_risco', 70], [20, 'atencao', 100], [30, 'baixo_risco', 75]]);
  const [ep] = processor.episodes();
  assert.equal(ep.metricas.antes.n_leituras, 40);
  assert.deepEqual(ep.metricas.antes.bpm, { media: 70, n: 40 });

  // episodio ja na primeira leitura: "antes" vazio, sinais null
  const first = run([[10, 'atencao', 100], [30, 'baixo_risco', 75]]);
  const [ep2] = first.episodes();
  assert.equal(ep2.metricas.antes.n_leituras, 0);
  for (const s of METRIC_SIGNALS) assert.equal(ep2.metricas.antes[s], null);
  assert.equal(ep2.metricas.durante.n_leituras, 10);
});

test('metricas: sinal sem valor (null) fica fora da media e com n proprio', () => {
  const processor = createEdgeProcessor({ childId: CHILD, classify: fakeClassify });
  const list = [...segments([[130, 'baixo_risco', 80], [10, 'atencao', 100], [30, 'baixo_risco', 90]])];
  for (let i = 130; i < 135; i += 1) list[i] = { ...list[i], hrv_ms: null };
  for (const r of list) processor.ingest(r);
  const { durante } = processor.episodes()[0].metricas;
  assert.equal(durante.n_leituras, 10);
  assert.equal(durante.hrv_ms.n, 5);
  assert.equal(durante.bpm.n, 10);
});

test('metricas: episodio interrompido guarda o que havia (recuperacao parcial)', () => {
  const processor = run([[130, 'baixo_risco', 80], [20, 'alto_risco', 120], [12, 'baixo_risco', 90]]);
  const closed = processor.close();
  assert.equal(closed.encerramento, 'interrompido');
  assert.equal(closed.metricas.durante.n_leituras, 20);
  assert.equal(closed.metricas.recuperacao.n_leituras, 12);
});

test('historico: metricas vao no topico, voltam pelo parseHistory e episodio antigo sem elas continua valido', () => {
  const processor = run([[130, 'baixo_risco', 80], [20, 'alto_risco', 120], [30, 'baixo_risco', 90]]);
  const message = processor.history(isoAt(999));
  const entry = message.episodios[0];
  assert.deepEqual(entry.metricas, processor.episodes()[0].metricas);

  const old = { ...entry };
  delete old.metricas;
  const parsed = parseHistory(JSON.stringify({ ...message, episodios: [entry, { ...old, id: 'ep_antigo' }] }));
  assert.equal(parsed.episodios.length, 2);
  assert.deepEqual(parsed.episodios[0].metricas, entry.metricas);
  assert.equal(parsed.episodios[1].metricas, null);
  // recuperacao do historico retido: as metricas voltam para o episodio
  assert.deepEqual(historyEntryToEpisode(parsed.episodios[0]).metricas, entry.metricas);

  // metricas malformadas nao derrubam o episodio
  const bad = parseHistory(JSON.stringify({ ...message, episodios: [{ ...entry, metricas: 'x' }] }));
  assert.equal(bad.episodios.length, 1);
  assert.equal(bad.episodios[0].metricas, null);
});

// ---------------------------------------------------------------------------
// resumo_minuto
// ---------------------------------------------------------------------------

function connected(options = {}) {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD, classify: fakeClassify });
  let nowMs = T0;
  const link = createEdgeLink({ client, processor, clock: () => nowMs, ...options });
  client.connect();
  const step = (r) => {
    nowMs = Date.parse(r.timestamp);
    return link.step(r);
  };
  return { client, processor, link, step };
}

const minutesSent = (client) => client.sent(TOPIC('resumo_minuto')).map((m) => JSON.parse(m.payload));

test('resumo_minuto: um por minuto fechado, QoS 1 sem retain, com medias, n e nivel maximo', () => {
  const { client, step } = connected();
  // T0 e um minuto cheio: 60 calmas, 30 calmas + 30 em atencao, 10 do terceiro minuto
  for (const r of segments([[60, 'baixo_risco', 80], [30, 'baixo_risco', 90], [30, 'atencao', 110], [10, 'baixo_risco', 85]])) step(r);
  const sent = client.sent(TOPIC('resumo_minuto'));
  assert.equal(sent.length, 2, 'o terceiro minuto ainda nao fechou');
  assert.ok(sent.every((m) => m.qos === 1 && !m.retain));
  const [m1, m2] = minutesSent(client);
  assert.deepEqual(Object.keys(m1), ['origem', 'timestamp', 'crianca', 'motivo', 'minutos']);
  assert.equal(m1.origem, 'pulseira');
  assert.equal(m1.motivo, 'minuto');
  assert.equal(m1.minutos.length, 1);
  assert.deepEqual(m1.minutos[0], {
    minuto: isoAt(0),
    nivel_maximo: 'baixo_risco',
    n_leituras: 60,
    bpm: { media: 80, n: 60 },
    hrv_ms: { media: 81, n: 60 },
    eda_uS: { media: 82, n: 60 },
    gyro_mag_dps: { media: 83, n: 60 },
    luz_lux: { media: 84, n: 60 },
    ruido_db: { media: 85, n: 60 },
  });
  assert.equal(m2.minutos[0].minuto, isoAt(60));
  assert.equal(m2.minutos[0].nivel_maximo, 'atencao');
  assert.equal(m2.minutos[0].bpm.media, 100);

  // o parser do app/site aceita a mensagem
  const parsed = parseMinuteSummary(sent[1].payload);
  assert.equal(parsed.minutos[0].n_leituras, 60);
  assert.equal(parseMinuteSummary(JSON.stringify({ ...m2, origem: 'site' })), null, 'so a pulseira publica');
});

test('resumo_minuto: ao desligar, publica o minuto parcial', async () => {
  const { client, link, step } = connected();
  for (const r of segments([[75, 'baixo_risco', 80]])) step(r);
  client.publishAsync = async (topic, payload, options) => client.publish(topic, payload, options);
  await link.close();
  const sent = minutesSent(client);
  assert.equal(sent.length, 2);
  assert.equal(sent[1].minutos[0].n_leituras, 15);
});

test('resumo_minuto: o app cai e volta -> a pulseira reenvia desde a queda (com margem), em lotes', () => {
  const { client, step } = connected();
  client.deliver(TOPIC('app/status'), 'online', { retain: true });
  const calm = (n, start) => [...segments([[n, 'baixo_risco', 80]], start)];
  for (const r of calm(600, 0)) step(r); // 10 min com o app online
  const before = client.sent(TOPIC('resumo_minuto')).length;
  assert.equal(before, 9);

  client.deliver(TOPIC('app/status'), 'offline'); // Last Will ao vivo, no t = 600 s
  for (const r of calm(60 * 60, 600)) step(r); // 1 h com o app fora
  client.deliver(TOPIC('app/status'), 'online');
  const resend = minutesSent(client).filter((m) => m.motivo === 'reenvio');
  assert.equal(resend.length, 1);
  const minutes = resend[0].minutos.map((m) => m.minuto);
  // desde a queda menos a margem de 5 min ate o ultimo minuto fechado: 5..68
  // (o minuto 69 ainda esta aberto)
  assert.equal(minutes[0], isoAt(600 - RESEND_MARGIN_MS / 1000));
  assert.equal(minutes.at(-1), isoAt(68 * 60));
  assert.equal(minutes.length, 64);

  // o "online" repetido (a cada 60 s) nao reenvia de novo
  client.deliver(TOPIC('app/status'), 'online');
  assert.equal(minutesSent(client).filter((m) => m.motivo === 'reenvio').length, 1);
  // payload vazio (o reset apagando o retido) e ignorado
  client.deliver(TOPIC('app/status'), '');
});

test('resumo_minuto: app offline retido ao conectar -> reenvia tudo o que ha (ate 24 h), em lotes de 360', () => {
  const { client, step } = connected();
  client.deliver(TOPIC('app/status'), 'offline', { retain: true });
  for (const r of segments([[25 * 3600, 'baixo_risco', 80]])) step(r); // 25 h
  client.deliver(TOPIC('app/status'), 'online');
  const resend = minutesSent(client).filter((m) => m.motivo === 'reenvio');
  const total = resend.reduce((n, m) => n + m.minutos.length, 0);
  assert.equal(total, 24 * 60, 'so as ultimas 24 h ficam na memoria');
  assert.deepEqual(resend.map((m) => m.minutos.length), [360, 360, 360, 360]);
  const size = Math.max(...client.sent(TOPIC('resumo_minuto')).map((m) => Buffer.byteLength(m.payload)));
  assert.ok(size < 1024 * 1024, `mensagem de ${size} bytes (limite do EMQX Serverless: 1 MB)`);
});

test('resumo_minuto: sem conexao a pulseira guarda e reenvia quando o app aparece online', () => {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD, classify: fakeClassify });
  const link = createEdgeLink({ client, processor });
  client.connect();
  for (const r of segments([[120, 'baixo_risco', 80]])) link.step(r);
  client.disconnect();
  for (const r of segments([[180, 'baixo_risco', 80]], 120)) link.step(r); // 3 min sem broker
  client.connect();
  client.deliver(TOPIC('app/status'), 'online', { retain: true });
  const resend = minutesSent(client).filter((m) => m.motivo === 'reenvio');
  // os minutos que fecharam sem broker (1, 2 e 3); o 4 ainda esta aberto
  assert.deepEqual(resend[0].minutos.map((m) => m.minuto), [isoAt(60), isoAt(120), isoAt(180)]);
});

test('resumo_minuto: a ordem de reset apaga os resumos guardados', () => {
  const { client, processor, step } = connected({ reset: { lastAppliedId: null } });
  client.deliver(TOPIC('comando'), { origem: 'terminal', acao: 'resetar', id: 'r1' }, { retain: true });
  for (const r of segments([[300, 'baixo_risco', 80]])) step(r);
  assert.equal(processor.minutesSince(-Infinity).length, 4);
  client.deliver(TOPIC('comando'), { origem: 'terminal', acao: 'resetar', id: 'r2', timestamp: isoAt(300) });
  assert.equal(processor.minutesSince(-Infinity).length, 0);
});

test('resumo_minuto: desligado pela opcao (minuteSummaries: false) nao publica nem assina app/status', () => {
  const { client, step } = connected({ minuteSummaries: false });
  for (const r of segments([[130, 'baixo_risco', 80]])) step(r);
  assert.equal(client.sent(TOPIC('resumo_minuto')).length, 0);
  assert.ok(!client.subscribed.has(TOPIC('app/status')));
});
