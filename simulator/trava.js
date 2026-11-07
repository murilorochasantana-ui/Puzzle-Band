// Arquivo de trava da pulseira: simulator/data/pulseira_<id>.lock
//
// A pulseira (index.js) cria o arquivo ao iniciar, com o PID do processo, e
// apaga ao encerrar. O reset (resetar.js) consulta a trava para recusar
// apagar o historico com a pulseira rodando (ela regravaria o arquivo e
// republicaria a lista). Trava de um processo que ja morreu (queda de
// energia, terminal fechado a forca) e "velha": nao bloqueia.

import { mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const lockPath = (dir, childId) => join(dir, `pulseira_${childId}.lock`);

// process.kill(pid, 0) nao mata nada: so pergunta se o processo existe.
// EPERM = existe, mas e de outro usuario.
export function processAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

function readLock(path) {
  try {
    const data = JSON.parse(readFileSync(path, 'utf8'));
    return data && typeof data === 'object' ? data : {};
  } catch (err) {
    if (err.code === 'ENOENT') return null;
    return {}; // ilegivel: trata como trava sem PID (velha)
  }
}

// { estado: 'livre' | 'ativa' | 'velha', path, dados }
export function checkLock(dir, childId, { isAlive = processAlive } = {}) {
  const path = lockPath(dir, childId);
  const dados = readLock(path);
  if (!dados) return { estado: 'livre', path, dados: null };
  return { estado: isAlive(dados.pid) ? 'ativa' : 'velha', path, dados };
}

// Cria (ou substitui) a trava deste processo. `anterior` diz se ja havia
// uma: ativa = outra pulseira com o mesmo CHILD_ID esta rodando.
// remove() so apaga a trava se ela ainda for deste processo.
export function createLock(dir, childId, info = {}, { pid = process.pid, isAlive = processAlive } = {}) {
  const anterior = checkLock(dir, childId, { isAlive });
  const path = anterior.path;
  mkdirSync(dir, { recursive: true });
  writeFileSync(path, `${JSON.stringify({ pid, inicio: new Date().toISOString(), crianca: childId, ...info }, null, 2)}\n`);
  return {
    path,
    anterior,
    remove() {
      if (readLock(path)?.pid !== pid) return false;
      try {
        unlinkSync(path);
        return true;
      } catch {
        return false;
      }
    },
  };
}
