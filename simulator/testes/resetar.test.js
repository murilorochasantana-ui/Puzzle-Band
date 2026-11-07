// Reset para uma apresentacao (npm run resetar, resetar.js) com um cliente
// MQTT falso: nada vai para o broker de verdade. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildHistoryMessage } from '../../frontend/src/hooks/buildMessages.js';
import { historyFilePath, lastResetPath } from '../historico.js';
import { parseCli, runReset } from '../resetar.js';
import { checkLock, createLock, lockPath } from '../trava.js';
import { FakeClient } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;
const RETIDOS = ['estado', 'historico', 'status', 'app/status'].map(TOPIC);
const silent = { log() {}, error() {} };

// data/ com o historico (e uma copia corrompida e a ultima ordem aplicada) e
// logs/ com um gabarito
function workspace(t) {
  const root = mkdtempSync(join(tmpdir(), 'puzzleband-resetar-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const paths = { data: join(root, 'data'), logs: join(root, 'logs') };
  mkdirSync(paths.data);
  mkdirSync(paths.logs);
  const ep = { id: 'ep_1', inicio: '2026-11-06T10:00:00.000Z', fim: '2026-11-06T10:02:00.000Z', encerramento: 'normalizou' };
  writeFileSync(historyFilePath(paths.data, CHILD), JSON.stringify([ep]));
  writeFileSync(join(paths.data, `historico_${CHILD}.corrompido-2026-11-05.json`), '{ quebrado');
  writeFileSync(join(paths.data, 'historico_C05.json'), '[]'); // outra crianca: fica
  writeFileSync(lastResetPath(paths.data, CHILD), '{"id":"antiga"}');
  writeFileSync(join(paths.logs, 'eventos_2026-11-06_10-00-00.csv'), 'numero;tipo\r\n');
  return paths;
}

// Broker com o historico de 1 episodio e a pulseira offline; o "app" responde
// a ordem na hora (como o celular aberto)
function broker({ status = 'offline', appResponde = true, deny = [] } = {}) {
  const historico = buildHistoryMessage([{ id: 'ep_1', inicio: '2026-11-06T10:00:00.000Z' }], { childId: CHILD, timestamp: '2026-11-06T10:05:00.000Z' });
  const client = new FakeClient({
    retained: { [TOPIC('status')]: status, [TOPIC('historico')]: JSON.stringify(historico) },
    deny,
  });
  client.connected = true;
  client.onPublish = ({ topic, payload }) => {
    if (topic !== TOPIC('comando') || !appResponde) return;
    const { id } = JSON.parse(payload);
    setImmediate(() => client.deliver(TOPIC('comando/resposta'), { id, status: 'aplicado' }));
  };
  return client;
}

const run = (client, paths, options, extra = {}) => runReset({
  client,
  childId: CHILD,
  options: { tudo: false, sim: true, simular: false, forcar: false, ...options },
  paths,
  out: silent,
  id: 'ordem-1',
  isAlive: () => false,
  retainedTimeoutMs: 40,
  responseTimeoutMs: 400,
  ...extra,
});

test('apaga o historico, limpa os retidos, publica a lista vazia e a ordem; o app confirma', async (t) => {
  const paths = workspace(t);
  const client = broker();
  const outcome = await run(client, paths, {});

  assert.equal(outcome.estado, 'executado');
  assert.equal(outcome.result.app, 'limpo');
  assert.deepEqual(readdirSync(paths.data).sort(), ['historico_C05.json', `reset_${CHILD}.json`],
    'só o histórico desta criança sai (a última ordem aplicada fica)');
  assert.equal(readdirSync(paths.logs).length, 1, 'sem --tudo, os logs ficam');

  const sent = client.published;
  assert.deepEqual(sent.slice(0, 4).map((m) => [m.topic, m.payload, m.qos, m.retain]),
    RETIDOS.map((topic) => [topic, '', 1, true]), 'payload vazio + retain apaga o retido');
  const vazio = JSON.parse(sent[4].payload);
  assert.equal(sent[4].topic, TOPIC('historico'));
  assert.ok(sent[4].retain);
  assert.deepEqual(vazio.episodios, []);
  assert.equal(vazio.origem, 'pulseira', 'o app só aceita histórico da pulseira');

  assert.equal(sent[5].topic, TOPIC('comando'));
  assert.equal(sent[5].qos, 1);
  assert.ok(sent[5].retain, 'a ordem fica retida para quem estiver desligado');
  const ordem = JSON.parse(sent[5].payload);
  assert.deepEqual({ ...ordem, timestamp: 'x' }, { acao: 'resetar', id: 'ordem-1', timestamp: 'x', manter_preferencias: true });
  assert.ok(!Number.isNaN(Date.parse(ordem.timestamp)));
  assert.equal(sent.length, 6);
  assert.ok(client.subscribed.has(TOPIC('comando/resposta')), 'assinou a resposta antes de publicar a ordem');
});

test('--tudo: também apaga os logs e manda manter_preferencias false; app desligado = sem resposta', async (t) => {
  const paths = workspace(t);
  const client = broker({ appResponde: false });
  const outcome = await run(client, paths, { tudo: true }, { responseTimeoutMs: 30 });

  assert.equal(outcome.estado, 'executado');
  assert.equal(outcome.result.app, 'sem_resposta');
  assert.deepEqual(readdirSync(paths.logs), []);
  assert.equal(client.lastJson(TOPIC('comando')).manter_preferencias, false);
});

test('recusa com a pulseira online (status retido): nada é apagado nem publicado', async (t) => {
  const paths = workspace(t);
  const client = broker({ status: 'online' });
  const outcome = await run(client, paths, {});

  assert.equal(outcome.estado, 'recusado');
  assert.match(outcome.motivos.join(), /online/);
  assert.ok(existsSync(historyFilePath(paths.data, CHILD)));
  assert.deepEqual(client.published, []);
});

test('recusa com a trava de uma pulseira viva; trava velha não bloqueia; --forcar segue', async (t) => {
  const paths = workspace(t);
  createLock(paths.data, CHILD, { cenario: 'demo' }, { pid: 4242 });

  const viva = await run(broker(), paths, {}, { isAlive: (pid) => pid === 4242 });
  assert.equal(viva.estado, 'recusado');
  assert.match(viva.motivos.join(), /PID 4242/);
  assert.ok(existsSync(historyFilePath(paths.data, CHILD)));

  const forcado = await run(broker(), paths, { forcar: true }, { isAlive: () => true });
  assert.equal(forcado.estado, 'executado');
  assert.equal(existsSync(historyFilePath(paths.data, CHILD)), false);

  const velha = await run(broker(), workspace(t), {}, { isAlive: () => false });
  assert.equal(velha.estado, 'executado', 'processo morto (queda): a trava não vale');
});

test('--simular só mostra: não apaga nem publica nada', async (t) => {
  const paths = workspace(t);
  const client = broker();
  const lines = [];
  const outcome = await run(client, paths, { simular: true, tudo: true }, { out: { log: (l) => lines.push(l), error: (l) => lines.push(l) } });

  assert.equal(outcome.estado, 'simulado');
  assert.ok(existsSync(historyFilePath(paths.data, CHILD)));
  assert.equal(readdirSync(paths.logs).length, 1);
  assert.deepEqual(client.published, []);
  const text = lines.join('\n');
  assert.match(text, /historico_C01\.json/);
  assert.match(text, /1 episódio/);
  assert.match(text, /nada foi apagado/);
});

test('sem digitar RESETAR: cancela sem apagar nada', async (t) => {
  const paths = workspace(t);
  const client = broker();
  let perguntou = false;
  const outcome = await run(client, paths, { sim: false }, {
    ask: async () => {
      perguntou = true;
      return false;
    },
  });
  assert.ok(perguntou);
  assert.equal(outcome.estado, 'cancelado');
  assert.ok(existsSync(historyFilePath(paths.data, CHILD)));
  assert.deepEqual(client.published, []);
});

test('ACL recusa publicar em app/status: para ali e diz o que já foi feito', async (t) => {
  const paths = workspace(t);
  const client = broker({ deny: [TOPIC('app/status')] });
  const outcome = await run(client, paths, {});

  assert.equal(outcome.estado, 'erro');
  assert.match(outcome.result.erro, /app\/status/);
  assert.deepEqual(outcome.result.retidosLimpos, RETIDOS.slice(0, 3));
  assert.equal(client.sent(TOPIC('comando')).length, 0, 'a ordem não sai depois de um erro');
});

test('argumentos: --id validado, opções booleanas', () => {
  assert.deepEqual(parseCli(['--tudo', '--sim', '--id', 'C05']), {
    id: 'C05', tudo: true, sim: true, simular: false, forcar: false, ajuda: false,
  });
  assert.equal(parseCli([]).id, null);
  assert.throws(() => parseCli(['--id', 'a/b']), /--id inválido/);
  assert.throws(() => parseCli(['--apagar']), /argumento inválido/);
});

test('trava da pulseira: criada, reconhecida e removida só pelo dono', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'puzzleband-trava-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  assert.equal(checkLock(dir, CHILD).estado, 'livre');

  const trava = createLock(dir, CHILD, { cenario: 'demo' });
  assert.equal(trava.anterior.estado, 'livre');
  assert.equal(checkLock(dir, CHILD).estado, 'ativa', 'o PID deste processo está vivo');
  assert.equal(checkLock(dir, CHILD, { isAlive: () => false }).estado, 'velha');

  const outra = createLock(dir, CHILD, {}, { pid: 999999 }); // outra pulseira sobrescreveu
  assert.equal(outra.anterior.estado, 'ativa');
  assert.equal(trava.remove(), false, 'não apaga a trava de outro processo');
  assert.ok(existsSync(lockPath(dir, CHILD)));
  assert.equal(outra.remove(), true);
  assert.equal(checkLock(dir, CHILD).estado, 'livre');
});
