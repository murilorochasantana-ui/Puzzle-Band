// Pulseira e a ordem de reset (puzzleband/<id>/comando, publicada pelo
// npm run resetar): na partida e com a pulseira rodando. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildHistoryMessage, buildResetCommand } from '../../frontend/src/hooks/buildMessages.js';
import { createEdgeLink, createEdgeProcessor } from '../borda.js';
import { historyFilePath, openHistoryFile, readLastReset, saveLastReset } from '../historico.js';
import { calmTargets } from '../scenarios.js';
import { FakeClient, calmTicks, runTicks } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;
const EPISODIOS = [
  { id: 'ep_2', inicio: '2026-11-06T11:00:00.000Z', fim: '2026-11-06T11:01:00.000Z', encerramento: 'normalizou', avaliacao_cuidador: 'confirmado' },
  { id: 'ep_1', inicio: '2026-11-05T10:00:00.000Z', fim: '2026-11-05T10:02:00.000Z', encerramento: 'normalizou' },
];
const ordem = (id) => buildResetCommand({ id, timestamp: '2026-11-07T14:00:00.000Z', manterPreferencias: true });

// Pulseira com 2 episodios no arquivo, como o index.js monta
function pulseira(t, { lastAppliedId = null, recoverFromRetained = false, timeoutMs = 60_000 } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'puzzleband-reset-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  if (!recoverFromRetained) writeFileSync(historyFilePath(dir, CHILD), JSON.stringify(EPISODIOS));
  const file = openHistoryFile(dir, CHILD);
  const processor = createEdgeProcessor({ childId: CHILD, storage: file.storage });
  const client = new FakeClient();
  const aplicadas = [];
  const link = createEdgeLink({
    client,
    processor,
    recoverFromRetained,
    recoveryTimeoutMs: timeoutMs,
    reset: {
      lastAppliedId,
      onApply(o) {
        file.storage.flush();
        saveLastReset(dir, CHILD, o);
        aplicadas.push(o.id);
      },
    },
  });
  return { dir, file, processor, client, link, aplicadas };
}

test('na partida, ordem retida com id novo: começa vazia, guarda o id e publica a lista vazia', (t) => {
  const { dir, processor, client, link, aplicadas } = pulseira(t, { lastAppliedId: 'antiga' });
  assert.equal(processor.episodes().length, 2);
  client.connect();
  assert.ok(client.subscribed.has(TOPIC('comando')));
  assert.ok(link.checkingReset());
  assert.equal(client.sent(TOPIC('historico')).length, 0, 'espera a ordem retida antes de publicar o histórico');

  client.deliver(TOPIC('comando'), ordem('nova'), { retain: true });
  assert.equal(link.checkingReset(), false);
  assert.deepEqual(aplicadas, ['nova']);
  assert.deepEqual(processor.episodes(), []);
  assert.deepEqual(JSON.parse(readFileSync(historyFilePath(dir, CHILD), 'utf8')), [], 'arquivo vazio na hora');
  assert.equal(readLastReset(dir, CHILD).id, 'nova');
  const publicado = client.sent(TOPIC('historico'));
  assert.equal(publicado.length, 1);
  assert.ok(publicado[0].retain);
  assert.deepEqual(JSON.parse(publicado[0].payload).episodios, []);

  // a mesma ordem de novo (QoS 1 repetido, reconexao): nada muda
  client.deliver(TOPIC('comando'), ordem('nova'), { retain: true });
  assert.deepEqual(aplicadas, ['nova']);
});

test('na partida, ordem retida já aplicada: mantém o histórico e publica normalmente', (t) => {
  const { processor, client, aplicadas } = pulseira(t, { lastAppliedId: 'x1' });
  client.connect();
  client.deliver(TOPIC('comando'), ordem('x1'), { retain: true });
  assert.deepEqual(aplicadas, []);
  assert.equal(processor.episodes().length, 2);
  assert.deepEqual(client.lastJson(TOPIC('historico')).episodios.map((e) => e.id), ['ep_2', 'ep_1']);
});

test('sem ordem retida: publica o histórico depois do tempo limite', async (t) => {
  const { processor, client, link } = pulseira(t, { timeoutMs: 30 });
  client.connect();
  assert.equal(client.sent(TOPIC('historico')).length, 0);
  await new Promise((resolve) => { setTimeout(resolve, 80); });
  assert.equal(link.checkingReset(), false);
  assert.equal(processor.episodes().length, 2);
  assert.equal(client.lastJson(TOPIC('historico')).episodios.length, 2);
});

test('ordem chegando com a pulseira rodando (resetar --forcar): apaga, descarta o episódio aberto e republica', (t) => {
  const { processor, client, link, aplicadas } = pulseira(t);
  client.connect();
  client.deliver(TOPIC('comando'), '', { retain: true }); // retido apagado: so encerra a espera
  assert.equal(link.checkingReset(), false);
  runTicks(calmTicks(40, calmTargets()), 7, (r) => link.step(r), { offset: 9000 });
  const antes = client.sent(TOPIC('historico')).length;

  client.deliver(TOPIC('comando'), ordem('ao-vivo'));
  assert.deepEqual(aplicadas, ['ao-vivo']);
  assert.deepEqual(processor.episodes(), []);
  assert.equal(processor.openEpisode(), null);
  assert.equal(client.sent(TOPIC('historico')).length, antes + 1);
  assert.deepEqual(client.lastJson(TOPIC('historico')).episodios, []);
  // segue processando normalmente depois do reset
  runTicks(calmTicks(5, calmTargets()), 8, (r) => link.step(r), { offset: 9100 });
  assert.equal(client.lastJson(TOPIC('estado')).nivel, 'baixo_risco');
});

test('sem arquivo: ordem nova vence o histórico retido (não importa)', (t) => {
  const { processor, client, aplicadas, link } = pulseira(t, { recoverFromRetained: true });
  client.connect();
  const retido = buildHistoryMessage(EPISODIOS, { childId: CHILD, timestamp: '2026-11-06T12:00:00.000Z' });
  client.deliver(TOPIC('comando'), ordem('nova'), { retain: true });
  assert.deepEqual(aplicadas, ['nova']);
  assert.equal(link.recovering(), false);
  assert.ok(!client.subscribed.has(TOPIC('historico')), 'deixa de assinar o histórico retido');
  client.deliver(TOPIC('historico'), retido, { retain: true }); // chegou depois: ignorado
  assert.deepEqual(processor.episodes(), []);
  assert.deepEqual(client.lastJson(TOPIC('historico')).episodios, []);
});

test('sem a opção reset (padrão): não assina comando e publica na conexão, como antes', () => {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD });
  createEdgeLink({ client, processor });
  client.connect();
  assert.ok(!client.subscribed.has(TOPIC('comando')));
  assert.equal(client.sent(TOPIC('historico')).length, 1);
});
