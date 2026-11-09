// Contexto de atividade e politica de alerta (estudo "exercicio x crise",
// docs/modelo.md). Funcoes puras sobre o historico de leituras (mais antiga
// -> mais recente), as mesmas que classify.js recebe.
//
// POLITICA = null: nada muda (o nivel sai so da probabilidade). Em producao
// desde 11/2026 (aprovada no estudo, "E4d 30 s"): quando houve exercicio
// irregular nos ultimos 60 s e nem a EDA nem o batimento acima do esperado
// pelo movimento estao elevados (e o batimento tambem nao esta muito ABAIXO
// do esperado), o alerta exige persistencia (p >= limiar de atencao em cada
// um dos ultimos 30 s); e, no exercicio sem EDA elevada, o nivel fica no
// maximo em "atencao" (teto), para uma crise que comece dentro do episodio
// ainda subir o nivel e notificar. As outras variantes (rebaixa, teto
// 'atencao', sem bilateral) ficam para reproduzir o estudo.
//
// Movimento = giroscopio (o acelerometro do dataset e uma copia saturada do
// giroscopio: docs/modelo.md, limitacao da escala do acelerometro).

export const POLITICA = Object.freeze({ tipo: 'persistencia', n: 30, bilateral: true, teto: 'atencao_eda' });

// Limites tirados do dataset v4 (model/gerar_dataset_v4.py), nao do simulador:
//   giroscopio: repouso ~5, atividade leve ~48, brincadeira ativa ~112 dps
//   regularidade: movimento livre < 0,15; estereotipia 0,65-0,95
//   brincadeira ativa: BPM +38 para +107 dps (0,34 bpm/dps), EDA +2,6 uS
//   crise "leve": BPM +11, EDA +2,1; "alto": BPM +38, EDA +7,1
export const CONTEXTO = Object.freeze({
  janelaMovimentoS: 10, // media curta do giroscopio e da regularidade
  memoriaExercicioS: 60, // exercicio nos ultimos 60 s (inclui a desaceleracao)
  giroExercicio: 40, // dps
  regularidadeRepetitiva: 0.4, // acima disso: movimento repetitivo, nunca exercicio
  janelaBaseS: 300, // linha de base: percentil 10 dos ultimos 300 s
  bpmPorGiro: 0.34, // bpm por dps (exercicio do v4)
  edaElevada: 3.5, // uS acima da linha de base (exercicio ~2,6; exercicio + crise leve ~4,7)
  bpmResiduoElevado: 10, // bpm acima do esperado pelo movimento
});

const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
function percentil10(values) {
  const s = [...values].sort((a, b) => a - b);
  return s[Math.floor(0.1 * (s.length - 1))];
}

// Contexto no fim do historico:
//   atividade        'repouso' | 'exercicio_irregular' | 'repetitivo'
//   exercicioRecente houve exercicio irregular nos ultimos memoriaExercicioS
//   edaAcimaBase     uS da media de 5 s acima da linha de base
//   bpmResiduo       bpm da media de 5 s acima da linha de base, menos o que o
//                    movimento (media curta acima da base) explicaria
export function contextoDe(history, c = CONTEXTO) {
  const n = history.length;
  const atividadeEm = (end) => {
    const w = history.slice(Math.max(0, end - c.janelaMovimentoS), end);
    const giro = mean(w.map((r) => r.gyro_mag_dps));
    const reg = mean(w.map((r) => r.regularidade));
    if (reg >= c.regularidadeRepetitiva) return 'repetitivo';
    return giro >= c.giroExercicio ? 'exercicio_irregular' : 'repouso';
  };
  const atividade = atividadeEm(n);
  let exercicioRecente = false;
  for (let end = n; end > Math.max(0, n - c.memoriaExercicioS) && !exercicioRecente; end -= 1) {
    exercicioRecente = atividadeEm(end) === 'exercicio_irregular';
  }
  const base = history.slice(Math.max(0, n - c.janelaBaseS));
  const ult5 = history.slice(-5);
  const ultMov = history.slice(-c.janelaMovimentoS);
  const edaAcimaBase = mean(ult5.map((r) => r.eda_uS)) - percentil10(base.map((r) => r.eda_uS));
  const giroAcimaBase = Math.max(0, mean(ultMov.map((r) => r.gyro_mag_dps)) - percentil10(base.map((r) => r.gyro_mag_dps)));
  const bpmResiduo = mean(ult5.map((r) => r.bpm)) - percentil10(base.map((r) => r.bpm)) - c.bpmPorGiro * giroAcimaBase;
  return { atividade, exercicioRecente, edaAcimaBase, bpmResiduo };
}

// A politica se aplica? (exercicio recente, movimento nao repetitivo agora, e
// nem EDA nem batimento acima do esperado). Com `bilateral`, o batimento
// tambem nao pode estar muito ABAIXO do esperado pelo movimento: so relaxa o
// alerta quando o batimento e explicado pelo movimento (|residuo| pequeno).
// Movimento intenso com pouco batimento nao e um exercicio tipico (ex.:
// crise agitada com pouca resposta cardiaca).
// Teto de "atencao" (politica.teto = 'atencao_eda'): exercicio recente, nao
// repetitivo, EDA nao elevada e batimento nao muito ABAIXO do esperado. Nao
// olha se o batimento esta ACIMA do esperado (o residuo oscila perto do
// limite no exercicio): so a EDA libera a "possivel crise".
export function tetoAtivo(ctx, c = CONTEXTO) {
  return ctx.exercicioRecente && ctx.atividade !== 'repetitivo'
    && ctx.edaAcimaBase < c.edaElevada && ctx.bpmResiduo > -c.bpmResiduoElevado;
}

export function politicaAtiva(ctx, c = CONTEXTO, politica = null) {
  return ctx.exercicioRecente && ctx.atividade !== 'repetitivo'
    && ctx.edaAcimaBase < c.edaElevada && ctx.bpmResiduo < c.bpmResiduoElevado
    && (!politica?.bilateral || ctx.bpmResiduo > -c.bpmResiduoElevado);
}
