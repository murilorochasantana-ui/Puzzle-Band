#!/usr/bin/env node
// Validacao com sementes NOVAS (estudo "exercicio x crise", docs/modelo.md):
// o E4d foi ajustado vendo casos das sementes 1-50 do verificar.js; aqui ele
// e o atual rodam com sementes nunca usadas no estudo. Monta uma copia da
// pulseira (como o comparar_episodios.mjs), liga a politica pedida e roda,
// com as sementes ini..fim, uma das partes:
//   eventos   eventos_aleatorios, 20 eventos por semente
//   crises    laco (3 ciclos) dos 7 cenarios de crise antigos
//   novos     laco de crise_com_agitacao e exercicio_e_crise nas 3 intensidades
//   controle  laco de exercicio, barulho_sem_crise e calmo
//
//   node model/validar_sementes.mjs --sementes 101-300 --parte crises [--politica '<json>' | --politica null] --saida <arq.json>
//   (sem --politica vale a do contexto.js; null = sem politica)
//   node model/validar_sementes.mjs --tabela <atual.json>... (junta as partes e imprime as tabelas)

import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const CRISES = ['estereotipia', 'crise_ruido', 'crise_luz', 'crise_sem_gatilho', 'crise_ruido_e_luz', 'ruido_depois_da_crise', 'crise_e_recuperacao'];
const NIVEIS = ['leve', 'moderada', 'alta'];

const FILHO = `
import { simulateProgram, exerciseCrisisCheck, LOOP_EXPECTED } from './simulator/verificar.js';
import { programTicks, SCENARIOS } from './simulator/scenarios.js';
const [ini, fim, parte] = process.argv.slice(2);
const RANK = { baixo_risco: 0, atencao: 1, alto_risco: 2 };
const CRISES = ${JSON.stringify(CRISES)};
const out = {};
const porCiclo = (run) => run.cycles.map((c) => run.episodes.filter((ep) => ep.t_inicio >= c.tInicio && ep.t_inicio < c.tFim + 60));
const orfaos = (run, por) => { const s = new Set(por.flat()); return run.episodes.filter((ep) => !s.has(ep)).length; };
function laco(cenario, nivel = null) {
  const ciclos = [];
  let pausas = 0;
  for (let seed = +ini; seed <= +fim; seed += 1) {
    const run = simulateProgram(programTicks({ cenario, ciclos: 3, pausa: 120, seed, nivel }), seed);
    const por = porCiclo(run);
    pausas += orfaos(run, por);
    run.cycles.forEach((c, i) => {
      const eps = por[i];
      let det = eps.length > 0;
      let t = det && c.tFisiologia !== null ? Math.min(...eps.map((e) => e.t_inicio)) - c.tFisiologia : null;
      let como = det ? 'episodio' : 'perdida';
      if (cenario === 'exercicio_e_crise') {
        const r = exerciseCrisisCheck(eps, c);
        t = r.tAlerta;
        como = r.como;
        det = t !== null;
      }
      const max = eps.reduce((m, e) => (RANK[e.nivel_maximo] > RANK[m] ? e.nivel_maximo : m), 'baixo_risco');
      ciclos.push({ seed, ciclo: c.numero, resultado: LOOP_EXPECTED[cenario].avaliar(eps, c), det, t, como, max });
    });
  }
  return { ciclos, pausas };
}
if (parte === 'eventos') {
  const eventos = [];
  let pausas = 0;
  for (let seed = +ini; seed <= +fim; seed += 1) {
    const run = simulateProgram(programTicks({ cenario: 'eventos_aleatorios', ciclos: 20, pausa: 120, seed }), seed);
    const por = porCiclo(run);
    pausas += orfaos(run, por);
    run.cycles.forEach((c, i) => {
      const eps = por[i];
      eventos.push({ tipo: c.tipo, crise: c.criseReal, intensidade: c.intensidade, det: eps.length > 0,
        t: eps.length && c.tFisiologia !== null ? Math.min(...eps.map((e) => e.t_inicio)) - c.tFisiologia : null });
    });
  }
  out.eventos = { eventos, pausas };
}
if (parte === 'crises') for (const n of CRISES) out[n] = laco(n);
if (parte === 'novos') for (const n of ['crise_com_agitacao', 'exercicio_e_crise']) for (const nv of ['leve', 'moderada', 'alta']) out[n + ':' + nv] = laco(n, nv);
if (parte === 'controle') for (const n of ['exercicio', 'barulho_sem_crise', 'calmo']) out[n] = laco(n);
console.log(JSON.stringify(out));
`;

function montar(dir, temPolitica, politica) {
  for (const sub of ['frontend/src/model', 'frontend/src/hooks', 'simulator']) {
    mkdirSync(join(dir, sub), { recursive: true });
    for (const f of readdirSync(join(ROOT, sub))) {
      if (/\.(js|json)$/.test(f) && !f.includes('.test.') && f !== 'package-lock.json' && f !== 'package.json') cpSync(join(ROOT, sub, f), join(dir, sub, f));
    }
  }
  writeFileSync(join(dir, 'package.json'), '{"type":"module"}');
  if (temPolitica) {
    const arq = join(dir, 'frontend/src/model/contexto.js');
    const novo = readFileSync(arq, 'utf8').replace(/^export const POLITICA = .*;$/m, `export const POLITICA = ${JSON.stringify(politica)};`);
    if (!novo.includes(JSON.stringify(politica))) throw new Error('politica nao aplicada');
    writeFileSync(arq, novo);
  }
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: { sementes: { type: 'string' }, parte: { type: 'string' }, politica: { type: 'string' }, saida: { type: 'string' },
    nome: { type: 'string' }, tabela: { type: 'boolean', default: false } },
});

if (!values.tabela) {
  const [ini, fim] = values.sementes.split('-').map(Number);
  const dir = mkdtempSync(join(tmpdir(), 'pb-validacao-'));
  try {
    montar(dir, values.politica !== undefined, values.politica !== undefined ? JSON.parse(values.politica) : null);
    writeFileSync(join(dir, 'filho.mjs'), FILHO);
    const r = JSON.parse(execFileSync(process.execPath, ['filho.mjs', ini, fim, values.parte], { cwd: dir, encoding: 'utf8', maxBuffer: 1 << 28 }));
    writeFileSync(values.saida, JSON.stringify({ nome: values.nome ?? 'sem nome', sementes: values.sementes, parte: values.parte, ...r }));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  process.exit(0);
}

// --- tabelas: cada argumento e um prefixo; junta <prefixo>.<parte>.json -----
const versoes = positionals.map((p) => {
  const v = {};
  for (const parte of ['eventos', 'crises', 'novos', 'controle']) Object.assign(v, JSON.parse(readFileSync(`${p}.${parte}.json`, 'utf8')));
  return v;
});
const ref = versoes[0];
const mediana = (a) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.floor(s.length / 2)] : '—'; };
const conta = (cs, f) => cs.filter(f).length;
const dec = (x) => String(Math.round(x * 10) / 10).replace('.', ',');

console.log(`Sementes ${ref.sementes} (nunca usadas no estudo)\n`);
console.log('| Versão | Crises (eventos) | Crises no laço (7 cenários) | crise_com_agitacao detectadas (leve · moderada · alta) | exercicio_e_crise detectadas (leve · moderada · alta) | engolidas | Exercício no laço: sem alerta · só atenção · possível crise | Exercício (eventos) com alarme | barulho_sem_crise sem alerta | calmo sem alerta | Episódios nas pausas (todas as partes) | Alerta após a fisiologia (eventos, média) |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|');
for (const v of versoes) {
  const ev = v.eventos.eventos;
  const crises = ev.filter((e) => e.crise);
  const ex = ev.filter((e) => e.tipo === 'exercicio');
  const lacoCrises = CRISES.flatMap((n) => v[n].ciclos);
  const nov = (n) => NIVEIS.map((nv) => v[`${n}:${nv}`].ciclos);
  const total = (cs) => cs.length;
  const exC = v.exercicio.ciclos;
  const pausas = v.eventos.pausas + [...CRISES, 'exercicio', 'barulho_sem_crise', 'calmo'].reduce((s, n) => s + v[n].pausas, 0)
    + ['crise_com_agitacao', 'exercicio_e_crise'].flatMap((n) => NIVEIS.map((nv) => v[`${n}:${nv}`].pausas)).reduce((a, b) => a + b, 0);
  const tempos = crises.filter((e) => e.det && e.t !== null).map((e) => e.t);
  console.log(`| ${v.nome} | ${conta(crises, (e) => e.det)}/${crises.length} | ${conta(lacoCrises, (c) => c.det)}/${total(lacoCrises)} `
    + `(${conta(lacoCrises, (c) => c.resultado === 'ok')} certos) | ${nov('crise_com_agitacao').map((cs) => `${conta(cs, (c) => c.det)}/${cs.length}`).join(' · ')} | `
    + `${nov('exercicio_e_crise').map((cs) => `${conta(cs, (c) => c.det)}/${cs.length}`).join(' · ')} | `
    + `${nov('exercicio_e_crise').map((cs) => conta(cs, (c) => c.como === 'engolida')).join(' · ')} | `
    + `${conta(exC, (c) => c.resultado === 'ok')} · ${conta(exC, (c) => c.resultado === 'limitacao')} · ${conta(exC, (c) => c.resultado === 'falhou')} (de ${exC.length}) | `
    + `${conta(ex, (e) => e.det)}/${ex.length} | ${conta(v.barulho_sem_crise.ciclos, (c) => c.resultado === 'ok')}/${v.barulho_sem_crise.ciclos.length} | `
    + `${conta(v.calmo.ciclos, (c) => c.resultado === 'ok')}/${v.calmo.ciclos.length} | ${pausas} | ${dec(tempos.reduce((a, b) => a + b, 0) / tempos.length)} s |`);
}

console.log('\n| Versão | Cenário | Intensidade | Detectadas | Tempo até o alerta: mediana · máximo (s) | Maior atraso contra o atual (mesmo ciclo) | Perdidas que o atual detectava |');
console.log('|---|---|---|---|---|---|---|');
for (const v of versoes) {
  for (const n of ['exercicio_e_crise', 'crise_com_agitacao']) {
    for (const nv of NIVEIS) {
      const cs = v[`${n}:${nv}`].ciclos;
      const base = ref[`${n}:${nv}`].ciclos;
      const t = cs.filter((c) => c.det).map((c) => c.t);
      const atrasos = cs.map((c, i) => (c.det && base[i].det ? c.t - base[i].t : null)).filter((x) => x !== null);
      console.log(`| ${v.nome} | ${n} | ${nv} | ${conta(cs, (c) => c.det)}/${cs.length} | ${mediana(t)} · ${t.length ? Math.max(...t) : '—'} | `
        + `${atrasos.length ? `${Math.max(...atrasos) > 0 ? '+' : ''}${Math.max(...atrasos)}` : '—'} | ${conta(cs, (c, i) => !c.det && base[i].det)} |`);
    }
  }
}
