// Validacao das mensagens MQTT recebidas. Mensagens malformadas viram null
// (o chamador descarta) - nunca lancam excecao pra nao quebrar a tela.

// Campos numericos que model/predict.js (computeFeatures) usa de cada leitura.
const NUMERIC_FIELDS = [
  'bpm', 'eda_uS', 'gyro_mag_dps', 'hrv_ms', 'accel_mag_g',
  'regularidade', 'luz_lux', 'ruido_db', 'idade',
];

export function parseReading(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  if (typeof data.timestamp !== 'string' || Number.isNaN(Date.parse(data.timestamp))) return null;

  const reading = { timestamp: data.timestamp };
  for (const field of NUMERIC_FIELDS) {
    if (typeof data[field] !== 'number' || !Number.isFinite(data[field])) return null;
    reading[field] = data[field];
  }
  return reading;
}

// O status da pulseira e texto puro: "online" ou "offline".
export function parseBandStatus(text) {
  const value = text.trim().toLowerCase();
  return value === 'online' || value === 'offline' ? value : null;
}
