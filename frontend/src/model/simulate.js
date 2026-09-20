// Gera leituras sinteticas ao vivo a partir de controles manuais, sem
// depender do dataset. As magnitudes-base de cada acao do giroscopio foram
// calibradas pelas medias observadas no dataset original, so como ponto de
// partida realista - o ruido por leitura reproduz a variabilidade alta que
// os sensores reais (e o dataset) mostram mesmo dentro de uma mesma
// atividade.

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
// `movimentoRepetitivo` controla o indice de regularidade do acelerometro,
// INDEPENDENTE da intensidade do giroscopio - da pra simular tanto
// "correr com amigos" (movimento intenso, IRREGULAR) quanto uma
// estereotipia motora (intensidade qualquer, mas bem REGULAR/periodica).
export function generateReading({
  bpmTarget, edaTarget, gyroAction, idade, timestamp,
  hrvTarget, movimentoRepetitivo, luzTarget, ruidoTarget,
}) {
  const bpm = Math.round(clamp(bpmTarget + (Math.random() - 0.5) * 4, 40, 200));
  const eda_uS = Number(clamp(edaTarget + (Math.random() - 0.5) * 0.6, 1, 20).toFixed(2));

  const gyroBase = gyroBaseFor(gyroAction);
  const gyro_mag_dps = Number(clamp(gyroBase * (0.4 + Math.random() * 1.3), 0.05, 950).toFixed(2));

  const hrv_ms = Number(clamp(hrvTarget + (Math.random() - 0.5) * 4, 8, 120).toFixed(1));

  const accel_mag_g = Number(clamp(gyro_mag_dps * 0.55 * (0.5 + Math.random() * 1.1), 0.02, 20).toFixed(2));
  const regBase = movimentoRepetitivo ? 0.8 : 0.08;
  const regularidade = Number(clamp(regBase + (Math.random() - 0.5) * 0.2, 0, 1).toFixed(2));

  const luz_lux = Number(clamp(luzTarget + (Math.random() - 0.5) * 30, 5, 2000).toFixed(0));
  const ruido_db = Number(clamp(ruidoTarget + (Math.random() - 0.5) * 4, 20, 110).toFixed(1));

  return {
    timestamp, bpm, eda_uS, gyro_mag_dps, idade,
    hrv_ms, accel_mag_g, regularidade, luz_lux, ruido_db,
  };
}
