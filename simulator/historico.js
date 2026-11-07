// Historico de episodios da pulseira em arquivo local:
//   simulator/data/historico_<id>.json   (fora do Git: simulator/.gitignore)
//
// E um "storage" com getItem/setItem (a mesma interface do localStorage que o
// site usava), entao o createEpisodeStore/loadEpisodes de
// frontend/src/model/episodes.js funciona sem mudanca. Diferencas:
//   - a gravacao e agrupada: no maximo uma a cada `delayMs` (com episodio
//     aberto, o historico muda a cada segundo) e sempre no flush() final;
//   - a gravacao e atomica (arquivo temporario + rename), para um Ctrl+C no
//     meio nao deixar um JSON pela metade.

import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { loadEpisodes } from '../frontend/src/model/episodes.js';

export const WRITE_DELAY_MS = 2000;

export const historyFilePath = (dir, childId) => join(dir, `historico_${childId}.json`);

export function createFileStorage(path, { delayMs = WRITE_DELAY_MS, onError = () => {} } = {}) {
  let pending = null; // texto a gravar
  let timer = null;

  function write(text) {
    mkdirSync(dirname(path), { recursive: true });
    const tmp = `${path}.tmp`;
    writeFileSync(tmp, text);
    try {
      renameSync(tmp, path);
    } catch {
      // Windows/OneDrive as vezes seguram o arquivo por um instante: grava direto
      writeFileSync(path, text);
      try {
        unlinkSync(tmp);
      } catch {
        // o temporario fica para a proxima gravacao sobrescrever
      }
    }
  }

  function flush() {
    clearTimeout(timer);
    timer = null;
    if (pending === null) return true;
    const text = pending;
    try {
      write(text);
      if (pending === text) pending = null;
      return true;
    } catch (err) {
      onError(err);
      return false; // continua pendente: tenta de novo na proxima mudanca
    }
  }

  return {
    path,
    exists: () => existsSync(path),
    getItem() {
      try {
        return readFileSync(path, 'utf8');
      } catch (err) {
        if (err.code === 'ENOENT') return null;
        throw err; // loadEpisodes trata como "falhou ao ler"
      }
    },
    setItem(_key, value) {
      // episodes.js grava JSON compacto; no arquivo fica indentado (legivel)
      let text = value;
      try {
        text = `${JSON.stringify(JSON.parse(value), null, 2)}\n`;
      } catch {
        // nao era JSON: grava como veio
      }
      pending = text;
      if (!timer) {
        timer = setTimeout(flush, delayMs);
        timer.unref?.(); // nao segura o processo aberto
      }
    },
    flush,
  };
}

// Abre o arquivo do historico. Se ele existir mas estiver corrompido, e
// renomeado para historico_<id>.corrompido-<data>.json (nada se perde) e a
// pulseira segue como se nao houvesse arquivo.
export function openHistoryFile(dir, childId, options = {}) {
  const storage = createFileStorage(historyFilePath(dir, childId), options);
  if (!storage.exists()) return { storage, status: 'sem_arquivo', episodes: 0 };
  const loaded = loadEpisodes(storage);
  if (loaded.ok) return { storage, status: 'ok', episodes: loaded.episodes.length };
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = storage.path.replace(/\.json$/, `.corrompido-${stamp}.json`);
  renameSync(storage.path, backup);
  return { storage, status: 'corrompido', episodes: 0, backup };
}
