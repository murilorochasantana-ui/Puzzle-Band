#!/usr/bin/env node
// Tabela por episodio do estudo "exercicio x crise" (docs/modelo.md), a
// partir dos JSON do model/comparar_episodios.mjs (--saida). A primeira
// versao e a referencia da comparacao pareada (mesma semente e ciclo) do
// tempo ate o alerta.
//
//   node model/tabela_estudo.mjs <atual.json> <versao.json>...

import { readFileSync } from 'node:fs';

const arquivos = process.argv.slice(2);
const versoes = arquivos.map((f) => JSON.parse(readFileSync(f, 'utf8'))[0]);
const ref = versoes[0];
const NIVEIS = ['leve', 'moderada', 'alta'];
const dec = (x) => String(Math.round(x * 10) / 10).replace('.', ',');
const mediana = (a) => {
  const s = [...a].sort((x, y) => x - y);
  return s.length ? s[Math.floor(s.length / 2)] : null;
};

function novos(r, cenario) {
  return NIVEIS.map((nivel) => {
    const ciclos = r.extras[`${cenario}:${nivel}`];
    const det = ciclos.filter((c) => c.det).length;
    const engolidas = ciclos.filter((c) => c.como === 'engolida').length;
    const t = ciclos.filter((c) => c.det).map((c) => c.t);
    // atraso pareado contra a referencia (mesma semente e ciclo, as duas detectadas)
    const base = ref.extras[`${cenario}:${nivel}`];
    const atrasos = ciclos.map((c, i) => (c.det && base[i].det ? c.t - base[i].t : null)).filter((x) => x !== null);
    const perdidasVsRef = ciclos.filter((c, i) => !c.det && base[i].det).length;
    return { nivel, det, total: ciclos.length, engolidas, tMed: mediana(t), tMax: t.length ? Math.max(...t) : null,
      atrasoMax: atrasos.length ? Math.max(...atrasos) : null, perdidasVsRef,
      ok: ciclos.filter((c) => c.resultado === 'ok').length };
  });
}

console.log('### Por episódio (simulador)\n');
console.log('| Versão | Crises detectadas (1000 eventos) | Crises certas no laço (7 cenários antigos) | crise_com_agitacao detectadas (leve · moderada · alta, de 60) | exercicio_e_crise detectadas (leve · moderada · alta, de 60) | exercicio_e_crise engolidas | Exercício no laço: sem alerta · só atenção · possível crise (de 60) | Exercício (eventos) com alarme | barulho_sem_crise sem alerta (de 60) | calmo sem alerta (de 60) | Episódios nas pausas (eventos) | Alerta após a fisiologia (eventos, média) | ms/leitura |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|---|');
for (const r of versoes) {
  const x = r.novos;
  const ag = novos(r, 'crise_com_agitacao');
  const ec = novos(r, 'exercicio_e_crise');
  console.log(`| ${r.nome} | ${x.detectadas}/${x.crises} | ${x.crisesLaco}/${x.crisesLacoTotal} | ${ag.map((a) => a.det).join(' · ')} | `
    + `${ec.map((a) => a.det).join(' · ')} | ${ec.map((a) => a.engolidas).join(' · ')} | `
    + `${x.exercicio.ok} · ${x.exercicio.limitacao} · ${x.exercicio.falhou} | ${x.exFalsos}/${x.exTotal} | ${x.barulho.ok} | ${x.calmo.ok} | `
    + `${x.foraEventos} | ${dec(x.tempo)} s | ${r.msPorLeitura.toFixed(3).replace('.', ',')} |`);
}

console.log('\n### Tempo até o alerta da crise nos cenários novos (s desde o início da alteração fisiológica)\n');
console.log('| Versão | Cenário | Intensidade | Detectadas | Mediana | Máximo | Maior atraso contra o atual (mesmo ciclo) | Perdidas que o atual detectava | Ciclos "ok" (sem nenhum alarme falso) |');
console.log('|---|---|---|---|---|---|---|---|---|');
for (const r of versoes) {
  for (const cenario of ['exercicio_e_crise', 'crise_com_agitacao']) {
    for (const a of novos(r, cenario)) {
      console.log(`| ${r.nome} | ${cenario} | ${a.nivel} | ${a.det}/${a.total} | ${a.tMed ?? '—'} | ${a.tMax ?? '—'} | `
        + `${a.atrasoMax === null ? '—' : `${a.atrasoMax > 0 ? '+' : ''}${a.atrasoMax}`} | ${a.perdidasVsRef} | ${a.ok}/${a.total} |`);
    }
  }
}
