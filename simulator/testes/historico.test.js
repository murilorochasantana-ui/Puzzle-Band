// Historico da pulseira: arquivo local (historico.js) e recuperacao da
// mensagem retida quando nao ha arquivo. Rode com: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createEdgeLink, createEdgeProcessor } from '../borda.js';
import { createFileStorage, historyFilePath, openHistoryFile } from '../historico.js';
import { calmTargets } from '../scenarios.js';
import { buildHistoryMessage } from '../../frontend/src/hooks/buildMessages.js';
import { FakeClient, calmTicks, isoAt, nominalTicks, runTicks } from './apoio.js';

const CHILD = 'C01';
const TOPIC = (s) => `puzzleband/${CHILD}/${s}`;

function tempDir(t) {
  const dir = mkdtempSync(join(tmpdir(), 'puzzleband-historico-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

// Um episodio fechado (crise_ruido + calmo) e, se `abrirOutro`, um segundo
// ainda em andamento (pulseira "desligada" no meio da segunda crise)
function crisisRun(processor, { abrirOutro = false } = {}) {
  let n = runTicks(nominalTicks('crise_ruido', 1), 1, (r) => processor.ingest(r));
  n += runTicks(calmTicks(60, calmTargets()), 99, (r) => processor.ingest(r), { offset: n });
  if (!abrirOutro) return;
  let open = false;
  runTicks(nominalTicks('crise_luz', 2), 2, (r) => {
    if (!open) open = Boolean(processor.ingest(r).changed.length) && Boolean(processor.openEpisode());
  }, { offset: n });
}

test('recupera o historico do arquivo entre execucoes (episodio aberto vira "interrompido")', (t) => {
  const dir = tempDir(t);
  const first = openHistoryFile(dir, CHILD);
  assert.equal(first.status, 'sem_arquivo');
  const p1 = createEdgeProcessor({ childId: CHILD, storage: first.storage });
  crisisRun(p1, { abrirOutro: true });
  assert.equal(p1.episodes().length, 2);
  assert.ok(p1.openEpisode());
  first.storage.flush(); // como no Ctrl+C sem fechar o episodio (queda de energia)

  const path = historyFilePath(dir, CHILD);
  assert.ok(existsSync(path));
  assert.ok(JSON.parse(readFileSync(path, 'utf8')).length === 2);

  const second = openHistoryFile(dir, CHILD);
  assert.equal(second.status, 'ok');
  assert.equal(second.episodes, 2);
  const p2 = createEdgeProcessor({ childId: CHILD, storage: second.storage });
  const [aberto, fechado] = p2.episodes();
  assert.equal(aberto.encerramento, 'interrompido');
  assert.equal(fechado.encerramento, 'normalizou');
  assert.equal(fechado.gatilho.tipo, 'ruido');
  assert.ok(fechado.gatilho.sinais, 'o arquivo guarda o gatilho completo');
  assert.equal(p2.openEpisode(), null);
});

test('arquivo: gravacao agrupada (no maximo 1 a cada delayMs) e flush no final', (t) => {
  const dir = tempDir(t);
  const path = historyFilePath(dir, CHILD);
  const storage = createFileStorage(path, { delayMs: 60_000 });
  storage.setItem('x', '[{"id":"a","inicio":"2026-01-01T12:00:00.000Z"}]');
  storage.setItem('x', '[]');
  assert.equal(existsSync(path), false, 'ainda nao gravou');
  assert.equal(storage.flush(), true);
  assert.equal(readFileSync(path, 'utf8').trim(), '[]', 'grava o ultimo valor');
  assert.equal(existsSync(`${path}.tmp`), false);
});

test('arquivo corrompido e guardado a parte e a pulseira segue sem ele', (t) => {
  const dir = tempDir(t);
  writeFileSync(historyFilePath(dir, CHILD), '{ isto nao e json');
  const opened = openHistoryFile(dir, CHILD);
  assert.equal(opened.status, 'corrompido');
  assert.ok(readdirSync(dir).some((f) => f.startsWith(`historico_${CHILD}.corrompido-`)));
  assert.equal(existsSync(historyFilePath(dir, CHILD)), false);
});

test('sem arquivo: recupera da mensagem retida em historico antes de publicar a sua', () => {
  // historico retido de uma execucao anterior: um episodio fechado e um aberto
  const old = createEdgeProcessor({ childId: CHILD });
  crisisRun(old, { abrirOutro: true });
  const retained = buildHistoryMessage(old.episodes(), { childId: CHILD, timestamp: isoAt(0) });
  const oldIds = old.episodes().map((ep) => ep.id);

  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD });
  const link = createEdgeLink({ client, processor, recoverFromRetained: true, recoveryTimeoutMs: 60_000 });
  client.connect();
  assert.ok(client.subscribed.has(TOPIC('historico')), 'assina historico so na partida');

  // leituras chegando antes da mensagem retida: nao publica historico (apagaria o retido)
  runTicks(calmTicks(5, calmTargets()), 3, (r) => link.step(r), { offset: 5000 });
  assert.equal(client.sent(TOPIC('historico')).length, 0);

  client.deliver(TOPIC('historico'), retained, { retain: true });
  assert.equal(link.recovering(), false);
  assert.ok(!client.subscribed.has(TOPIC('historico')), 'deixa de assinar depois de recuperar');
  assert.deepEqual(client.unsubscribed, [TOPIC('historico')]);

  const published = client.lastJson(TOPIC('historico'));
  assert.deepEqual(published.episodios.map((ep) => ep.id), oldIds);
  assert.equal(published.episodios[0].encerramento, 'interrompido'); // estava aberto quando a pulseira caiu
  assert.equal(published.episodios[1].encerramento, 'normalizou');
  assert.equal(published.episodios[1].gatilho.tipo, 'ruido');
  assert.equal(processor.episodes().length, 2);

  // uma segunda mensagem em historico (a propria publicacao, por exemplo) nao e reimportada
  client.deliver(TOPIC('historico'), { episodios: [] });
  assert.equal(processor.episodes().length, 2);
});

test('sem arquivo e sem mensagem retida: espera o tempo limite e comeca vazio', async () => {
  const client = new FakeClient();
  const processor = createEdgeProcessor({ childId: CHILD });
  const link = createEdgeLink({ client, processor, recoverFromRetained: true, recoveryTimeoutMs: 30 });
  client.connect();
  assert.equal(client.sent(TOPIC('historico')).length, 0);
  await new Promise((resolve) => { setTimeout(resolve, 80); });
  assert.equal(link.recovering(), false);
  assert.deepEqual(client.lastJson(TOPIC('historico')).episodios, []);
});
