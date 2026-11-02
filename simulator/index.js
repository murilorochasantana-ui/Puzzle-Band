#!/usr/bin/env node
// Simulador da pulseira Puzzle Band (ESP32) - publica 1 leitura por segundo
// no broker MQTT, no mesmo formato que o dashboard (modo "Pulseira (MQTT)")
// espera. As leituras vem do MESMO gerador do simulador manual do dashboard
// (frontend/src/model/simulate.js); os cenarios ficam em scenarios.js.
//
//   node index.js --cenario crise_ruido [--idade 8] [--duracao 300]
//
// Configuracao em simulator/.env (ver .env.example).

import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import dotenv from 'dotenv';
import mqtt from 'mqtt';
import { generateReading } from '../frontend/src/model/simulate.js';
import { SCENARIOS, SCENARIO_NAMES, describeTimeline, scenarioAt } from './scenarios.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ENV_PATH = join(HERE, '.env');
const IDADE_MIN = 5;
const IDADE_MAX = 12; // mesma faixa do controle de idade do dashboard

const USAGE = `Uso: node index.js --cenario <nome> [--idade <anos>] [--duracao <segundos>]
     npm start -- --cenario <nome> ...      (ou um atalho: npm run crise-ruido -- --duracao 300)

  --cenario   um dos cenários abaixo (padrão: calmo)
  --idade     idade da criança, ${IDADE_MIN} a ${IDADE_MAX} anos (padrão: 8)
  --duracao   para depois de N segundos (padrão: sem fim, até Ctrl+C)`;

function scenarioList() {
  const width = Math.max(...SCENARIO_NAMES.map((n) => n.length));
  return SCENARIO_NAMES.map((n) => `  ${n.padEnd(width)}  ${SCENARIOS[n].descricao}`).join('\n');
}

function fail(message, { showUsage = false, showScenarios = false } = {}) {
  console.error(`Erro: ${message}`);
  if (showScenarios) console.error(`\nCenários válidos:\n${scenarioList()}`);
  if (showUsage) console.error(`\n${USAGE}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Argumentos
// ---------------------------------------------------------------------------

function parseCli() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        cenario: { type: 'string', default: 'calmo' },
        idade: { type: 'string', default: '8' },
        duracao: { type: 'string' },
        ajuda: { type: 'boolean', short: 'h' },
        help: { type: 'boolean' },
      },
      strict: true,
      allowPositionals: false,
    }));
  } catch (err) {
    const messages = {
      ERR_PARSE_ARGS_UNKNOWN_OPTION: 'opção desconhecida',
      ERR_PARSE_ARGS_INVALID_OPTION_VALUE: 'opção sem valor ou com valor inválido',
      ERR_PARSE_ARGS_UNEXPECTED_POSITIONAL: 'argumento inesperado (use --opcao valor)',
    };
    fail(`${messages[err.code] ?? 'argumentos inválidos'}: ${err.message}`, { showUsage: true });
  }

  if (values.ajuda || values.help) {
    console.log(`${USAGE}\n\nCenários:\n${scenarioList()}`);
    process.exit(0);
  }

  const cenario = values.cenario.trim();
  if (!SCENARIOS[cenario]) fail(`cenário inválido: "${cenario}".`, { showScenarios: true });

  const idade = Number(values.idade);
  if (!Number.isInteger(idade) || idade < IDADE_MIN || idade > IDADE_MAX) {
    fail(`--idade deve ser um número inteiro de ${IDADE_MIN} a ${IDADE_MAX} (recebido: "${values.idade}").`);
  }

  let duracao = Infinity;
  if (values.duracao !== undefined) {
    duracao = Number(values.duracao);
    if (!Number.isInteger(duracao) || duracao <= 0) {
      fail(`--duracao deve ser um número inteiro de segundos maior que zero (recebido: "${values.duracao}").`);
    }
  }
  return { cenario, idade, duracao };
}

// ---------------------------------------------------------------------------
// Configuracao (.env)
// ---------------------------------------------------------------------------

function loadConfig() {
  const hasEnvFile = existsSync(ENV_PATH);
  if (hasEnvFile) dotenv.config({ path: ENV_PATH, quiet: true });

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
  if (!/^[A-Za-z0-9_-]+$/.test(config.childId)) {
    fail(`CHILD_ID inválido: "${config.childId}". Use só letras, números, _ ou - (vira parte do tópico MQTT).`);
  }
  const host = new URL(config.url).hostname;
  if (/^(mqtt|ws):/.test(config.url) && !['localhost', '127.0.0.1', '::1'].includes(host)) {
    console.warn('Aviso: MQTT_URL sem TLS (mqtt:// ou ws://): usuário e senha trafegam sem criptografia.');
  }
  return config;
}

// ---------------------------------------------------------------------------
// Saida no terminal
// ---------------------------------------------------------------------------

function formatElapsed(t) {
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = t % 60;
  const mmss = `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return h ? `${h}:${mmss}` : mmss;
}

// [tempo] bpm, eda, hrv, gyro, reg, luz, ruido | fase
function formatReading(t, r, fase, sent) {
  const cols = [
    `bpm ${String(r.bpm).padStart(3)}`,
    `eda ${r.eda_uS.toFixed(2).padStart(5)}`,
    `hrv ${r.hrv_ms.toFixed(1).padStart(5)}`,
    `gyro ${r.gyro_mag_dps.toFixed(1).padStart(5)}`,
    `reg ${r.regularidade.toFixed(2)}`,
    `luz ${String(r.luz_lux).padStart(4)}`,
    `ruido ${r.ruido_db.toFixed(1).padStart(5)}`,
  ];
  return `[${formatElapsed(t)}] ${cols.join('  ')} | ${fase}${sent ? '' : '  (não enviada: sem conexão)'}`;
}

// ---------------------------------------------------------------------------
// Simulacao
// ---------------------------------------------------------------------------

const AUTH_ERROR_CODES = new Set([4, 5, 134, 135]); // MQTT 3.1.1 e 5

const NETWORK_HINTS = {
  ECONNREFUSED: 'conexão recusada (broker fora do ar ou porta errada)',
  ENOTFOUND: 'endereço do broker não encontrado (confira MQTT_URL e a internet)',
  ETIMEDOUT: 'tempo esgotado (rede lenta ou firewall bloqueando a porta)',
  ECONNRESET: 'conexão interrompida pelo broker',
};

// Erros de rede podem vir como AggregateError sem "message" (IPv6 + IPv4)
function describeError(err) {
  const code = err.code ?? err.errors?.[0]?.code;
  const detail = err.message || err.errors?.map((e) => e.message).join('; ') || code || 'erro desconhecido';
  return NETWORK_HINTS[code] ? `${NETWORK_HINTS[code]} — ${detail}` : detail;
}

function main() {
  const { cenario, idade, duracao } = parseCli();
  const config = loadConfig();

  const base = `puzzleband/${config.childId}`;
  const topicReadings = `${base}/leituras`;
  const topicStatus = `${base}/status`;

  console.log('Puzzle Band — simulador da pulseira (ESP32)');
  console.log(`Cenário: ${cenario} — ${SCENARIOS[cenario].descricao}`);
  console.log(`Linha do tempo: ${describeTimeline(cenario)}`);
  console.log(`Roteiro: ${SCENARIOS[cenario].duracao} s (depois tudo fica calmo; --duracao ${SCENARIOS[cenario].duracao} para parar sozinho)`);
  console.log(`Criança: ${config.childId} · idade ${idade} · duração: ${Number.isFinite(duracao) ? `${duracao} s` : 'sem fim (Ctrl+C para parar)'}`);
  console.log(`Broker: ${config.url} (usuário ${config.username})`);
  console.log(`Tópicos: ${topicReadings} (QoS 0) · ${topicStatus} (retain)`);
  console.log('Conectando...');

  const client = mqtt.connect(config.url, {
    username: config.username,
    password: config.password,
    clientId: `puzzleband-sim-${config.childId}-${Math.random().toString(16).slice(2, 8)}`,
    clean: true,
    keepalive: 15, // sem resposta por ~22 s, o broker publica o Last Will
    reconnectPeriod: 3000,
    connectTimeout: 10000,
    queueQoSZero: false, // leitura velha nao serve: sem conexao, descarta
    will: { topic: topicStatus, payload: 'offline', qos: 1, retain: true },
  });

  let t = 0;
  let timer = null;
  let stopping = false;
  let wasConnected = false;

  async function shutdown(reason, exitCode = 0) {
    if (stopping) {
      console.log('Saindo sem esperar o broker.');
      process.exit(exitCode || 1);
    }
    stopping = true;
    clearInterval(timer);
    console.log(`\nEncerrando (${reason})...`);
    const forceExit = setTimeout(() => {
      console.error('O broker não respondeu a tempo; saindo mesmo assim (o Last Will publica "offline").');
      process.exit(exitCode || 1);
    }, 5000);
    try {
      if (client.connected) {
        await client.publishAsync(topicStatus, 'offline', { qos: 1, retain: true });
        console.log(`status: offline (retain) em ${topicStatus}`);
        await client.endAsync();
      } else {
        console.log('Sem conexão com o broker: o "offline" fica por conta do Last Will.');
        await client.endAsync(true);
      }
      console.log('Desconectado.');
    } catch (err) {
      console.error(`Erro ao encerrar: ${describeError(err)}`);
      exitCode = exitCode || 1;
    }
    clearTimeout(forceExit);
    process.exit(exitCode);
  }

  function tick() {
    if (stopping) return;
    const { alvos, fase } = scenarioAt(cenario, t, { idade });
    const reading = generateReading({ ...alvos, timestamp: new Date().toISOString() });
    const sent = client.connected;
    if (sent) client.publish(topicReadings, JSON.stringify(reading), { qos: 0 });
    console.log(formatReading(t, reading, fase, sent));
    t += 1;
    if (t >= duracao) shutdown(`duração de ${duracao} s atingida`);
  }

  client.on('connect', () => {
    console.log(wasConnected ? 'Reconectado.' : 'Conectado ao broker.');
    wasConnected = true;
    // A cada (re)conexao: o broker pode ter publicado o Last Will no meio tempo
    client.publish(topicStatus, 'online', { qos: 1, retain: true });
    console.log(`status: online (retain) em ${topicStatus}`);
    if (!timer && !stopping) {
      // o relogio do cenario so comeca com o broker conectado
      timer = setInterval(tick, 1000);
      tick();
    }
  });

  client.on('reconnect', () => {
    if (!stopping) console.log('Tentando reconectar...');
  });

  client.on('offline', () => {
    if (!stopping && wasConnected) console.log('Conexão perdida; as leituras seguem no terminal até reconectar.');
  });

  client.on('error', (err) => {
    if (AUTH_ERROR_CODES.has(err.code)) {
      console.error(`Erro: o broker recusou o login (${err.message}). Confira MQTT_USER e MQTT_PASS no simulator/.env.`);
      client.end(true);
      process.exit(1);
    }
    console.error(`Erro de conexão: ${describeError(err)}`);
  });

  process.on('SIGINT', () => shutdown('Ctrl+C'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  if (process.platform === 'win32') process.on('SIGBREAK', () => shutdown('Ctrl+Break'));
}

main();
