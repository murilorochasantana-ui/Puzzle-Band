#!/usr/bin/env node
// Comparacao POR EPISODIO das versoes do modelo (docs/modelo.md, "Versao
// simplificada"). Para cada forest.json, monta uma copia da pulseira numa
// pasta temporaria (frontend/src/model + hooks + simulator/*.js) com aquele
// modelo e roda o simulator/verificar.js (seeds fixas) com os cenarios
// atuais e, com --cenarios-antigos <arquivo>, tambem com outro
// scenarios.js (ex.: o anterior a subida subita). Mede ainda o tempo de
// inferencia por leitura e o tamanho do arquivo.
//
// Roda (da raiz):
//   node model/comparar_episodios.mjs <forest.json>... [--cenarios-antigos <scenarios.js>] [--limiares 0.35,0.65]
// --limiares troca, so na copia, os limiares de atencao e possivel crise do
// predict.js (padrao 0,4 e 0,7).
// Os forest.json saem do model/comparar_modelos.py.

import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const CRISES = ['estereotipia', 'crise_ruido', 'crise_luz', 'crise_sem_gatilho', 'crise_ruido_e_luz', 'ruido_depois_da_crise', 'crise_e_recuperacao'];

const args = process.argv.slice(2);
const iAntigos = args.indexOf('--cenarios-antigos');
const antigos = iAntigos >= 0 ? args.splice(iAntigos, 2)[1] : null;
const iLimiares = args.indexOf('--limiares');
const limiares = iLimiares >= 0 ? args.splice(iLimiares, 2)[1].split(',').map(Number) : null;
const florestas = args;
if (!florestas.length) {
  console.error('Uso: node model/comparar_episodios.mjs <forest.json>... [--cenarios-antigos <scenarios.js>]');
  process.exit(1);
}

// Copia da pulseira com outro forest.json (e, se pedido, outro scenarios.js)
function montar(dir, floresta, cenarios) {
  for (const sub of ['frontend/src/model', 'frontend/src/hooks', 'simulator']) {
    mkdirSync(join(dir, sub), { recursive: true });
    for (const f of readdirSync(join(ROOT, sub))) {
      if (/\.(js|json)$/.test(f) && !f.includes('.test.') && f !== 'package-lock.json') cpSync(join(ROOT, sub, f), join(dir, sub, f));
    }
  }
  writeFileSync(join(dir, 'package.json'), '{"type":"module"}');
  cpSync(floresta, join(dir, 'frontend/src/model/forest.json'));
  if (cenarios) cpSync(cenarios, join(dir, 'simulator/scenarios.js'));
  if (limiares) {
    const arq = join(dir, 'frontend/src/model/predict.js');
    const [atencao, crise] = limiares;
    const novo = readFileSync(arq, 'utf8')
      .replace('if (p >= 0.7) return', `if (p >= ${crise}) return`)
      .replace('if (p >= 0.4) return', `if (p >= ${atencao}) return`);
    if (!novo.includes(`p >= ${crise}) return 'alto_risco'`) || !novo.includes(`p >= ${atencao}) return 'atencao'`)) throw new Error('limiares nao aplicados');
    writeFileSync(arq, novo);
  }
}

// "0/60 (37 limitação · 23 falharam)" -> { ok: 0, total: 60, limitacao: 37, falhou: 23 }
function contagem(texto) {
  const [, ok, total] = texto.match(/(\d+)\/(\d+)/);
  const lim = texto.match(/(\d+) limitação/);
  const fal = texto.match(/(\d+) falharam/);
  return { ok: +ok, total: +total, limitacao: lim ? +lim[1] : 0, falhou: fal ? +fal[1] : 0 };
}

function lerSaida(saida) {
  const linhas = saida.split('\n');
  const laco = {};
  const atraso = {};
  let tabela = null;
  for (const l of linhas) {
    if (l.startsWith('─')) continue; // linha separadora da tabela
    if (l.includes('Esperado em cada ciclo')) tabela = 'laco';
    else if (l.includes('1º ciclo (nominal)')) tabela = 'detalhe';
    else if (!l.includes('│')) tabela = l.trim() ? null : tabela;
    if (!tabela || !l.includes('│')) continue;
    const c = l.split('│').map((x) => x.trim());
    if (tabela === 'laco' && /^\d/.test(c[5] ?? '')) laco[c[0]] = contagem(c[5]);
    if (tabela === 'detalhe') {
      const m = (c[3] ?? '').match(/mediana (-?[\d,]+) s/);
      if (m) atraso[c[0]] = Number(m[1].replace(',', '.'));
    }
  }
  const agregado = saida.slice(saida.indexOf('agregado'));
  const num = (re) => agregado.match(re)?.slice(1).map((x) => Number(x.replace(',', '.')));
  const [detectadas, crises] = num(/Crises reais detectadas: (\d+) de (\d+)/);
  const [leve, leveTotal] = num(/leve (\d+)\/(\d+)/);
  const [exFalsos, exTotal] = num(/exercicio (\d+)\/(\d+)/);
  const [ambFalsos, ambTotal] = num(/ambiente_sem_crise (\d+)\/(\d+)/);
  const [gatilho] = num(/Gatilho certo: (\d+) de/);
  const [tempo] = num(/Tempo médio até o alerta: ([\d,]+) s/);
  const [foraEventos] = num(/Episódios fora dos eventos \(nas pausas\): (\d+)/);
  const crisesLaco = CRISES.reduce((s, n) => s + laco[n].ok, 0);
  return {
    detectadas, crises, leve, leveTotal, exFalsos, exTotal, ambFalsos, ambTotal, gatilho, tempo, foraEventos,
    calmo: laco.calmo,
    crisesLaco, crisesLacoTotal: CRISES.length * 60,
    exercicio: laco.exercicio, barulho: laco.barulho_sem_crise, demo: laco.demo,
    atrasoMediano: CRISES.map((n) => atraso[n]).filter(Number.isFinite),
  };
}

// Tempo de inferencia: classifyAt sobre 3.000 leituras de eventos_aleatorios
const MEDIR = `
import { classifyAt } from './frontend/src/model/classify.js';
import { generateReading } from './frontend/src/model/simulate.js';
import { programTicks, seeded, withRandom } from './simulator/scenarios.js';
const ticks = [...programTicks({ cenario: 'eventos_aleatorios', ciclos: 12, seed: 5 })].slice(0, 3000);
const leituras = withRandom(seeded(5), () => ticks.map((t) => generateReading({ ...t.alvos, timestamp: new Date(t.t * 1000).toISOString() })));
for (let i = 0; i < 300; i += 1) classifyAt(leituras, i); // aquecimento
const inicio = process.hrtime.bigint();
for (let i = 0; i < leituras.length; i += 1) classifyAt(leituras.slice(Math.max(0, i - 299), i + 1), Math.min(i, 299));
console.log(Number(process.hrtime.bigint() - inicio) / 1e6 / leituras.length);
`;

const pct = (n, d) => `${Math.round((100 * n) / d)}%`;
const resultados = [];
for (const floresta of florestas) {
  const nome = basename(floresta, '.json') + (limiares ? ` (${limiares.join(' / ')})` : '');
  const r = { nome, kb: statSync(floresta).size / 1024 };
  for (const [rotulo, cenarios] of [['novos', null], ['antigos', antigos]]) {
    if (rotulo === 'antigos' && !antigos) continue;
    const dir = mkdtempSync(join(tmpdir(), 'pb-comparacao-'));
    try {
      montar(dir, floresta, cenarios);
      let saida;
      try {
        saida = execFileSync(process.execPath, ['simulator/verificar.js'], { cwd: dir, encoding: 'utf8', maxBuffer: 1 << 26 });
      } catch (e) {
        saida = e.stdout; // sai com 1 quando algum cenario falha: a saida vale
      }
      r[rotulo] = lerSaida(saida);
      if (rotulo === 'novos') {
        writeFileSync(join(dir, 'medir.mjs'), MEDIR);
        r.msPorLeitura = Number(execFileSync(process.execPath, ['medir.mjs'], { cwd: dir, encoding: 'utf8' }));
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
  resultados.push(r);
  console.error(`${nome}: ok`);
}

writeFileSync(join(process.cwd(), 'comparacao_episodios.json'), JSON.stringify(resultados, null, 1));
for (const rotulo of ['novos', 'antigos']) {
  if (rotulo === 'antigos' && !antigos) continue;
  console.log(`\n### Cenários ${rotulo === 'novos' ? 'com subida súbita (70%) e gradual' : 'antigos (subida de 30 s)'}\n`);
  console.log('| Versão | Crises detectadas (1000 eventos) | Leves | Crises certas no laço | Exercício no laço: sem alerta · só atenção · possível crise | Exercício (eventos) com alarme | barulho_sem_crise sem alerta | Ambiente (eventos) com alarme | calmo sem alerta | Episódios nas pausas (eventos) | demo certa | Alerta após a fisiologia (média) | Gatilho certo | ms/leitura | KB |');
  console.log('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of resultados) {
    const x = r[rotulo];
    console.log(`| ${r.nome} | ${x.detectadas}/${x.crises} | ${x.leve}/${x.leveTotal} | ${x.crisesLaco}/${x.crisesLacoTotal} | `
      + `${x.exercicio.ok} · ${x.exercicio.limitacao} · ${x.exercicio.falhou} (de ${x.exercicio.total}) | ${x.exFalsos}/${x.exTotal} (${pct(x.exFalsos, x.exTotal)}) | `
      + `${x.barulho.ok}/${x.barulho.total} | ${x.ambFalsos}/${x.ambTotal} | ${x.calmo.ok}/${x.calmo.total} | ${x.foraEventos} | ${x.demo.ok}/${x.demo.total} | ${String(x.tempo).replace('.', ',')} s | `
      + `${x.gatilho}/${x.detectadas} | ${r.msPorLeitura.toFixed(3).replace('.', ',')} | ${Math.round(r.kb)} |`);
  }
}
