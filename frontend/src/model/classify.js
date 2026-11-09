import { computeFeatures, predictCrisisProbability, riskTierFromProbability, MIN_HISTORY_REQUIRED, FEATURE_HISTORY } from './predict.js';
import { CONTEXTO, POLITICA, contextoDe, politicaAtiva, tetoAtivo } from './contexto.js';

const LIMIAR_ATENCAO = 0.4; // o mesmo de riskTierFromProbability

const probabilityAt = (readings, index) => {
  const features = computeFeatures(readings.slice(Math.max(0, index + 1 - FEATURE_HISTORY), index + 1));
  return features ? predictCrisisProbability(features) : null;
};

// Nivel do modelo para a leitura readings[index]. O modelo precisa de 31
// leituras terminando nela; as features com memoria olham ate FEATURE_HISTORY
// para tras, quando houver. Quem chama e a pulseira (simulator/borda.js, uma
// chamada por leitura nova), alem dos testes e do simulator/verificar.js.
// Com uma POLITICA de contexto (contexto.js; padrao null = desligada), o
// nivel pode exigir persistencia ou ser rebaixado no exercicio.
export function classifyAt(readings, index, politica = POLITICA) {
  if (index + 1 < MIN_HISTORY_REQUIRED) return { tier: 'baixo_risco', probability: null };
  const probability = probabilityAt(readings, index);
  if (probability === null) return { tier: 'baixo_risco', probability: null };
  let tier = riskTierFromProbability(probability);
  if (politica && tier !== 'baixo_risco') {
    const ctx = contextoDe(readings.slice(Math.max(0, index + 1 - CONTEXTO.janelaBaseS), index + 1));
    if (politicaAtiva(ctx, CONTEXTO, politica)) {
      if (politica.tipo === 'rebaixa') {
        tier = 'atencao';
      } else {
        // persistencia: p >= limiar de atencao em cada um dos ultimos N s
        for (let k = 1; k < politica.n && tier !== 'baixo_risco'; k += 1) {
          const p = index - k + 1 >= MIN_HISTORY_REQUIRED ? probabilityAt(readings, index - k) : null;
          if (p === null || p < LIMIAR_ATENCAO) tier = 'baixo_risco';
        }
        // teto: no exercicio sem sinal de crise, no maximo "atencao" (o
        // episodio do exercicio nao chega a possivel crise; uma crise que
        // comece dentro dele ainda sobe o nivel e notifica)
        if (politica.teto === 'atencao' && tier === 'alto_risco') tier = 'atencao';
      }
    }
    if (politica.teto === 'atencao_eda' && tier === 'alto_risco' && tetoAtivo(ctx)) tier = 'atencao';
  }
  return { tier, probability };
}
