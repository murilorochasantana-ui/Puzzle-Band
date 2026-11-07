// Configuracao do simulator/.env (ver .env.example), usada pela pulseira
// (index.js) e pelo reset (resetar.js). Erro de configuracao encerra o
// processo com uma mensagem que diz o que fazer.

import { existsSync } from 'node:fs';
import dotenv from 'dotenv';

export const CHILD_ID_PATTERN = /^[A-Za-z0-9_-]+$/;

function fail(message) {
  console.error(`Erro: ${message}`);
  process.exit(1);
}

export function loadConfig(envPath) {
  const hasEnvFile = existsSync(envPath);
  if (hasEnvFile) dotenv.config({ path: envPath, quiet: true });

  const config = {
    url: process.env.MQTT_URL?.trim(),
    username: process.env.MQTT_USER?.trim(),
    password: process.env.MQTT_PASS,
    childId: process.env.CHILD_ID?.trim(),
  };
  const missing = [
    ['MQTT_URL', config.url],
    ['MQTT_USER', config.username],
    ['MQTT_PASS', config.password],
    ['CHILD_ID', config.childId],
  ].filter(([, v]) => !v).map(([name]) => name);

  if (missing.length && !hasEnvFile) {
    console.error(`Erro: arquivo simulator/.env não encontrado.

Crie-o a partir do modelo, dentro da pasta simulator/:
  copy .env.example .env      (Windows)
  cp .env.example .env        (Linux/macOS)

e preencha MQTT_USER e MQTT_PASS com o usuário da pulseira no EMQX Cloud.
O .env fica fora do Git (simulator/.gitignore): nunca commite a senha.`);
    process.exit(1);
  }
  if (missing.length) fail(`faltam variáveis no simulator/.env: ${missing.join(', ')} (veja .env.example).`);

  if (!/^(mqtts?|wss?):\/\//.test(config.url)) {
    fail(`MQTT_URL inválida: "${config.url}". Use mqtts://host:8883 (ou mqtt://, ws://, wss://).`);
  }
  if (!CHILD_ID_PATTERN.test(config.childId)) {
    fail(`CHILD_ID inválido: "${config.childId}". Use só letras, números, _ ou - (vira parte do tópico MQTT).`);
  }
  const host = new URL(config.url).hostname;
  if (/^(mqtt|ws):/.test(config.url) && !['localhost', '127.0.0.1', '::1'].includes(host)) {
    console.warn('Aviso: MQTT_URL sem TLS (mqtt:// ou ws://): usuário e senha trafegam sem criptografia.');
  }
  return config;
}

// Erros de rede podem vir como AggregateError sem "message" (IPv6 + IPv4)
const NETWORK_HINTS = {
  ECONNREFUSED: 'conexão recusada (broker fora do ar ou porta errada)',
  ENOTFOUND: 'endereço do broker não encontrado (confira MQTT_URL e a internet)',
  ETIMEDOUT: 'tempo esgotado (rede lenta ou firewall bloqueando a porta)',
  ECONNRESET: 'conexão interrompida pelo broker',
};

export function describeError(err) {
  const code = err.code ?? err.errors?.[0]?.code;
  const detail = err.message || err.errors?.map((e) => e.message).join('; ') || code || 'erro desconhecido';
  return NETWORK_HINTS[code] ? `${NETWORK_HINTS[code]} — ${detail}` : detail;
}

export const AUTH_ERROR_CODES = new Set([4, 5, 134, 135]); // MQTT 3.1.1 e 5
