import { computeFeatures, predictCrisisProbability, riskTierFromProbability, MIN_HISTORY_REQUIRED, FEATURE_HISTORY } from './predict.js';

// Nivel do modelo para a leitura readings[index]. O modelo precisa de 31
// leituras terminando nela; as features com memoria olham ate FEATURE_HISTORY
// para tras, quando houver. Quem chama e a pulseira (simulator/borda.js, uma
// chamada por leitura nova), alem dos testes e do simulator/verificar.js.
export function classifyAt(readings, index) {
  if (index + 1 < MIN_HISTORY_REQUIRED) return { tier: 'baixo_risco', probability: null };
  const features = computeFeatures(readings.slice(Math.max(0, index + 1 - FEATURE_HISTORY), index + 1));
  if (!features) return { tier: 'baixo_risco', probability: null };
  const probability = predictCrisisProbability(features);
  return { tier: riskTierFromProbability(probability), probability };
}
