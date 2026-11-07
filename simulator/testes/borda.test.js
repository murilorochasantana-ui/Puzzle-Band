// Pulseira com processamento na borda (borda.js), SEM o site: publica
// estado, alertas e historico e aplica ack e avaliacao. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createEdgeLink, createEdgeProcessor } from '../borda.js';
import { calmTargets } from '../scenarios.js';
import { FakeClient, calmTicks, isoAt, nominalTicks, runTicks } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;

// Campos que o app le (mobile/lib/models/models.dart, docs/mqtt.md): o
// formato tem de continuar EXATAMENTE este.
const STATE_KEYS = ['origem', 'timestamp', 'fonte', 'crianca', 'nivel', 'probabilidade', 'leituras', 'media_bpm_5min', 'gatilho', 'episodio'];
const ALERT_KEYS = ['origem', 'timestamp', 'fonte', 'crianca', 'episodio_id', 'nivel_anterior', 'nivel', 'probabilidade', 'gatilho', 'leituras'];
const HISTORY_KEYS = ['origem', 'timestamp', 'crianca', 'total', 'episodios'];
const ENTRY_KEYS = [
  'id', 'crianca', 'fonte', 'inicio', 'fim', 'duracao_s', 'encerramento', 'nivel_maximo', 'probabilidade_maxima',
  'gatilho', 'avaliacao_cuidador', 'observacao', 'avaliacao_origem', 'avaliacao_em', 'visto_pelo_cuidador_em',
];

// crise_ruido nominal + 60 s calmos: um episodio, fechado, gatilho "ruido"
function runCrisis(onReading, seed = 1) {
  let n = runTicks(nominalTicks('crise_ruido', seed), seed, onReading);
  n += runTicks(calmTicks(60, calmTargets()), seed + 1000, onReading, { offset: n });
  return n;
}

function connectedLink(options = {}) {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD, source: 'pulseira', ...options.processor });
  const link = createEdgeLink({ client, processor, ...options.link });
  client.connect();
  return { client, processor, link };
}

test('processador: crise_ruido abre e fecha um episodio, com gatilho e alerta no formato do app', () => {
  const processor = createEdgeProcessor({ childId: CHILD, source: 'pulseira' });
  const alerts = [];
  runCrisis((reading) => alerts.push(...processor.ingest(reading).alerts));

  const episodes = processor.episodes();
  assert.equal(episodes.length, 1);
  const [ep] = episodes;
  assert.equal(ep.encerramento, 'normalizou');
  assert.equal(ep.gatilho.tipo, 'ruido');

  assert.ok(alerts.length >= 1);
  assert.deepEqual(Object.keys(alerts[0]), ALERT_KEYS);
  assert.equal(alerts[0].origem, 'pulseira');
  assert.equal(alerts[0].fonte, 'pulseira');
  assert.equal(alerts[0].crianca, CHILD);
  assert.equal(alerts[0].episodio_id, ep.id);
  assert.equal(alerts[0].gatilho.tipo, 'ruido'); // objeto completo do gatilho no alerta
  assert.ok(alerts[0].gatilho.sinais);

  const state = processor.state(isoAt(999));
  assert.deepEqual(Object.keys(state), STATE_KEYS);
  assert.equal(state.origem, 'pulseira');
  assert.equal(state.nivel, 'baixo_risco');
  assert.equal(state.episodio, null);

  const history = processor.history(isoAt(999));
  assert.deepEqual(Object.keys(history), HISTORY_KEYS);
  assert.deepEqual(Object.keys(history.episodios[0]), ENTRY_KEYS);
  assert.deepEqual(history.episodios[0].gatilho, { tipo: 'ruido', texto: ep.gatilho.texto }); // resumido
});

test('sem o site: a pulseira publica leituras, estado (1x por leitura, retain), alertas (QoS 1) e historico (retain)', () => {
  const { client: c, link } = connectedLink();
  // assina so os comandos (fora do modo controle, nem o controle)
  assert.deepEqual([...c.subscribed].sort(), [TOPIC('ack'), TOPIC('avaliacao')]);
  // historico publicado ja na conexao (retain: o app recebe ao abrir)
  assert.equal(c.sent(TOPIC('historico')).length, 1);

  const n = runCrisis((reading) => link.step(reading));

  const leituras = c.sent(TOPIC('leituras'));
  const estados = c.sent(TOPIC('estado'));
  assert.equal(leituras.length, n);
  assert.equal(estados.length, n);
  assert.ok(estados.every((m) => m.retain && m.qos === 0));
  assert.ok(leituras.every((m) => !m.retain && m.qos === 0));

  const alertas = c.sent(TOPIC('alertas'));
  assert.ok(alertas.length >= 1);
  assert.ok(alertas.every((m) => m.qos === 1 && !m.retain));
  const primeiro = JSON.parse(alertas[0].payload);
  assert.ok(['atencao', 'alto_risco'].includes(primeiro.nivel));
  assert.equal(primeiro.nivel_anterior, 'baixo_risco');

  // historico: na conexao, quando o episodio abre, quando muda e quando fecha -
  // mas nao a cada segundo
  const historicos = c.sent(TOPIC('historico'));
  assert.ok(historicos.every((m) => m.retain && m.qos === 1));
  assert.ok(historicos.length >= 3 && historicos.length < 20, `${historicos.length} publicações de historico`);
  const final = c.lastJson(TOPIC('historico'));
  assert.equal(final.episodios.length, 1);
  assert.equal(final.episodios[0].encerramento, 'normalizou');
  assert.equal(final.origem, 'pulseira');

  // durante o episodio, o estado leva o episodio em andamento e o gatilho resumido
  const comEpisodio = estados.map((m) => JSON.parse(m.payload)).find((s) => s.episodio);
  assert.equal(comEpisodio.episodio.id, final.episodios[0].id);
  assert.equal(comEpisodio.gatilho.tipo, 'ruido');

  // a pulseira nunca publica nos topicos de comando
  for (const t of ['ack', 'avaliacao', 'controle', 'app/status']) assert.equal(c.sent(TOPIC(t)).length, 0);
});

test('sem conexao a pulseira segue processando e republica o historico ao reconectar', () => {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD });
  const link = createEdgeLink({ client, processor });
  runCrisis((reading) => link.step(reading)); // nunca conectou
  assert.equal(client.published.length, 0);
  assert.equal(processor.episodes().length, 1);
  client.connect();
  assert.equal(client.lastJson(TOPIC('historico')).episodios.length, 1);
});

test('aplica ack e avaliacao (app e site) e republica o historico', () => {
  const { client, processor, link } = connectedLink();
  let ackSentAt = null;
  let n = 0;
  // Roda ate o primeiro alerta e manda o "Estou ciente" com o episodio aberto
  runCrisis((reading) => {
    link.step(reading);
    n += 1;
    if (!ackSentAt && client.sent(TOPIC('alertas')).length) {
      ackSentAt = isoAt(n);
      const id = processor.openEpisode().id;
      client.deliver(TOPIC('ack'), { episodio_id: id, timestamp: ackSentAt, origem: 'app' });
    }
  });
  const id = processor.episodes()[0].id;
  // o estado seguinte ja levou o "visto pelo cuidador" (banner do site e do app)
  const estados = client.sent(TOPIC('estado')).map((m) => JSON.parse(m.payload));
  assert.ok(estados.some((s) => s.episodio?.visto_pelo_cuidador_em === ackSentAt));

  const historyAfter = (message, topic) => {
    const before = client.sent(TOPIC('historico')).length;
    client.deliver(TOPIC(topic), message);
    const list = client.sent(TOPIC('historico'));
    assert.equal(list.length, before + 1, `historico republicado depois de ${topic}`);
    return JSON.parse(list[list.length - 1].payload).episodios[0];
  };

  let ep = historyAfter({ episodio_id: id, avaliacao: 'confirmado', observacao: 'sirene', origem: 'app', timestamp: isoAt(2000) }, 'avaliacao');
  assert.equal(ep.visto_pelo_cuidador_em, ackSentAt);
  assert.equal(ep.avaliacao_cuidador, 'confirmado');
  assert.equal(ep.avaliacao_origem, 'app');
  assert.equal(ep.avaliacao_em, isoAt(2000));
  assert.equal(ep.observacao, 'sirene');

  ep = historyAfter({ episodio_id: id, avaliacao: 'descartado', origem: 'site', timestamp: isoAt(2001) }, 'avaliacao');
  assert.equal(ep.avaliacao_cuidador, 'descartado');
  assert.equal(ep.avaliacao_origem, 'site');
  assert.equal(ep.observacao, 'sirene'); // sem observacao na mensagem: mantem

  ep = historyAfter({ episodio_id: id, avaliacao: 'pendente', origem: 'site', timestamp: isoAt(2002) }, 'avaliacao');
  assert.equal(ep.avaliacao_cuidador, 'pendente'); // o site desfez

  // episodio desconhecido: nada muda, mas o historico e republicado (quem mandou se corrige)
  ep = historyAfter({ episodio_id: 'ep_nao_existe', avaliacao: 'confirmado', origem: 'app' }, 'avaliacao');
  assert.equal(ep.avaliacao_cuidador, 'pendente');
  historyAfter({ episodio_id: 'ep_nao_existe', origem: 'app' }, 'ack');

  // malformadas (ou eco da propria pulseira): ignoradas, sem republicar
  const before = client.sent(TOPIC('historico')).length;
  client.deliver(TOPIC('avaliacao'), 'isto nao e json');
  client.deliver(TOPIC('avaliacao'), { episodio_id: id, avaliacao: 'talvez', origem: 'app' });
  client.deliver(TOPIC('avaliacao'), { episodio_id: id, avaliacao: 'confirmado', origem: 'pulseira' });
  client.deliver(TOPIC('ack'), { timestamp: isoAt(1) });
  assert.equal(client.sent(TOPIC('historico')).length, before);
  assert.equal(processor.episodes()[0].avaliacao_cuidador, 'pendente');
});

test('ao desligar: fecha o episodio aberto como interrompido e publica o historico final', async () => {
  const { client, processor, link } = connectedLink();
  let alerted = false;
  runCrisis((reading) => {
    if (alerted) return; // "desliga" logo depois do primeiro alerta
    link.step(reading);
    alerted = client.sent(TOPIC('alertas')).length > 0;
  });
  assert.ok(processor.openEpisode());
  const closed = await link.close();
  assert.equal(closed.encerramento, 'interrompido');
  const final = client.lastJson(TOPIC('historico'));
  assert.equal(final.episodios[0].id, closed.id);
  assert.equal(final.episodios[0].encerramento, 'interrompido');
});
