// Testes do protocolo MQTT site <-> app (node:test). Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAck, parseAppStatus, parseBandStatus, parseEvaluation, SITE_ORIGIN } from './parseMessages.js';
import {
  HISTORY_TOPIC_LIMIT,
  averageBpm,
  buildAlertMessage,
  buildHistoryMessage,
  buildStateMessage,
  historySignature,
  topicsFor,
} from './buildMessages.js';

const reading = (bpm, extra = {}) => ({
  timestamp: '2026-11-04T12:00:00.000Z',
  bpm, eda_uS: 4.2, gyro_mag_dps: 5.5, hrv_ms: 55.1, accel_mag_g: 2.1, regularidade: 0.1,
  luz_lux: 300, ruido_db: 45.2, idade: 8, ...extra,
});

const gatilho = {
  tipo: 'ruido',
  texto: 'Provável gatilho: ruído (45 → 88 dB, cerca de 12 s antes da alteração fisiológica).',
  baseline_confiavel: true,
  sinais: { ruido: { status: 'gatilho' }, luminosidade: { status: 'estavel' } },
};

const episode = (id, extra = {}) => ({
  id,
  crianca: 'simulada',
  fonte: 'manual',
  inicio: '2026-11-04T12:00:00.000Z',
  fim: null,
  duracao_s: 12,
  encerramento: null,
  nivel_maximo: 'atencao',
  probabilidade_maxima: 0.62,
  gatilho,
  avaliacao_cuidador: 'pendente',
  observacao: '',
  ultima_leitura: '2026-11-04T12:00:12.000Z',
  ...extra,
});

// ---------- topicos ----------

test('topicos de uma crianca', () => {
  const t = topicsFor('C01');
  assert.equal(t.estado, 'puzzleband/C01/estado');
  assert.equal(t.alertas, 'puzzleband/C01/alertas');
  assert.equal(t.historico, 'puzzleband/C01/historico');
  assert.equal(t.avaliacao, 'puzzleband/C01/avaliacao');
  assert.equal(t.ack, 'puzzleband/C01/ack');
  assert.equal(t.appStatus, 'puzzleband/C01/app/status');
});

// ---------- mensagens recebidas ----------

test('avaliacao do app: valida', () => {
  const msg = parseEvaluation(JSON.stringify({
    episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'sirene', origem: 'app', timestamp: '2026-11-04T12:05:00Z',
  }));
  assert.deepEqual(msg, {
    episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'sirene', origem: 'app', timestamp: '2026-11-04T12:05:00Z',
  });
});

test('avaliacao do app: observacao opcional, timestamp invalido vira null, observacao limitada', () => {
  const noObs = parseEvaluation('{"episodio_id":"ep_1","avaliacao":"descartado","origem":"app"}');
  assert.equal(noObs.avaliacao, 'descartado');
  assert.equal('observacao' in noObs, false);
  assert.equal(noObs.timestamp, null);
  const long = parseEvaluation(JSON.stringify({ episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'x'.repeat(500) }));
  assert.equal(long.observacao.length, 200);
});

test('avaliacao malformada ou do proprio site e descartada sem excecao', () => {
  for (const text of [
    'nao e json',
    'null',
    '[]',
    '"texto"',
    '{"avaliacao":"confirmado"}',
    '{"episodio_id":"","avaliacao":"confirmado"}',
    '{"episodio_id":"ep_1","avaliacao":"talvez"}',
    '{"episodio_id":"ep_1","avaliacao":"pendente"}',
    '{"episodio_id":"ep_1","avaliacao":"confirmado","observacao":42}',
    `{"episodio_id":"ep_1","avaliacao":"confirmado","origem":"${SITE_ORIGIN}"}`,
  ]) {
    assert.equal(parseEvaluation(text), null, text);
  }
});

test('ack do app', () => {
  assert.deepEqual(parseAck('{"episodio_id":"ep_1","timestamp":"2026-11-04T12:01:00Z"}'), {
    episodio_id: 'ep_1', timestamp: '2026-11-04T12:01:00Z',
  });
  assert.equal(parseAck('{"episodio_id":"ep_1"}').timestamp, null);
  assert.equal(parseAck('{"timestamp":"2026-11-04T12:01:00Z"}'), null);
  assert.equal(parseAck('{{'), null);
  assert.equal(parseAck(`{"episodio_id":"ep_1","origem":"${SITE_ORIGIN}"}`), null);
});

test('status online/offline da pulseira e do app', () => {
  assert.equal(parseBandStatus('online'), 'online');
  assert.equal(parseAppStatus(' OFFLINE \n'), 'offline');
  assert.equal(parseAppStatus('{"status":"online"}'), null);
});

// ---------- mensagens publicadas ----------

test('estado: modo manual sem episodio', () => {
  const msg = buildStateMessage({
    timestamp: '2026-11-04T12:00:01Z',
    source: 'manual',
    childId: 'C01',
    tier: 'baixo_risco',
    probability: 0.12345,
    readings: [reading(70), reading(80)],
    openEpisode: null,
  });
  assert.equal(msg.origem, SITE_ORIGIN);
  assert.equal(msg.fonte, 'manual');
  assert.equal(msg.crianca, 'C01');
  assert.equal(msg.nivel, 'baixo_risco');
  assert.equal(msg.probabilidade, 0.123);
  assert.equal(msg.media_bpm_5min, 75);
  assert.equal(msg.gatilho, null);
  assert.equal(msg.episodio, null);
  assert.deepEqual(Object.keys(msg.leituras).sort(), [
    'bpm', 'eda_uS', 'gyro_mag_dps', 'hrv_ms', 'luz_lux', 'regularidade', 'ruido_db', 'timestamp',
  ]);
  assert.equal(msg.leituras.bpm, 80);
});

test('estado: modo pulseira com episodio em andamento e buffer vazio', () => {
  const ep = episode('ep_9', { visto_pelo_cuidador_em: '2026-11-04T12:00:20Z' });
  const msg = buildStateMessage({
    timestamp: 'x', source: 'mqtt', childId: 'C01', tier: 'atencao', probability: null, readings: [], openEpisode: ep,
  });
  assert.equal(msg.fonte, 'pulseira');
  assert.equal(msg.probabilidade, null);
  assert.equal(msg.leituras, null);
  assert.equal(msg.media_bpm_5min, null);
  assert.deepEqual(msg.gatilho, { tipo: 'ruido', texto: gatilho.texto });
  assert.deepEqual(msg.episodio, {
    id: 'ep_9', inicio: ep.inicio, nivel_maximo: 'atencao', visto_pelo_cuidador_em: '2026-11-04T12:00:20Z',
  });
});

test('media de BPM ignora valores invalidos', () => {
  assert.equal(averageBpm([{ bpm: 70 }, { bpm: Number.NaN }, {}, { bpm: 81 }]), 75.5);
  assert.equal(averageBpm([]), null);
});

test('alerta: nivel anterior, objeto completo do gatilho e origem', () => {
  const msg = buildAlertMessage(
    { timestamp: 't', nivel_anterior: 'baixo_risco', nivel: 'alto_risco', probabilidade: 0.81, leituras: reading(120), episodio_id: 'ep_1', gatilho },
    { source: 'manual', childId: 'C01' },
  );
  assert.equal(msg.origem, SITE_ORIGIN);
  assert.equal(msg.fonte, 'manual');
  assert.equal(msg.episodio_id, 'ep_1');
  assert.equal(msg.nivel_anterior, 'baixo_risco');
  assert.equal(msg.nivel, 'alto_risco');
  assert.equal(msg.probabilidade, 0.81);
  assert.deepEqual(msg.gatilho, gatilho);
});

test(`historico: no maximo ${HISTORY_TOPIC_LIMIT} episodios, gatilho resumido e fonte do protocolo`, () => {
  const episodes = Array.from({ length: 60 }, (_, i) => episode(`ep_${i}`, { fonte: i % 2 ? 'mqtt' : 'manual' }));
  const msg = buildHistoryMessage(episodes, { childId: 'C01', timestamp: 't' });
  assert.equal(msg.origem, SITE_ORIGIN);
  assert.equal(msg.total, 60);
  assert.equal(msg.episodios.length, HISTORY_TOPIC_LIMIT);
  assert.equal(msg.episodios[0].id, 'ep_0');
  assert.equal(msg.episodios[0].fonte, 'manual');
  assert.equal(msg.episodios[1].fonte, 'pulseira');
  assert.deepEqual(msg.episodios[0].gatilho, { tipo: 'ruido', texto: gatilho.texto });
  assert.equal(msg.episodios[0].encerramento, null);
  assert.equal(msg.episodios[0].avaliacao_origem, null);
  assert.equal(msg.episodios[0].visto_pelo_cuidador_em, null);
  assert.equal('ultima_leitura' in msg.episodios[0], false);
});

test('assinatura do historico: muda ao abrir, fechar e avaliar, mas nao com a duracao', () => {
  const open = [episode('ep_1')];
  const base = historySignature(open);
  assert.equal(historySignature([{ ...open[0], duracao_s: 99 }]), base, 'duracao nao republica');
  assert.notEqual(historySignature([episode('ep_2'), ...open]), base, 'episodio novo');
  assert.notEqual(historySignature([{ ...open[0], encerramento: 'normalizou' }]), base, 'episodio fechado');
  assert.notEqual(historySignature([{ ...open[0], avaliacao_cuidador: 'confirmado' }]), base, 'avaliado');
  assert.notEqual(historySignature([{ ...open[0], avaliacao_em: 'outro' }]), base, 'reavaliado pelo app');
  assert.notEqual(historySignature([{ ...open[0], visto_pelo_cuidador_em: 't' }]), base, 'visto');
  assert.notEqual(historySignature([]), base, 'historico limpo');
});
