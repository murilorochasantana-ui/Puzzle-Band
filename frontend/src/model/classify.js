import { computeFeatures, predictCrisisProbability, riskTierFromProbability, MIN_HISTORY_REQUIRED } from './predict.js';

// Nivel do modelo para a leitura readings[index], usando as 31 leituras que
// terminam nela. Quem chama e a pulseira (simulator/borda.js, uma chamada por
// leitura nova), alem dos testes e do simulator/verificar.js.
export function classifyAt(readings, index) {
  if (index + 1 < MIN_HISTORY_REQUIRED) return { tier: 'baixo_risco', probability: null };
  const features = computeFeatures(readings.slice(index + 1 - MIN_HISTORY_REQUIRED, index + 1));
  if (!features) return { tier: 'baixo_risco', probability: null };
  const probability = predictCrisisProbability(features);
  return { tier: riskTierFromProbability(probability), probability };
}
