import { computeFeatures, predictCrisisProbability, riskTierFromProbability, MIN_HISTORY_REQUIRED } from './predict.js';

// Nivel do modelo para a leitura readings[index], usando as 31 leituras que
// terminam nela - o mesmo calculo que o App.jsx faz para a leitura mais
// recente. Usado pelo historico de episodios (uma chamada por leitura nova,
// inclusive nas velocidades 2x/4x) e pelos testes/simulador em Node.
export function classifyAt(readings, index) {
  if (index + 1 < MIN_HISTORY_REQUIRED) return { tier: 'baixo_risco', probability: null };
  const features = computeFeatures(readings.slice(index + 1 - MIN_HISTORY_REQUIRED, index + 1));
  if (!features) return { tier: 'baixo_risco', probability: null };
  const probability = predictCrisisProbability(features);
  return { tier: riskTierFromProbability(probability), probability };
}
