#!/usr/bin/env node
// Validacao automatica dos cenarios, OFFLINE (sem broker): gera as mesmas
// leituras que o index.js publicaria e passa pelo MESMO caminho do dashboard:
//   buffer de 300 leituras -> classifyAt (frontend/src/model/classify.js, que
//   chama computeFeatures, predictCrisisProbability e riskTierFromProbability
//   do predict.js, como o App.jsx) -> episodios (episodes.js) -> gatilho
//   provavel (trigger.js).
// Roda em segundos (nao espera o relogio). Cada cenario roda com varias
// sementes de ruido (Math.random com semente: resultado reprodutivel).
//
//   node verificar.js                         # todos, 20 sementes
//   node verificar.js --cenario demo --sementes 50
//   node verificar.js --markdown              # tabela em Markdown (docs/testes.md)
//
// Sai com codigo 1 se algum cenario nao der o resultado esperado
// ("limitacao conhecida" do exercicio nao conta como falha).

import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { generateReading } from '../frontend/src/model/simulate.js';
import { classifyAt } from '../frontend/src/model/classify.js';
import { createMonitor, ingestReadings, upsertEpisode, EPISODE_END_CALM_S } from '../frontend/src/model/episodes.js';
import { DEMO_SEGMENTS, SCENARIOS, SCENARIO_NAMES, scenarioAt } from './scenarios.js';

const MAX_BUFFER = 300; // mesmo limite do App.jsx
const EXTRA_S = EPISODE_END_CALM_S + 30; // calmo extra no fim, para o ultimo episodio fechar
const T0 = Date.parse('2026-01-01T12:00:00Z');
const TIER_RANK = { baixo_risco: 0, atencao: 1, alto_risco: 2 };

// mulberry32: troca o Math.random durante a simulacao (resultado reprodutivel)
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = a;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

const secondsOf = (iso) => (Date.parse(iso) - T0) / 1000;

// Uma execucao completa do cenario, leitura a leitura, como o dashboard faz
export function simulate(name, seed, { idade = 8 } = {}) {
  const total = SCENARIOS[name].duracao + EXTRA_S;
  const originalRandom = Math.random;
  Math.random = seeded(seed);
  try {
    let buffer = [];
    let monitor = createMonitor({ childId: 'SIM', source: 'mqtt' });
    let lastReading = null;
    let episodes = [];
    let nivelMax = 'baixo_risco';
    let primeiroAlerta = null;
    const tiersByPhase = new Map();
    for (let t = 0; t < total; t += 1) {
      const { alvos, fase } = scenarioAt(name, t, { idade });
      const reading = generateReading({ ...alvos, timestamp: new Date(T0 + t * 1000).toISOString() });
      buffer = [...buffer, reading].slice(-MAX_BUFFER);
      const result = ingestReadings(monitor, lastReading, buffer, classifyAt);
      monitor = result.monitor;
      lastReading = result.lastReading;
      for (const ep of result.changed) episodes = upsertEpisode(episodes, ep);

      const tier = monitor.prevTier;
      if (TIER_RANK[tier] > TIER_RANK[nivelMax]) nivelMax = tier;
      if (tier !== 'baixo_risco' && primeiroAlerta === null) primeiroAlerta = t;
      if (!tiersByPhase.has(fase)) tiersByPhase.set(fase, { baixo_risco: 0, atencao: 0, alto_risco: 0 });
      tiersByPhase.get(fase)[tier] += 1;
    }
    episodes = [...episodes].reverse().map((ep) => ({ ...ep, t_inicio: secondsOf(ep.inicio) }));
    return { nivelMax, primeiroAlerta, episodes, tiersByPhase };
  } finally {
    Math.random = originalRandom;
  }
}

// Episodio principal: o de nivel mais alto (empate: o mais longo)
function mainEpisode(run) {
  return [...run.episodes].sort((a, b) => (TIER_RANK[b.nivel_maximo] - TIER_RANK[a.nivel_maximo])
    || ((b.duracao_s ?? 0) - (a.duracao_s ?? 0)))[0] ?? null;
}

// ---------------------------------------------------------------------------
// Resultado esperado de cada cenario -> 'ok' | 'limitacao' | 'falhou'
// ---------------------------------------------------------------------------

const ok = (cond) => (cond ? 'ok' : 'falhou');
const noAlerts = (run) => ok(run.nivelMax === 'baixo_risco' && run.episodes.length === 0);
const alertWith = (levels, tipo, extra = () => true) => (run) => {
  const main = mainEpisode(run);
  return ok(levels.includes(run.nivelMax) && main?.gatilho?.tipo === tipo && extra(main));
};

function demoCheck(run) {
  const exercise = DEMO_SEGMENTS.find((s) => s.nome === 'exercício');
  const afterExercise = DEMO_SEGMENTS[DEMO_SEGMENTS.indexOf(exercise) + 1];
  const crises = DEMO_SEGMENTS.filter((s) => s.gatilho);
  const inSegment = (ep, s) => ep.t_inicio >= s.inicio && ep.t_inicio < s.fim;
  const mains = crises.map((s) => run.episodes.filter((ep) => inSegment(ep, s)));
  const mainsOk = crises.every((s, i) => mains[i].length === 1
    && mains[i][0].nivel_maximo === 'alto_risco' && mains[i][0].gatilho.tipo === s.gatilho);
  // o resto so pode ser alerta curto de "atencao" ligado ao exercicio
  const others = run.episodes.filter((ep) => !mains.flat().includes(ep));
  const othersOk = others.every((ep) => ep.nivel_maximo === 'atencao'
    && ep.t_inicio >= exercise.inicio && ep.t_inicio < afterExercise.fim);
  return ok(mainsOk && othersOk);
}

export const EXPECTED = {
  calmo: { texto: 'sem alertas', avaliar: noAlerts },
  exercicio: {
    texto: 'idealmente sem alertas',
    // so "atencao" = limitacao conhecida do modelo (transicao exercicio x estresse leve)
    avaliar: (run) => {
      if (run.nivelMax === 'baixo_risco') return 'ok';
      return run.nivelMax === 'atencao' ? 'limitacao' : 'falhou';
    },
  },
  estereotipia: { texto: 'atenção/alto · nenhum_ambiental', avaliar: alertWith(['atencao', 'alto_risco'], 'nenhum_ambiental') },
  crise_ruido: { texto: 'alto_risco · ruido', avaliar: alertWith(['alto_risco'], 'ruido') },
  crise_luz: { texto: 'alto_risco · luminosidade', avaliar: alertWith(['alto_risco'], 'luminosidade') },
  crise_sem_gatilho: { texto: 'alto_risco · nenhum_ambiental', avaliar: alertWith(['alto_risco'], 'nenhum_ambiental') },
  crise_ruido_e_luz: { texto: 'alto_risco · ruido_e_luminosidade', avaliar: alertWith(['alto_risco'], 'ruido_e_luminosidade') },
  barulho_sem_crise: { texto: 'sem alertas', avaliar: noAlerts },
  ruido_depois_da_crise: {
    texto: 'alto_risco · nenhum_ambiental (ruído = consequência)',
    avaliar: alertWith(['alto_risco'], 'nenhum_ambiental', (ep) => ep.gatilho.sinais.ruido.status === 'possivel_consequencia'),
  },
  crise_e_recuperacao: {
    texto: '1 episódio, encerrado, com duração',
    avaliar: (run) => ok(run.episodes.length === 1 && run.episodes[0].encerramento === 'normalizou'
      && run.episodes[0].duracao_s > 0 && run.episodes[0].fim !== null),
  },
  demo: { texto: '2 episódios principais (ruido, nenhum_ambiental)', avaliar: demoCheck },
};

// ---------------------------------------------------------------------------
// Relatorio
// ---------------------------------------------------------------------------

const range = (values, unit = '') => {
  if (!values.length) return '—';
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  return lo === hi ? `${lo}${unit}` : `${lo}–${hi}${unit}`;
};

const median = (values) => {
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

// "11–14 s (mediana 13 s)"
const leadSummary = (values) => (values.length ? `${range(values, ' s')} (mediana ${median(values)} s)` : '—');

// "alto_risco" se todas iguais; senao "alto_risco 18 · atencao 2"
function distribution(values) {
  const counts = new Map();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  if (counts.size === 1) return String(values[0]);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([v, n]) => `${v} ${n}`).join(' · ');
}

function triggerLabel(name, run) {
  if (!run.episodes.length) return '—';
  if (name === 'demo') {
    const crises = DEMO_SEGMENTS.filter((s) => s.gatilho);
    return crises.map((s) => run.episodes.find((ep) => ep.t_inicio >= s.inicio && ep.t_inicio < s.fim)?.gatilho.tipo ?? '?').join(' + ');
  }
  return mainEpisode(run).gatilho.tipo;
}

function evaluateScenario(name, seeds) {
  const runs = Array.from({ length: seeds }, (_, i) => simulate(name, i + 1));
  const results = runs.map((run) => EXPECTED[name].avaliar(run));
  const count = (r) => results.filter((x) => x === r).length;
  let resultado = 'ok';
  if (count('falhou')) resultado = 'falhou';
  else if (count('limitacao')) resultado = 'limitacao';
  // "20/20" ou "11/20 (9 falharam)" ou "0/20 (13 limitação · 7 falharam)"
  const notes = [];
  if (count('limitacao')) notes.push(`${count('limitacao')} limitação`);
  if (count('falhou')) notes.push(`${count('falhou')} ${count('falhou') === 1 ? 'falhou' : 'falharam'}`);
  const bateu = `${count('ok')}/${seeds}${notes.length ? ` (${notes.join(' · ')})` : ''}`;
  return {
    name,
    runs,
    resultado,
    linha: {
      cenario: name,
      esperado: EXPECTED[name].texto,
      nivel: distribution(runs.map((r) => r.nivelMax)),
      alerta: range(runs.map((r) => r.primeiroAlerta).filter((t) => t !== null), ' s'),
      episodios: range(runs.map((r) => r.episodes.length)),
      gatilho: distribution(runs.map((r) => triggerLabel(name, r))),
      bateu,
    },
  };
}

const COLUMNS = [
  ['cenario', 'Cenário'],
  ['esperado', 'Esperado'],
  ['nivel', 'Nível máx.'],
  ['alerta', '1º alerta (t)'],
  ['episodios', 'Episódios'],
  ['gatilho', 'Gatilho identificado'],
  ['bateu', 'Bateu'],
];

function printTable(rows, markdown) {
  if (markdown) {
    console.log(`| ${COLUMNS.map(([, h]) => h).join(' | ')} |`);
    console.log(`|${COLUMNS.map(() => '---').join('|')}|`);
    for (const r of rows) console.log(`| ${COLUMNS.map(([k]) => (k === 'cenario' ? `\`${r[k]}\`` : r[k])).join(' | ')} |`);
    return;
  }
  const widths = COLUMNS.map(([k, h]) => Math.max(h.length, ...rows.map((r) => String(r[k]).length)));
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join(' │ ');
  console.log(line(COLUMNS.map(([, h]) => h)));
  console.log(widths.map((w) => '─'.repeat(w)).join('─┼─'));
  for (const r of rows) console.log(line(COLUMNS.map(([k]) => r[k])));
}

const pct = (n, total) => `${Math.round((100 * n) / total)}%`;

function printDetails(evaluation) {
  const { name, runs } = evaluation;
  const lines = [];
  const mains = runs.map(mainEpisode).filter(Boolean);
  if (mains.length && name !== 'demo') {
    const signal = { crise_ruido: 'ruido', crise_luz: 'luminosidade', crise_e_recuperacao: 'ruido' }[name];
    if (signal) lines.push(`antecedência do sinal ambiental: ${leadSummary(mains.map((ep) => ep.gatilho.sinais[signal].antecedencia_s).filter(Number.isFinite))}`);
    if (name === 'crise_ruido_e_luz') {
      lines.push(`antecedência: ruído ${leadSummary(mains.map((ep) => ep.gatilho.sinais.ruido.antecedencia_s))}, luz ${leadSummary(mains.map((ep) => ep.gatilho.sinais.luminosidade.antecedencia_s))}`);
    }
    const early = mains.filter((ep) => !ep.gatilho.fisiologia.detectada).length;
    if (early && !['exercicio', 'barulho_sem_crise'].includes(name)) {
      lines.push(`modelo alertou antes de BPM/EDA passarem da margem (referência = alerta): ${early}/${mains.length}`);
    }
    if (name === 'ruido_depois_da_crise') {
      lines.push(`ruído: ${distribution(mains.map((ep) => ep.gatilho.sinais.ruido.status))}, ${range(mains.map((ep) => -ep.gatilho.sinais.ruido.antecedencia_s), ' s')} depois da fisiologia`);
    }
    lines.push(`linha de base confiável: ${mains.filter((ep) => ep.gatilho.baseline_confiavel).length}/${mains.length}`);
    const closed = mains.filter((ep) => ep.encerramento === 'normalizou');
    lines.push(`episódio principal encerrado: ${closed.length}/${mains.length}, duração ${range(closed.map((ep) => ep.duracao_s), ' s')}`);
    lines.push(`exemplo (semente 1): "${mains[0].gatilho.texto}"`);
  }
  if (name === 'demo') {
    for (const s of DEMO_SEGMENTS.filter((seg) => seg.gatilho)) {
      const eps = runs.map((r) => r.episodes.find((ep) => ep.t_inicio >= s.inicio && ep.t_inicio < s.fim)).filter(Boolean);
      lines.push(`${s.nome} (${s.inicio}–${s.fim} s): episódio começa em t=${range(eps.map((ep) => ep.t_inicio), ' s')}, `
        + `gatilho ${distribution(eps.map((ep) => ep.gatilho.tipo))}, duração ${range(eps.map((ep) => ep.duracao_s), ' s')}`);
    }
    const crises = DEMO_SEGMENTS.filter((s) => s.gatilho);
    const extras = runs.map((r) => r.episodes.filter((ep) => !crises.some((s) => ep.t_inicio >= s.inicio && ep.t_inicio < s.fim)));
    const withHigh = extras.filter((list) => list.some((ep) => ep.nivel_maximo === 'alto_risco')).length;
    lines.push(`episódios extras (trecho de exercício): ${range(extras.map((l) => l.length))} por execução, `
      + `duração ${range(extras.flat().map((ep) => ep.duracao_s), ' s')}; chegaram a "alto_risco" em ${withHigh}/${runs.length} execuções`);
  }
  if (name === 'exercicio' || name === 'demo') {
    const phases = runs[0].tiersByPhase;
    for (const [fase, c] of phases) {
      if (!/exerc|correr|desacel/.test(fase)) continue;
      const n = c.baixo_risco + c.atencao + c.alto_risco;
      lines.push(`semente 1, fase "${fase}": baixo ${pct(c.baixo_risco, n)} · atenção ${pct(c.atencao, n)} · alto ${pct(c.alto_risco, n)}`);
    }
  }
  if (lines.length) console.log(`\n${name}:\n${lines.map((l) => `  ${l}`).join('\n')}`);
}

function main() {
  const { values } = parseArgs({
    options: {
      cenario: { type: 'string' },
      sementes: { type: 'string', default: '20' },
      markdown: { type: 'boolean', default: false },
    },
  });
  const names = values.cenario ? [values.cenario] : SCENARIO_NAMES;
  const unknown = names.find((n) => !SCENARIOS[n]);
  if (unknown) {
    console.error(`Cenário inválido: "${unknown}". Válidos: ${SCENARIO_NAMES.join(', ')}`);
    process.exit(1);
  }
  const seeds = Math.max(1, Number.parseInt(values.sementes, 10) || 20);
  console.log(`Verificação offline dos cenários: modelo real (predict.js) + episódios + gatilho; ${seeds} sementes por cenário\n`);

  const evaluations = names.map((n) => evaluateScenario(n, seeds));
  printTable(evaluations.map((e) => e.linha), values.markdown);
  if (!values.markdown) evaluations.forEach(printDetails);

  const failed = evaluations.filter((e) => e.resultado === 'falhou').map((e) => e.name);
  const limited = evaluations.filter((e) => e.resultado === 'limitacao').map((e) => e.name);
  console.log('');
  if (limited.length) console.log(`Limitação conhecida (reportada, não é falha): ${limited.join(', ')}`);
  console.log(failed.length ? `FALHOU: ${failed.join(', ')}` : 'OK: todos os cenários deram o resultado esperado.');
  process.exitCode = failed.length ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
