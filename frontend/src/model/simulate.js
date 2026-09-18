// Gera leituras sinteticas ao vivo a partir de controles manuais (BPM, EDA,
// acao do giroscopio), sem depender do dataset. As magnitudes-base de cada
// acao do giroscopio foram calibradas pelas medias observadas no dataset
// original (dataset_pulseira_TEA_estresse.xlsx), so como ponto de partida
// realista - o ruido por leitura reproduz a variabilidade alta que os
// sensores reais (e o dataset) mostram mesmo dentro de uma mesma atividade.

export const GYRO_ACTIONS = [
  { id: 'repouso', label: 'Repouso (parado)', base: 5 },
  { id: 'andando', label: 'Andando', base: 45 },
  { id: 'brincando', label: 'Brincando', base: 110 },
  { id: 'correndo', label: 'Correndo', base: 180 },
  { id: 'agitado', label: 'Agitado / estereotipia intensa', base: 250 },
];

const gyroBaseFor = (actionId) => GYRO_ACTIONS.find((a) => a.id === actionId)?.base ?? 5;

const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

// Uma leitura por "segundo simulado", com ruido em torno dos alvos atuais.
export function generateReading({ bpmTarget, edaTarget, gyroAction, idade, timestamp }) {
  const bpm = Math.round(clamp(bpmTarget + (Math.random() - 0.5) * 4, 40, 200));
  const eda_uS = Number(clamp(edaTarget + (Math.random() - 0.5) * 0.6, 1, 20).toFixed(2));

  const gyroBase = gyroBaseFor(gyroAction);
  const gyro_mag_dps = Number(clamp(gyroBase * (0.4 + Math.random() * 1.3), 0.05, 950).toFixed(2));

  return { timestamp, bpm, eda_uS, gyro_mag_dps, idade };
}
