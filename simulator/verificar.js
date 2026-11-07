#!/usr/bin/env node
// Validacao automatica dos cenarios, OFFLINE (sem broker): gera as mesmas
// leituras que o index.js publicaria (mesmo programTicks() e mesma --seed) e
// passa pelo MESMO processador que a pulseira roda ao vivo (borda.js,
// createEdgeProcessor):
//   buffer de 300 leituras -> classifyAt (frontend/src/model/classify.js, que
//   chama computeFeatures, predictCrisisProbability e riskTierFromProbability
//   do predict.js) -> episodios (episodes.js) -> gatilho provavel (trigger.js).
// Roda em segundos (nao espera o relogio). A semente controla o ruido dos
// sensores e o sorteio do roteiro: resultado reprodutivel, e igual ao do
// simulador ao vivo com a mesma --seed.
//
// Padrao:
//   1. LOOP: cada cenario roda 3 ciclos com a pausa calma entre eles (1o
//      ciclo nominal, os outros com variacao), em 20 sementes. Cada ciclo
//      tem de dar o resultado esperado; nos cenarios com crise, exatamente 1
//      episodio por ciclo, fechado, com o nivel e o gatilho esperados.
//   2. eventos_aleatorios: 20 eventos com seed fixa (42); compara o gabarito
//      do sorteio com os episodios detectados. Depois, o agregado das seeds
//      1-50 (1000 eventos), para todos os tipos e intensidades terem amostra.
//
//   node verificar.js                              # loop + eventos_aleatorios
//   node verificar.js --cenario crise_luz --sementes 50 --pausa 90
//   node verificar.js --cenario eventos_aleatorios --seed 7 --eventos 40 --agregado 0
//   node verificar.js --uma-vez --sementes 50      # verificacao antiga: roteiro nominal, uma vez
//   node verificar.js --markdown                   # tabelas em Markdown (docs/testes.md)
//
// Sai com codigo 1 se algum cenario nao der o resultado esperado
// ("limitacao conhecida" do exercicio nao conta como falha). O
// eventos_aleatorios e uma medicao: nao reprova.

import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { generateReading } from '../frontend/src/model/simulate.js';
import { EPISODE_END_CALM_S } from '../frontend/src/model/episodes.js';
import { createEdgeProcessor } from './borda.js';
import {
  EVENTOS_ALEATORIOS, INTENSIDADES, PAUSA_MIN_S, PAUSA_PADRAO_S, SCENARIOS, TIPOS_DE_EVENTO, VARIACAO_NOMINAL,
  calmTargets, cycleDetails, nominalScenario, programTicks, seeded, withRandom,
} from './scenarios.js';

const EXTRA_S = EPISODE_END_CALM_S + 30; // --uma-vez: calmo extra no fim, para o ultimo episodio fechar
const T0 = Date.parse('2026-01-01T12:00:00Z');
const TIER_RANK = { baixo_risco: 0, atencao: 1, alto_risco: 2 };
// Episodio que comeca ate 60 s depois do fim do trecho ativo ainda e do
// ciclo/evento (o modelo usa janelas de 30 s e reage com atraso)
const MATCH_TAIL_S = 60;
const LOOP_CYCLES = 3;
const LOOP_SEEDS = 20;
const RANDOM_SEED = 42;
const RANDOM_EVENTS = 20;
const RANDOM_AGGREGATE_SEEDS = 50; // agregado: seeds 1..50, para todos os tipos terem amostra
const SCENARIO_KEYS = Object.keys(SCENARIOS);
const DEMO_SEGMENTS = nominalScenario('demo').segmentos;

const secondsOf = (iso) => (Date.parse(iso) - T0) / 1000;

// Executa um programa (programTicks) leitura a leitura, como a pulseira faz.
// Math.random = ruido dos sensores com a semente `seed` (o mesmo que o
// index.js usa); o sorteio do roteiro tem gerador proprio (scenarios.js).
export function simulateProgram(ticks, seed, { extraCalmS = 0, idade = 8 } = {}) {
  return withRandom(seeded(seed), () => {
    // o MESMO processador que a pulseira roda ao vivo (borda.js), sem rede e sem arquivo
    const processor = createEdgeProcessor({ childId: 'SIM', source: 'pulseira' });
    let nivelMax = 'baixo_risco';
    let primeiroAlerta = null;
    const tiersByPhase = new Map();
    const cycles = [];

    const step = (t, alvos, fase) => {
      const reading = generateReading({ ...alvos, timestamp: new Date(T0 + t * 1000).toISOString() });
      const { tier } = processor.ingest(reading);

      if (TIER_RANK[tier] > TIER_RANK[nivelMax]) nivelMax = tier;
      if (tier !== 'baixo_risco' && primeiroAlerta === null) primeiroAlerta = t;
      if (!tiersByPhase.has(fase)) tiersByPhase.set(fase, { baixo_risco: 0, atencao: 0, alto_risco: 0 });
      tiersByPhase.get(fase)[tier] += 1;
    };

    let last = { t: -1, fase: 'calmo' };
    for (const tick of ticks) {
      if (tick.inicioCiclo) cycles.push(tick.ciclo);
      step(tick.t, tick.alvos, tick.fase);
      last = tick;
    }
    const calm = calmTargets(idade);
    for (let k = 1; k <= extraCalmS; k += 1) step(last.t + k, calm, last.fase);

    const episodes = [...processor.episodes()].reverse().map((ep) => ({ ...ep, t_inicio: secondsOf(ep.inicio) }));
    return { nivelMax, primeiroAlerta, episodes, tiersByPhase, cycles };
  });
}

// Roteiro nominal, uma vez (+ calmo extra), como o simulador antes do loop
export const simulate = (name, seed, { idade = 8 } = {}) => simulateProgram(
  programTicks({ cenario: name, umaVez: true, seed, idade }), seed, { extraCalmS: EXTRA_S, idade },
);

// Episodio principal: o de nivel mais alto (empate: o mais longo)
function mainOf(episodes) {
  return [...episodes].sort((a, b) => (TIER_RANK[b.nivel_maximo] - TIER_RANK[a.nivel_maximo])
    || ((b.duracao_s ?? 0) - (a.duracao_s ?? 0)))[0] ?? null;
}
const mainEpisode = (run) => mainOf(run.episodes);

// ---------------------------------------------------------------------------
// Estatistica e formatacao
// ---------------------------------------------------------------------------

// "3–7 s"; com negativo, "−2 a 6 s" (o traco viraria ambiguo)
const range = (values, unit = '') => {
  if (!values.length) return '—';
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  if (lo === hi) return `${lo}${unit}`;
  return lo < 0 ? `${String(lo).replace('-', '−')} a ${hi}${unit}` : `${lo}–${hi}${unit}`;
};

const median = (values) => {
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

const mean = (values) => values.reduce((a, b) => a + b, 0) / values.length;
const dec = (x, digits = 1) => x.toFixed(digits).replace('.', ',');
const pctOf = (n, total) => (total ? `${Math.round((100 * n) / total)}%` : '—');

// "11–14 s (mediana 13 s)"
const leadSummary = (values) => (values.length ? `${range(values, ' s')} (mediana ${median(values)} s)` : '—');

// "alto_risco" se todas iguais; senao "alto_risco 18 · atencao 2"
function distribution(values) {
  const counts = new Map();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  if (counts.size === 1) return String(values[0]);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([v, n]) => `${v} ${n}`).join(' · ');
}

// "20/20" ou "11/20 (9 falharam)" ou "0/20 (13 limitação · 7 falharam)"
function tally(results) {
  const count = (r) => results.filter((x) => x === r).length;
  const notes = [];
  if (count('limitacao')) notes.push(`${count('limitacao')} limitação`);
  if (count('falhou')) notes.push(`${count('falhou')} ${count('falhou') === 1 ? 'falhou' : 'falharam'}`);
  return `${count('ok')}/${results.length}${notes.length ? ` (${notes.join(' · ')})` : ''}`;
}

function worstOf(results) {
  if (results.includes('falhou')) return 'falhou';
  if (results.includes('limitacao')) return 'limitacao';
  return 'ok';
}

// Tempo desde o inicio no MESMO formato do log do simulador ([mm:ss] ou [h:mm:ss])
function mmss(t) {
  const h = Math.floor(t / 3600);
  const mm = `${String(Math.floor((t % 3600) / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
  return h ? `${h}:${mm}` : mm;
}

function printTable(columns, rows, markdown) {
  if (markdown) {
    console.log(`| ${columns.map(([, h]) => h).join(' | ')} |`);
    console.log(`|${columns.map(() => '---').join('|')}|`);
    for (const r of rows) console.log(`| ${columns.map(([k]) => (k === 'cenario' ? `\`${r[k]}\`` : r[k])).join(' | ')} |`);
    return;
  }
  const widths = columns.map(([k, h]) => Math.max(h.length, ...rows.map((r) => String(r[k]).length)));
  const line = (cells) => cells.map((c, i) => String(c).padEnd(widths[i])).join(' │ ');
  console.log(line(columns.map(([, h]) => h)));
  console.log(widths.map((w) => '─'.repeat(w)).join('─┼─'));
  for (const r of rows) console.log(line(columns.map(([k]) => r[k])));
}

// ---------------------------------------------------------------------------
// Resultado esperado de cada cenario -> 'ok' | 'limitacao' | 'falhou'
// ---------------------------------------------------------------------------

const ok = (cond) => (cond ? 'ok' : 'falhou');
const isClosed = (ep) => ep.encerramento === 'normalizou' && ep.fim !== null && ep.duracao_s > 0;

// Demo: as duas crises viram 1 episodio cada (alto_risco, gatilho certo); o
// resto so pode ser alerta curto de "atencao" ligado ao exercicio
function demoEpisodes(episodes, segmentos, offset = 0) {
  const segs = segmentos.map((s) => ({ ...s, inicio: s.inicio + offset, fim: s.fim + offset }));
  const exercise = segs.find((s) => s.nome === 'exercício');
  const afterExercise = segs[segs.indexOf(exercise) + 1];
  const crises = segs.filter((s) => s.gatilho);
  const inSegment = (ep, s) => ep.t_inicio >= s.inicio && ep.t_inicio < s.fim;
  const mains = crises.map((s) => episodes.filter((ep) => inSegment(ep, s)));
  const mainsOk = crises.every((s, i) => mains[i].length === 1
    && mains[i][0].nivel_maximo === 'alto_risco' && mains[i][0].gatilho.tipo === s.gatilho);
  const others = episodes.filter((ep) => !mains.flat().includes(ep));
  const othersOk = others.every((ep) => ep.nivel_maximo === 'atencao'
    && ep.t_inicio >= exercise.inicio && ep.t_inicio < afterExercise.fim);
  return { mainsOk, othersOk, mains: mains.map((list) => list[0] ?? null), others };
}

// --- verificacao antiga (--uma-vez): uma execucao do roteiro nominal ---

const noAlerts = (run) => ok(run.nivelMax === 'baixo_risco' && run.episodes.length === 0);
const alertWith = (levels, tipo, extra = () => true) => (run) => {
  const main = mainEpisode(run);
  return ok(levels.includes(run.nivelMax) && main?.gatilho?.tipo === tipo && extra(main));
};

function demoCheck(run) {
  const { mainsOk, othersOk } = demoEpisodes(run.episodes, DEMO_SEGMENTS);
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

// --- loop: cada ciclo, com os episodios que comecaram nele ---

const oneEpisode = (levels, tipo, extra = () => true) => (eps) => ok(eps.length === 1 && isClosed(eps[0])
  && levels.includes(eps[0].nivel_maximo) && eps[0].gatilho?.tipo === tipo && extra(eps[0]));

export const LOOP_EXPECTED = {
  calmo: { texto: 'sem alertas', avaliar: (eps) => ok(eps.length === 0) },
  exercicio: {
    texto: 'idealmente sem alertas',
    avaliar: (eps) => {
      if (!eps.length) return 'ok';
      return eps.every((ep) => ep.nivel_maximo === 'atencao') ? 'limitacao' : 'falhou';
    },
  },
  estereotipia: { texto: '1 episódio fechado · atenção/alto · nenhum_ambiental', avaliar: oneEpisode(['atencao', 'alto_risco'], 'nenhum_ambiental') },
  crise_ruido: { texto: '1 episódio fechado · alto_risco · ruido', avaliar: oneEpisode(['alto_risco'], 'ruido') },
  crise_luz: { texto: '1 episódio fechado · alto_risco · luminosidade', avaliar: oneEpisode(['alto_risco'], 'luminosidade') },
  crise_sem_gatilho: { texto: '1 episódio fechado · alto_risco · nenhum_ambiental', avaliar: oneEpisode(['alto_risco'], 'nenhum_ambiental') },
  crise_ruido_e_luz: { texto: '1 episódio fechado · alto_risco · ruido_e_luminosidade', avaliar: oneEpisode(['alto_risco'], 'ruido_e_luminosidade') },
  barulho_sem_crise: { texto: 'sem alertas', avaliar: (eps) => ok(eps.length === 0) },
  ruido_depois_da_crise: {
    texto: '1 episódio fechado · alto_risco · nenhum_ambiental (ruído = consequência)',
    avaliar: oneEpisode(['alto_risco'], 'nenhum_ambiental', (ep) => ep.gatilho.sinais.ruido.status === 'possivel_consequencia'),
  },
  crise_e_recuperacao: { texto: '1 episódio fechado · alto_risco · ruido', avaliar: oneEpisode(['alto_risco'], 'ruido') },
  demo: {
    texto: '2 episódios fechados (ruido, nenhum_ambiental) + só "atenção" no exercício',
    avaliar: (eps, ciclo) => {
      const { mainsOk, othersOk, mains } = demoEpisodes(eps, ciclo.roteiro.segmentos, ciclo.t0);
      return ok(mainsOk && othersOk && mains.every(isClosed));
    },
  },
};

// Episodios de cada ciclo: os que comecam no trecho ativo ou ate
// MATCH_TAIL_S depois; os outros (nas pausas) sao "fora dos ciclos"
function assignEpisodes(run) {
  const byCycle = run.cycles.map((c) => run.episodes.filter((ep) => ep.t_inicio >= c.tInicio && ep.t_inicio < c.tFim + MATCH_TAIL_S));
  const assigned = new Set(byCycle.flat());
  return { byCycle, orphans: run.episodes.filter((ep) => !assigned.has(ep)) };
}

// ---------------------------------------------------------------------------
// 1. Loop
// ---------------------------------------------------------------------------

const ENV_SIGNALS = {
  crise_ruido: ['ruido'],
  crise_luz: ['luminosidade'],
  crise_ruido_e_luz: ['ruido', 'luminosidade'],
  crise_e_recuperacao: ['ruido'],
};

function triggerOfCycle(name, eps, ciclo) {
  if (!eps.length) return '—';
  if (name === 'demo') {
    const { mains } = demoEpisodes(eps, ciclo.roteiro.segmentos, ciclo.t0);
    return mains.map((ep) => ep?.gatilho.tipo ?? '?').join(' + ');
  }
  return mainOf(eps).gatilho.tipo;
}

function evaluateLoop(name, seeds, { ciclos, pausa }) {
  const runs = [];
  for (let seed = 1; seed <= seeds; seed += 1) {
    const run = simulateProgram(programTicks({ cenario: name, ciclos, pausa, seed }), seed);
    const { byCycle, orphans } = assignEpisodes(run);
    const results = run.cycles.map((c, i) => LOOP_EXPECTED[name].avaliar(byCycle[i], c));
    runs.push({ seed, run, byCycle, orphans, results, resultado: orphans.length ? 'falhou' : worstOf(results) });
  }
  const cycles = runs.flatMap((r) => r.run.cycles.map((c, i) => ({ seed: r.seed, ciclo: c, eps: r.byCycle[i], resultado: r.results[i] })));
  const episodes = runs.flatMap((r) => r.run.episodes);
  const orphans = runs.reduce((n, r) => n + r.orphans.length, 0);
  const resultado = worstOf(runs.map((r) => r.resultado));

  // primeiro episodio de cada ciclo com crise
  const firsts = cycles.filter((x) => x.eps.length && x.ciclo.tFisiologia !== null)
    .map((x) => ({ ...x, ep: [...x.eps].sort((a, b) => a.t_inicio - b.t_inicio)[0], main: mainOf(x.eps) }));
  const signals = ENV_SIGNALS[name] ?? [];
  const leads = signals.map((key) => firsts.map((x) => x.main.gatilho.sinais[key].antecedencia_s).filter(Number.isFinite));
  const planned = cycles.map((x) => x.ciclo.roteiro.antecedencia).filter(Number.isFinite);
  const withTrigger = cycles.flatMap((x) => (name === 'demo'
    ? demoEpisodes(x.eps, x.ciclo.roteiro.segmentos, x.ciclo.t0).mains.filter(Boolean)
    : [mainOf(x.eps)].filter(Boolean)));
  const nominal = cycles.filter((x) => x.ciclo.variacao === VARIACAO_NOMINAL);
  const varied = cycles.filter((x) => x.ciclo.variacao !== VARIACAO_NOMINAL);

  return {
    name,
    runs,
    cycles,
    resultado,
    orphans,
    linha: {
      cenario: name,
      esperado: LOOP_EXPECTED[name].texto,
      episodios: range(runs.map((r) => r.run.episodes.length)),
      fechados: episodes.length ? `${episodes.filter(isClosed).length}/${episodes.length}` : '—',
      gatilho: distribution(cycles.map((x) => triggerOfCycle(name, x.eps, x.ciclo))),
      ciclos: tally(cycles.map((x) => x.resultado)),
      bateu: tally(runs.map((r) => r.resultado)),
    },
    detalhe: {
      cenario: name,
      nominal: tally(nominal.map((x) => x.resultado)),
      variados: tally(varied.map((x) => x.resultado)),
      alerta: leadSummary(firsts.map((x) => x.ep.t_inicio - x.ciclo.tFisiologia)).replace(/(\d)\.(\d)/g, '$1,$2'),
      antecedencia: signals.length
        ? `${signals.map((key, i) => `${signals.length > 1 ? `${key === 'ruido' ? 'ruído' : 'luz'} ` : ''}${range(leads[i], ' s')}`).join(', ')} (planejada ${range(planned, ' s')})`
        : '—',
      baseline: withTrigger.length
        ? `${withTrigger.filter((ep) => ep.gatilho.baseline_confiavel).length}/${withTrigger.length} (${range(withTrigger.map((ep) => ep.gatilho.linha_de_base.amostras))} leituras)`
        : '—',
      duracao: range(episodes.filter(isClosed).map((ep) => ep.duracao_s), ' s'),
      fora: String(orphans),
    },
  };
}

const LOOP_COLUMNS = [
  ['cenario', 'Cenário'],
  ['esperado', 'Esperado em cada ciclo'],
  ['episodios', 'Episódios/execução'],
  ['fechados', 'Fechados'],
  ['gatilho', 'Gatilho identificado (por ciclo)'],
  ['ciclos', 'Ciclos certos'],
  ['bateu', 'Execuções 3/3'],
];

const LOOP_DETAIL_COLUMNS = [
  ['cenario', 'Cenário'],
  ['nominal', '1º ciclo (nominal)'],
  ['variados', 'Ciclos variados'],
  ['alerta', 'Alerta após a fisiologia'],
  ['antecedencia', 'Antecedência medida'],
  ['baseline', 'Linha de base confiável'],
  ['duracao', 'Duração dos episódios'],
  ['fora', 'Episódios nas pausas'],
];

function printLoopFailures(evaluation) {
  const bad = evaluation.cycles.filter((x) => x.resultado === 'falhou');
  const orphanRuns = evaluation.runs.filter((r) => r.orphans.length);
  if (!bad.length && !orphanRuns.length) return;
  console.log(`\n${evaluation.name}: ${bad.length} ciclo(s) fora do esperado${orphanRuns.length ? `, ${orphanRuns.length} execução(ões) com episódio na pausa` : ''}`);
  for (const x of bad.slice(0, 4)) {
    const desc = x.eps.length
      ? x.eps.map((ep) => `${ep.nivel_maximo}/${ep.gatilho?.tipo}${isClosed(ep) ? '' : ' (aberto)'} em t=${ep.t_inicio}`).join(', ')
      : 'nenhum episódio';
    console.log(`  semente ${x.seed}, ciclo ${x.ciclo.numero} [${cycleDetails(x.ciclo)}]: ${desc}`);
  }
  if (bad.length > 4) console.log(`  ... e mais ${bad.length - 4}`);
}

// ---------------------------------------------------------------------------
// 2. eventos_aleatorios
// ---------------------------------------------------------------------------

function evaluateRandom({ seed, eventos, pausa }) {
  const run = simulateProgram(programTicks({ cenario: EVENTOS_ALEATORIOS, ciclos: eventos, pausa, seed }), seed);
  const { byCycle, orphans } = assignEpisodes(run);
  const rows = run.cycles.map((c, i) => {
    const eps = byCycle[i];
    const main = mainOf(eps);
    const first = eps.length ? Math.min(...eps.map((ep) => ep.t_inicio)) : null;
    let resultado;
    if (c.criseReal) {
      if (!eps.length) resultado = 'não detectada';
      else resultado = main.gatilho?.tipo === c.gatilhoEsperado ? 'acerto' : 'gatilho errado';
    } else {
      resultado = eps.length ? 'alerta falso' : 'sem alerta (certo)';
    }
    return {
      c,
      eps,
      main,
      resultado,
      alertaFisio: first !== null && c.tFisiologia !== null ? first - c.tFisiologia : null,
      alertaEvento: first !== null ? first - c.tInicio : null,
    };
  });
  return { run, rows, orphans };
}

const secondsText = (x) => `${String(x).replace('-', '−')} s`;

// Resumo de uma lista de eventos avaliados (uma seed ou varias juntas)
function randomStats(rows, orphans) {
  const crises = rows.filter((r) => r.c.criseReal);
  const detected = crises.filter((r) => r.eps.length);
  const rightTrigger = detected.filter((r) => r.resultado === 'acerto');
  const noCrisis = rows.filter((r) => !r.c.criseReal);
  const falseAlarms = noCrisis.filter((r) => r.eps.length);
  const typesNoCrisis = Object.keys(TIPOS_DE_EVENTO).filter((tp) => noCrisis.some((r) => r.c.tipo === tp));
  const alertFisio = detected.map((r) => r.alertaFisio).filter(Number.isFinite);
  const alertEvent = detected.map((r) => r.alertaEvento);
  const durCrisis = detected.map((r) => r.main.duracao_s);
  const durFalse = falseAlarms.map((r) => r.main.duracao_s);
  const levels = Object.keys(INTENSIDADES);
  const byIntensity = levels.map((lvl) => {
    const list = crises.filter((r) => r.c.intensidade === lvl);
    return `${lvl} ${list.filter((r) => r.eps.length).length}/${list.length}`;
  });

  const lines = [
    `Crises reais detectadas: ${detected.length} de ${crises.length} (${pctOf(detected.length, crises.length)}) · por intensidade: ${byIntensity.join(' · ')}`,
    `Alertas falsos: ${falseAlarms.length} de ${noCrisis.length} eventos sem crise viraram episódio`
      + (typesNoCrisis.length ? ` (${typesNoCrisis.map((tp) => `${tp} ${falseAlarms.filter((r) => r.c.tipo === tp).length}/${noCrisis.filter((r) => r.c.tipo === tp).length}`).join(' · ')})` : ''),
    `Episódios fora dos eventos (nas pausas): ${orphans}`,
    `Gatilho certo: ${rightTrigger.length} de ${detected.length} crises detectadas (${pctOf(rightTrigger.length, detected.length)})`,
    `Tempo médio até o alerta: ${alertFisio.length ? `${dec(mean(alertFisio))} s depois do início da alteração fisiológica` : '—'}`
      + `${alertEvent.length ? ` (${dec(mean(alertEvent))} s depois do início do evento)` : ''}`,
    `Duração média dos episódios: ${durCrisis.length ? `${Math.round(mean(durCrisis))} s nas crises` : '—'}`
      + `${durFalse.length ? ` · ${Math.round(mean(durFalse))} s nos alertas falsos` : ''}`,
  ];

  const group = (list) => {
    const det = list.filter((r) => r.eps.length);
    const fis = det.map((r) => r.alertaFisio).filter(Number.isFinite);
    return { det, fis, dur: det.length ? `${Math.round(mean(det.map((r) => r.main.duracao_s)))} s` : '—' };
  };
  const typeRows = Object.keys(TIPOS_DE_EVENTO).map((tipo) => {
    const list = rows.filter((r) => r.c.tipo === tipo);
    const { esperado } = SCENARIOS[TIPOS_DE_EVENTO[tipo]];
    const { det, fis, dur } = group(list);
    const right = det.filter((r) => r.resultado === 'acerto').length;
    let certos = '—';
    if (list.length) {
      certos = esperado.crise
        ? `${right}/${list.length} (${pctOf(right, list.length)})`
        : `${list.length - det.length}/${list.length} sem alerta`;
    }
    return {
      tipo,
      esperado: esperado.gatilho ?? 'sem episódio',
      eventos: list.length,
      detectados: list.length ? `${det.length}/${list.length}${esperado.crise ? '' : ' (alerta falso)'}` : '—',
      certos,
      alerta: esperado.crise && fis.length ? `${dec(mean(fis))} s` : '—',
      duracao: dur,
    };
  });
  const intensityRows = levels.map((lvl) => {
    const list = crises.filter((r) => r.c.intensidade === lvl);
    const { det, fis, dur } = group(list);
    const high = det.filter((r) => r.main.nivel_maximo === 'alto_risco').length;
    return {
      intensidade: `${lvl} (×${String(INTENSIDADES[lvl]).replace('.', ',')})`,
      crises: list.length,
      detectadas: `${det.length}/${list.length}`,
      alto: `${high}/${det.length}`,
      certos: `${det.filter((r) => r.resultado === 'acerto').length}/${list.length}`,
      alerta: fis.length ? `${dec(mean(fis))} s (${range(fis, ' s')})` : '—',
      duracao: dur,
    };
  });
  return { lines, typeRows, intensityRows };
}

const TYPE_COLUMNS = [
  ['tipo', 'Tipo'], ['esperado', 'Gatilho esperado'], ['eventos', 'Eventos'], ['detectados', 'Com episódio'],
  ['certos', 'Acertos'], ['alerta', 'Alerta após a fisiologia (média)'], ['duracao', 'Duração média'],
];
const INTENSITY_COLUMNS = [
  ['intensidade', 'Intensidade'], ['crises', 'Crises'], ['detectadas', 'Detectadas'], ['alto', 'Chegaram a alto_risco'],
  ['certos', 'Gatilho certo'], ['alerta', 'Alerta após a fisiologia'], ['duracao', 'Duração média'],
];

function printRandomStats(stats, markdown, { intensities = false } = {}) {
  console.log('');
  for (const l of stats.lines) console.log(markdown ? `- ${l}` : l);
  console.log(`\nAcerto do gatilho por tipo${markdown ? '' : ':'}\n`);
  printTable(TYPE_COLUMNS, stats.typeRows, markdown);
  if (intensities) {
    console.log(`\nPor intensidade (só crises reais)${markdown ? '' : ':'}\n`);
    printTable(INTENSITY_COLUMNS, stats.intensityRows, markdown);
  }
}

function printRandom({ seed, eventos, pausa, markdown }) {
  const { run, rows, orphans } = evaluateRandom({ seed, eventos, pausa });
  const lastCycle = run.cycles[run.cycles.length - 1];
  const totalS = lastCycle ? lastCycle.tFim + lastCycle.pausaDepois : 0;
  console.log(`\n=== eventos_aleatorios: seed ${seed} · ${eventos} eventos · pausa ${pausa}–${2 * pausa} s · ${dec(totalS / 3600, 1)} h simuladas ===`);
  console.log(`(ao vivo: node index.js --cenario eventos_aleatorios --ciclos ${eventos} --seed ${seed}${pausa === PAUSA_PADRAO_S ? '' : ` --pausa ${pausa}`})\n`);

  printTable([
    ['n', '#'], ['tipo', 'Tipo'], ['intensidade', 'Intensidade'], ['inicio', 'Início'], ['crise', 'Crise real'],
    ['esperado', 'Gatilho esperado'], ['episodios', 'Episódios'], ['nivel', 'Nível máx.'], ['gatilho', 'Gatilho identificado'],
    ['alerta', 'Alerta após a fisiologia'], ['duracao', 'Duração'], ['resultado', 'Resultado'],
  ], rows.map((r) => ({
    n: r.c.numero,
    tipo: r.c.tipo,
    intensidade: r.c.intensidade ?? '—',
    inicio: mmss(r.c.tInicio),
    crise: r.c.criseReal ? 'sim' : 'não',
    esperado: r.c.gatilhoEsperado ?? 'sem episódio',
    episodios: r.eps.length,
    nivel: r.main?.nivel_maximo ?? '—',
    gatilho: r.main?.gatilho?.tipo ?? '—',
    alerta: r.alertaFisio === null ? '—' : secondsText(r.alertaFisio),
    duracao: r.main ? `${r.main.duracao_s} s` : '—',
    resultado: r.resultado,
  })), markdown);
  printRandomStats(randomStats(rows, orphans.length), markdown);
}

// Mesmo teste com varias seeds (1..N), para todos os tipos terem amostra
function printRandomAggregate({ seeds, eventos, pausa, markdown }) {
  const all = [];
  let orphans = 0;
  for (let seed = 1; seed <= seeds; seed += 1) {
    const result = evaluateRandom({ seed, eventos, pausa });
    all.push(...result.rows);
    orphans += result.orphans.length;
  }
  console.log(`\n=== eventos_aleatorios agregado: seeds 1–${seeds} × ${eventos} eventos = ${all.length} eventos ===`);
  printRandomStats(randomStats(all, orphans), markdown, { intensities: true });
}

// ---------------------------------------------------------------------------
// 3. Verificacao antiga (--uma-vez)
// ---------------------------------------------------------------------------

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
  return {
    name,
    runs,
    resultado: worstOf(results),
    linha: {
      cenario: name,
      esperado: EXPECTED[name].texto,
      nivel: distribution(runs.map((r) => r.nivelMax)),
      alerta: range(runs.map((r) => r.primeiroAlerta).filter((t) => t !== null), ' s'),
      episodios: range(runs.map((r) => r.episodes.length)),
      gatilho: distribution(runs.map((r) => triggerLabel(name, r))),
      bateu: tally(results),
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

// ---------------------------------------------------------------------------

function summary(evaluations) {
  const failed = evaluations.filter((e) => e.resultado === 'falhou').map((e) => e.name);
  const limited = evaluations.filter((e) => e.resultado === 'limitacao').map((e) => e.name);
  console.log('');
  if (limited.length) console.log(`Limitação conhecida (reportada, não é falha): ${limited.join(', ')}`);
  if (evaluations.length) console.log(failed.length ? `FALHOU: ${failed.join(', ')}` : 'OK: todos os cenários deram o resultado esperado.');
  return failed.length ? 1 : 0;
}

function main() {
  const { values } = parseArgs({
    options: {
      cenario: { type: 'string' },
      sementes: { type: 'string' },
      ciclos: { type: 'string', default: String(LOOP_CYCLES) },
      pausa: { type: 'string', default: String(PAUSA_PADRAO_S) },
      seed: { type: 'string', default: String(RANDOM_SEED) },
      eventos: { type: 'string', default: String(RANDOM_EVENTS) },
      agregado: { type: 'string', default: String(RANDOM_AGGREGATE_SEEDS) },
      'uma-vez': { type: 'boolean', default: false },
      markdown: { type: 'boolean', default: false },
    },
  });
  const valid = [...SCENARIO_KEYS, EVENTOS_ALEATORIOS];
  if (values.cenario && !valid.includes(values.cenario)) {
    console.error(`Cenário inválido: "${values.cenario}". Válidos: ${valid.join(', ')}`);
    process.exit(1);
  }
  const int = (raw, fallback, min = 1) => Math.max(min, Number.parseInt(raw, 10) || fallback);
  const markdown = values.markdown;

  if (values['uma-vez']) {
    const seeds = int(values.sementes, 20);
    const names = values.cenario ? [values.cenario] : SCENARIO_KEYS;
    if (names.includes(EVENTOS_ALEATORIOS)) {
      console.error('--uma-vez não se aplica ao eventos_aleatorios (use --eventos N).');
      process.exit(1);
    }
    console.log(`Verificação offline dos cenários: modelo real (predict.js) + episódios + gatilho; ${seeds} sementes por cenário\n`);
    const evaluations = names.map((n) => evaluateScenario(n, seeds));
    printTable(COLUMNS, evaluations.map((e) => e.linha), markdown);
    if (!markdown) evaluations.forEach(printDetails);
    process.exitCode = summary(evaluations);
    return;
  }

  const seeds = int(values.sementes, LOOP_SEEDS);
  const ciclos = int(values.ciclos, LOOP_CYCLES);
  const pausa = int(values.pausa, PAUSA_PADRAO_S);
  if (pausa < PAUSA_MIN_S) console.log(`Aviso: pausa de ${pausa} s, abaixo do mínimo de ${PAUSA_MIN_S} s do simulador (teste de limite).\n`);

  const loopNames = values.cenario ? [values.cenario].filter((n) => n !== EVENTOS_ALEATORIOS) : SCENARIO_KEYS;
  const evaluations = [];
  if (loopNames.length) {
    console.log(`Verificação offline em LOOP: ${ciclos} ciclos por execução (1º nominal, os outros com variação), `
      + `pausa calma de ${pausa} s, ${seeds} sementes por cenário`);
    console.log('Mesmo processamento da pulseira (borda.js): classifyAt (predict.js) → episódios (episodes.js) → gatilho (trigger.js)\n');
    for (const name of loopNames) evaluations.push(evaluateLoop(name, seeds, { ciclos, pausa }));
    printTable(LOOP_COLUMNS, evaluations.map((e) => e.linha), markdown);
    console.log(`\nDetalhes${markdown ? '' : ' (por ciclo)'}:\n`);
    printTable(LOOP_DETAIL_COLUMNS, evaluations.map((e) => e.detalhe), markdown);
    if (!markdown) evaluations.forEach(printLoopFailures);
  }

  if (!values.cenario || values.cenario === EVENTOS_ALEATORIOS) {
    const seed = Number.parseInt(values.seed, 10);
    const eventos = int(values.eventos, RANDOM_EVENTS);
    printRandom({ seed: seed >= 0 ? seed : RANDOM_SEED, eventos, pausa, markdown });
    const aggregate = Number.parseInt(values.agregado, 10);
    if (aggregate > 0) printRandomAggregate({ seeds: aggregate, eventos, pausa, markdown });
  }
  process.exitCode = summary(evaluations);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
