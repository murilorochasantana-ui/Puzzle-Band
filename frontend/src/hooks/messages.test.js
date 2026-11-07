// Testes do protocolo MQTT (node:test). Rode com: npm test
//   pulseira -> app e painel: estado, alertas, historico (origem "pulseira")
//   app e painel -> pulseira: avaliacao, ack, controle
//   terminal (npm run resetar) -> pulseira, app e site: comando (e a resposta do app)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BAND_ORIGIN,
  RESET_ACTION,
  SITE_ORIGIN,
  parseAck,
  parseAlert,
  parseAppStatus,
  parseBandStatus,
  parseCommandResponse,
  parseControl,
  parseEvaluation,
  parseHistory,
  parseResetCommand,
  parseState,
} from './parseMessages.js';
import {
  HISTORY_TOPIC_LIMIT,
  averageBpm,
  buildAlertMessage,
  buildControlMessage,
  buildEvaluationMessage,
  buildHistoryMessage,
  buildResetCommand,
  buildStateMessage,
  historyEntryToEpisode,
  historySignature,
  protocolSource,
  topicsFor,
} from './buildMessages.js';
import { CONTROL_MIN_INTERVAL_MS, createThrottle } from './throttle.js';
import { CALM_CONTROL } from '../model/simulate.js';

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
  crianca: 'C01',
  fonte: 'pulseira',
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
  assert.equal(t.controle, 'puzzleband/C01/controle');
  assert.equal(t.appStatus, 'puzzleband/C01/app/status');
  assert.equal(t.comando, 'puzzleband/C01/comando');
  assert.equal(t.comandoResposta, 'puzzleband/C01/comando/resposta');
});

// ---------- terminal (npm run resetar) -> pulseira, app e site ----------

test('comando resetar: ida e volta, com e sem manter as preferencias', () => {
  const ts = '2026-11-07T14:00:00.000Z';
  const manter = buildResetCommand({ id: 'a1b2', timestamp: ts, manterPreferencias: true });
  assert.deepEqual(manter, { acao: RESET_ACTION, id: 'a1b2', timestamp: ts, manter_preferencias: true });
  assert.deepEqual(parseResetCommand(JSON.stringify(manter)), manter);

  const tudo = parseResetCommand(JSON.stringify(buildResetCommand({ id: 'c3', timestamp: ts, manterPreferencias: false })));
  assert.equal(tudo.manter_preferencias, false);
});

test('comando resetar: invalido vira null; sem manter_preferencias vale true', () => {
  assert.equal(parseResetCommand(''), null, 'retido apagado (payload vazio)');
  assert.equal(parseResetCommand('quebrado'), null);
  assert.equal(parseResetCommand('{"acao":"reiniciar","id":"x"}'), null, 'outra acao');
  assert.equal(parseResetCommand('{"acao":"resetar"}'), null, 'sem id');
  assert.equal(parseResetCommand('{"acao":"resetar","id":"  "}'), null);
  const semCampo = parseResetCommand('{"acao":"resetar","id":" x ","timestamp":"ontem"}');
  assert.deepEqual(semCampo, { acao: 'resetar', id: 'x', timestamp: null, manter_preferencias: true });
  assert.equal(parseResetCommand('{"acao":"resetar","id":"x","manter_preferencias":"nao"}').manter_preferencias, true);
});

test('resposta do app ao comando', () => {
  assert.deepEqual(parseCommandResponse('{"id":"a1b2","status":"aplicado"}'), { id: 'a1b2', status: 'aplicado' });
  assert.equal(parseCommandResponse('{"status":"aplicado"}'), null);
  assert.equal(parseCommandResponse('{"id":"a1b2"}'), null);
  assert.equal(parseCommandResponse(''), null);
});

test('historico: a origem vem junto (so a da pulseira vale para o app e para a recuperacao)', () => {
  const daPulseira = parseHistory(JSON.stringify(buildHistoryMessage([], { childId: 'C01', timestamp: '2026-11-07T14:00:00.000Z' })));
  assert.equal(daPulseira.origem, BAND_ORIGIN);
  assert.deepEqual(daPulseira.episodios, []);
  assert.equal(parseHistory('{"origem":"site","episodios":[]}').origem, SITE_ORIGIN);
  assert.equal(parseHistory('{"episodios":[]}').origem, null);
});

// ---------- app e painel -> pulseira ----------

test('avaliacao do app: valida', () => {
  const msg = parseEvaluation(JSON.stringify({
    episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'sirene', origem: 'app', timestamp: '2026-11-04T12:05:00Z',
  }));
  assert.deepEqual(msg, {
    episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'sirene', origem: 'app', timestamp: '2026-11-04T12:05:00Z',
  });
});

test('avaliacao: observacao opcional, sem origem vale "app", timestamp invalido vira null, observacao limitada', () => {
  const noObs = parseEvaluation('{"episodio_id":"ep_1","avaliacao":"descartado"}');
  assert.equal(noObs.avaliacao, 'descartado');
  assert.equal(noObs.origem, 'app');
  assert.equal('observacao' in noObs, false);
  assert.equal(noObs.timestamp, null);
  const long = parseEvaluation(JSON.stringify({ episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'x'.repeat(500) }));
  assert.equal(long.observacao.length, 200);
});

test('avaliacao do painel do site: origem "site" aceita, e "pendente" desfaz', () => {
  const site = parseEvaluation(JSON.stringify(buildEvaluationMessage({
    episodioId: 'ep_1', avaliacao: 'confirmado', observacao: 'porta bateu', timestamp: '2026-11-04T12:06:00.000Z',
  })));
  assert.deepEqual(site, {
    episodio_id: 'ep_1', avaliacao: 'confirmado', observacao: 'porta bateu', origem: SITE_ORIGIN, timestamp: '2026-11-04T12:06:00.000Z',
  });
  const undo = parseEvaluation(JSON.stringify(buildEvaluationMessage({ episodioId: 'ep_1', avaliacao: 'pendente', timestamp: 't' })));
  assert.equal(undo.avaliacao, 'pendente');
  assert.equal(undo.origem, SITE_ORIGIN);
  assert.equal('observacao' in undo, false);
});

test('mensagem do site: mesmo formato que o app usa (so muda a origem)', () => {
  const msg = buildEvaluationMessage({ episodioId: 'ep_1', avaliacao: 'descartado', observacao: '', timestamp: 't' });
  assert.deepEqual(Object.keys(msg), ['episodio_id', 'avaliacao', 'observacao', 'origem', 'timestamp']);
});

test('avaliacao malformada ou de origem desconhecida e descartada sem excecao', () => {
  for (const text of [
    'nao e json',
    'null',
    '[]',
    '"texto"',
    '{"avaliacao":"confirmado"}',
    '{"episodio_id":"","avaliacao":"confirmado"}',
    '{"episodio_id":"ep_1","avaliacao":"talvez"}',
    '{"episodio_id":"ep_1","avaliacao":"confirmado","observacao":42}',
    `{"episodio_id":"ep_1","avaliacao":"confirmado","origem":"${BAND_ORIGIN}"}`,
    '{"episodio_id":"ep_1","avaliacao":"confirmado","origem":"outro"}',
  ]) {
    assert.equal(parseEvaluation(text), null, text);
  }
});

test('ack do app', () => {
  assert.deepEqual(parseAck('{"episodio_id":"ep_1","timestamp":"2026-11-04T12:01:00Z","origem":"app"}'), {
    episodio_id: 'ep_1', timestamp: '2026-11-04T12:01:00Z',
  });
  assert.equal(parseAck('{"episodio_id":"ep_1"}').timestamp, null);
  assert.equal(parseAck('{"timestamp":"2026-11-04T12:01:00Z"}'), null);
  assert.equal(parseAck('{{'), null);
  assert.equal(parseAck(`{"episodio_id":"ep_1","origem":"${BAND_ORIGIN}"}`), null);
});

test('controle: mensagem do painel ida e volta, faixas validadas campo a campo', () => {
  const msg = buildControlMessage({ ...CALM_CONTROL, bpm: 140, extra: 1, ruido: Number.NaN }, { timestamp: 't' });
  assert.equal(msg.origem, SITE_ORIGIN);
  assert.equal('extra' in msg, false);
  assert.equal('ruido' in msg, false);
  const parsed = parseControl(JSON.stringify(msg));
  assert.deepEqual(parsed.valores, { bpm: 140, eda: 4, hrv: 55, movimento: 5, regularidade: 0.08, luz: 300, idade: 8 });
  assert.deepEqual(parsed.ignorados, []);
  const bad = parseControl('{"bpm":300,"eda":"4","idade":7.5,"luz":1000}');
  assert.deepEqual(bad.valores, { luz: 1000 });
  assert.deepEqual(bad.ignorados, ['bpm', 'eda', 'idade']);
  assert.equal(parseControl('nao e json'), null);
});

// ---------- pulseira -> app e painel ----------

test('status online/offline da pulseira e do app', () => {
  assert.equal(parseBandStatus('online'), 'online');
  assert.equal(parseAppStatus(' OFFLINE \n'), 'offline');
  assert.equal(parseAppStatus('{"status":"online"}'), null);
});

test('estado: pulseira no modo controle ("manual") sem episodio', () => {
  const msg = buildStateMessage({
    timestamp: '2026-11-04T12:00:01Z',
    source: 'manual',
    childId: 'C01',
    tier: 'baixo_risco',
    probability: 0.12345,
    readings: [reading(70), reading(80)],
    openEpisode: null,
  });
  assert.equal(msg.origem, BAND_ORIGIN);
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

test('estado: pulseira em cenario com episodio em andamento e buffer vazio', () => {
  const ep = episode('ep_9', { visto_pelo_cuidador_em: '2026-11-04T12:00:20Z' });
  const msg = buildStateMessage({
    timestamp: 'x', source: 'pulseira', childId: 'C01', tier: 'atencao', probability: null, readings: [], openEpisode: ep,
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

test('fonte no protocolo: "pulseira" (e o nome antigo "mqtt") ou "manual"', () => {
  assert.equal(protocolSource('pulseira'), 'pulseira');
  assert.equal(protocolSource('mqtt'), 'pulseira');
  assert.equal(protocolSource('manual'), 'manual');
});

test('painel le o estado publicado pela pulseira', () => {
  const ep = episode('ep_9', { visto_pelo_cuidador_em: '2026-11-04T12:00:20.000Z' });
  const sent = buildStateMessage({
    timestamp: '2026-11-04T12:00:21.000Z', source: 'pulseira', childId: 'C01', tier: 'alto_risco', probability: 0.9, readings: [reading(130)], openEpisode: ep,
  });
  const got = parseState(JSON.stringify(sent));
  assert.equal(got.nivel, 'alto_risco');
  assert.equal(got.probabilidade, 0.9);
  assert.equal(got.fonte, 'pulseira');
  assert.deepEqual(got.gatilho, { tipo: 'ruido', texto: gatilho.texto });
  assert.equal(got.episodio.id, 'ep_9');
  assert.equal(got.episodio.visto_pelo_cuidador_em, '2026-11-04T12:00:20.000Z');
  // sem nivel valido (o app tambem descarta) ou malformado: null
  assert.equal(parseState('{"nivel":"nenhum"}'), null);
  assert.equal(parseState('[]'), null);
  assert.equal(parseState('{"nivel":"atencao","episodio":{"id":""}}').episodio, null);
});

test('media de BPM ignora valores invalidos', () => {
  assert.equal(averageBpm([{ bpm: 70 }, { bpm: Number.NaN }, {}, { bpm: 81 }]), 75.5);
  assert.equal(averageBpm([]), null);
});

test('alerta: nivel anterior, objeto completo do gatilho e origem', () => {
  const msg = buildAlertMessage(
    { timestamp: '2026-11-04T12:00:05Z', nivel_anterior: 'baixo_risco', nivel: 'alto_risco', probabilidade: 0.81, leituras: reading(120), episodio_id: 'ep_1', gatilho },
    { source: 'pulseira', childId: 'C01' },
  );
  assert.equal(msg.origem, BAND_ORIGIN);
  assert.equal(msg.fonte, 'pulseira');
  assert.equal(msg.episodio_id, 'ep_1');
  assert.equal(msg.nivel_anterior, 'baixo_risco');
  assert.equal(msg.nivel, 'alto_risco');
  assert.equal(msg.probabilidade, 0.81);
  assert.deepEqual(msg.gatilho, gatilho);
  const got = parseAlert(JSON.stringify(msg));
  assert.equal(got.nivel, 'alto_risco');
  assert.equal(got.episodio_id, 'ep_1');
  assert.deepEqual(got.gatilho, { tipo: 'ruido', texto: gatilho.texto });
  assert.equal(parseAlert('{"nivel":1}'), null);
});

test(`historico: no maximo ${HISTORY_TOPIC_LIMIT} episodios, gatilho resumido e fonte do protocolo`, () => {
  const episodes = Array.from({ length: 60 }, (_, i) => episode(`ep_${i}`, { fonte: i % 2 ? 'pulseira' : 'manual' }));
  const msg = buildHistoryMessage(episodes, { childId: 'C01', timestamp: 't' });
  assert.equal(msg.origem, BAND_ORIGIN);
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

test('historico: painel e pulseira (recuperacao) leem o que a pulseira publicou', () => {
  const list = [
    episode('ep_2', { avaliacao_cuidador: 'confirmado', avaliacao_origem: 'app', avaliacao_em: '2026-11-04T12:10:00.000Z', observacao: 'sirene' }),
    episode('ep_1', { fonte: 'manual', encerramento: 'normalizou', fim: '2026-11-04T12:01:00.000Z' }),
  ];
  const text = JSON.stringify(buildHistoryMessage(list, { childId: 'C01', timestamp: '2026-11-04T12:11:00.000Z' }));
  const got = parseHistory(text);
  assert.equal(got.total, 2);
  assert.deepEqual(got.episodios.map((e) => e.id), ['ep_2', 'ep_1']);
  assert.equal(got.episodios[0].avaliacao_cuidador, 'confirmado');
  assert.equal(got.episodios[0].observacao, 'sirene');

  const ep = historyEntryToEpisode(got.episodios[1]);
  assert.equal(ep.fonte, 'manual');
  assert.equal(ep.ultima_leitura, '2026-11-04T12:01:00.000Z');
  assert.equal(historyEntryToEpisode(got.episodios[0]).fonte, 'pulseira');

  // episodio sem id/inicio/nivel valido e pulado (como no app); lista ausente: null
  const mixed = parseHistory(JSON.stringify({ episodios: [{ id: 'x' }, got.episodios[0], 7] }));
  assert.deepEqual(mixed.episodios.map((e) => e.id), ['ep_2']);
  assert.equal(parseHistory('{"total":3}'), null);
});

test('assinatura do historico: muda ao abrir, fechar e avaliar, mas nao com a duracao', () => {
  const open = [episode('ep_1')];
  const base = historySignature(open);
  assert.equal(historySignature([{ ...open[0], duracao_s: 99 }]), base, 'duracao nao republica');
  assert.notEqual(historySignature([episode('ep_2'), ...open]), base, 'episodio novo');
  assert.notEqual(historySignature([{ ...open[0], encerramento: 'normalizou' }]), base, 'episodio fechado');
  assert.notEqual(historySignature([{ ...open[0], avaliacao_cuidador: 'confirmado' }]), base, 'avaliado');
  assert.notEqual(historySignature([{ ...open[0], avaliacao_em: 'outro' }]), base, 'reavaliado');
  assert.notEqual(historySignature([{ ...open[0], visto_pelo_cuidador_em: 't' }]), base, 'visto');
  assert.notEqual(historySignature([]), base, 'historico limpo');
});

// ---------- limitacao de frequencia do controle ----------

function fakeClock() {
  let now = 0;
  const timers = [];
  return {
    clock: {
      now: () => now,
      setTimeout: (cb, ms) => {
        const timer = { at: now + ms, cb, done: false };
        timers.push(timer);
        return timer;
      },
      clearTimeout: (timer) => {
        timer.done = true;
      },
    },
    advance(ms) {
      now += ms;
      for (const t of timers) {
        if (!t.done && t.at <= now) {
          t.done = true;
          t.cb();
        }
      }
    },
  };
}

test(`controle: no maximo 1 mensagem a cada ${CONTROL_MIN_INTERVAL_MS} ms, sempre com o ultimo valor`, () => {
  const sent = [];
  const { clock, advance } = fakeClock();
  const throttle = createThrottle((v) => sent.push(v), CONTROL_MIN_INTERVAL_MS, clock);

  throttle.call(80); // primeira mudanca: sai na hora
  assert.deepEqual(sent, [80]);
  for (let bpm = 81; bpm <= 120; bpm += 1) {
    throttle.call(bpm); // arrastando o controle: 40 mudancas em 400 ms
    advance(10);
  }
  assert.deepEqual(sent, [80]); // ainda dentro do intervalo
  advance(100);
  assert.deepEqual(sent, [80, 120]); // uma so, com o ultimo valor

  // 2 s arrastando sem parar (1 mudanca a cada 20 ms): no maximo 2 por segundo
  for (let i = 0; i < 100; i += 1) {
    throttle.call(i);
    advance(20);
  }
  advance(1000);
  assert.ok(sent.length - 2 <= 5, `${sent.length - 2} mensagens em 2 s`);
  assert.equal(sent[sent.length - 1], 99, 'o ultimo valor nunca se perde');

  throttle.call(5); // intervalo ja passou: sai na hora
  throttle.call(6); // fica pendente...
  throttle.cancel(); // ...e o painel fecha
  advance(1000);
  assert.equal(sent[sent.length - 1], 5, 'cancel descarta o pendente');
});
