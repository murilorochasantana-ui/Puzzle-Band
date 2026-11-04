#!/usr/bin/env node
// Simulador da pulseira Puzzle Band (ESP32) - publica 1 leitura por segundo
// no broker MQTT, no mesmo formato que o dashboard (modo "Pulseira (MQTT)")
// espera. As leituras vem do MESMO gerador do simulador manual do dashboard
// (frontend/src/model/simulate.js); os cenarios ficam em scenarios.js.
//
// Por padrao o cenario roda em LOOP (ciclo -> pausa calma -> ciclo ...) ate
// o Ctrl+C; o 1o ciclo e o roteiro nominal e os seguintes variam um pouco.
//
//   node index.js --cenario crise_ruido [--ciclos 3] [--pausa 120] [--seed 42]
//   node index.js --cenario crise_ruido --uma-vez          # roteiro nominal e encerra
//   node index.js --cenario eventos_aleatorios --ciclos 20 --seed 42
//
// Cada evento/ciclo vira uma linha do gabarito em logs/eventos_<data-hora>.csv
// (e .json). Configuracao em simulator/.env (ver .env.example).

import { randomInt } from 'node:crypto';
import { existsSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import dotenv from 'dotenv';
import mqtt from 'mqtt';
import { generateReading } from '../frontend/src/model/simulate.js';
import {
  EVENTOS_ALEATORIOS, INTENSIDADES, PAUSA_MIN_S, PAUSA_PADRAO_S, SCENARIOS, SCENARIO_NAMES, TIPOS_DE_EVENTO, VARIACAO_LIMITES,
  cycleBanner, cycleDetails, describeTimeline, nominalScenario, programTicks, scenarioDescription, seeded, withRandom,
} from './scenarios.js';
import { createGabaritoWriter, gabaritoEntry } from './gabarito.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ENV_PATH = join(HERE, '.env');
const LOGS_DIR = join(HERE, 'logs');
const IDADE_MIN = 5;
const IDADE_MAX = 12; // mesma faixa do controle de idade do dashboard
const SEED_MAX = 4294967295;

const USAGE = `Uso: node index.js --cenario <nome> [opções]
     npm start -- --cenario <nome> ...      (ou um atalho: npm run crise-ruido -- --ciclos 3)

  --cenario   um dos cenários abaixo (padrão: calmo)
  --idade     idade da criança, ${IDADE_MIN} a ${IDADE_MAX} anos (padrão: 8)
  --uma-vez   só o roteiro nominal, uma vez, e encerra (comportamento antigo)
  --ciclos    roda N ciclos (no eventos_aleatorios, N eventos) e encerra (padrão: loop até Ctrl+C)
  --pausa     segundos de pausa calma entre ciclos (padrão: ${PAUSA_PADRAO_S}; mínimo ${PAUSA_MIN_S});
              no eventos_aleatorios a pausa é sorteada entre S e 2×S (padrão: ${PAUSA_PADRAO_S}–${2 * PAUSA_PADRAO_S} s)
  --seed      semente do sorteio e do ruído dos sensores (mesma seed = mesma sequência)
  --duracao   para depois de N segundos, em qualquer modo`;

function scenarioList() {
  const width = Math.max(...SCENARIO_NAMES.map((n) => n.length));
  return SCENARIO_NAMES.map((n) => `  ${n.padEnd(width)}  ${scenarioDescription(n)}`).join('\n');
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
        'uma-vez': { type: 'boolean', default: false },
        ciclos: { type: 'string' },
        pausa: { type: 'string' },
        seed: { type: 'string' },
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
  if (!SCENARIO_NAMES.includes(cenario)) fail(`cenário inválido: "${cenario}".`, { showScenarios: true });

  const idade = Number(values.idade);
  if (!Number.isInteger(idade) || idade < IDADE_MIN || idade > IDADE_MAX) {
    fail(`--idade deve ser um número inteiro de ${IDADE_MIN} a ${IDADE_MAX} (recebido: "${values.idade}").`);
  }

  const positiveInt = (name, raw, what) => {
    const n = Number(raw);
    if (!Number.isInteger(n) || n <= 0) fail(`--${name} deve ser ${what} (recebido: "${raw}").`);
    return n;
  };

  const duracao = values.duracao === undefined ? Infinity : positiveInt('duracao', values.duracao, 'um número inteiro de segundos maior que zero');

  let umaVez = values['uma-vez'];
  if (umaVez && values.ciclos !== undefined) fail('use --uma-vez OU --ciclos, não os dois.');
  let ciclos = values.ciclos === undefined ? Infinity : positiveInt('ciclos', values.ciclos, 'um número inteiro maior que zero');
  if (umaVez && cenario === EVENTOS_ALEATORIOS) {
    // nao ha roteiro nominal: --uma-vez = um evento sorteado (+ pausa final)
    umaVez = false;
    ciclos = 1;
  }

  let pausa = PAUSA_PADRAO_S;
  if (values.pausa !== undefined) {
    pausa = positiveInt('pausa', values.pausa, 'um número inteiro de segundos');
    if (umaVez && cenario !== EVENTOS_ALEATORIOS) console.warn('Aviso: --pausa não se aplica com --uma-vez (não há segundo ciclo).');
    if (pausa < PAUSA_MIN_S) {
      console.warn(`Aviso: --pausa ${pausa} é menor que o mínimo de ${PAUSA_MIN_S} s (30 s para o episódio anterior fechar no site`
        + ` + 60 s de linha de base calma para o gatilho). Usando ${PAUSA_MIN_S} s.`);
      pausa = PAUSA_MIN_S;
    }
  }

  let seed;
  if (values.seed === undefined) {
    seed = randomInt(1, 1000000); // sorteada, mas impressa no inicio e gravada no gabarito
  } else {
    seed = Number(values.seed);
    if (!Number.isInteger(seed) || seed < 0 || seed > SEED_MAX) {
      fail(`--seed deve ser um número inteiro de 0 a ${SEED_MAX} (recebido: "${values.seed}").`);
    }
  }
  return { cenario, idade, duracao, umaVez, ciclos, pausa, seed, seedInformada: values.seed !== undefined };
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

const pct = (x) => `${Math.round(x * 100)}%`;
const fmtFactor = (x) => String(x).replace('.', ',');

// "pico ±15%, fases ±20%, antecedência do ambiente 8–15 s"
function variationText() {
  const L = VARIACAO_LIMITES;
  return `pico ±${pct(L.pico[1] - 1)}, fases ±${pct(L.duracao[1] - 1)}, antecedência do ambiente ${L.antecedencia[0]}–${L.antecedencia[1]} s`;
}

function modeLines({ cenario, umaVez, ciclos, pausa }) {
  const aleatorio = cenario === EVENTOS_ALEATORIOS;
  const unit = `${aleatorio ? 'evento' : 'ciclo'}${ciclos === 1 ? '' : 's'}`;
  if (umaVez && !aleatorio) {
    return [`Modo: uma vez — roteiro nominal de ${nominalScenario(cenario).duracao} s e encerra`];
  }
  const howLong = Number.isFinite(ciclos) ? `${ciclos} ${unit} e encerra` : `loop sem fim (Ctrl+C para parar)`;
  if (aleatorio) {
    const levels = Object.entries(INTENSIDADES).map(([n, f]) => `${n} ×${fmtFactor(f)}`).join(', ');
    const longer = Object.entries(TIPOS_DE_EVENTO)
      .filter(([, nome]) => (SCENARIOS[nome].pausaMinima ?? 0) > 2 * pausa)
      .map(([tipo, nome]) => `${SCENARIOS[nome].pausaMinima} s depois de ${tipo}`);
    return [
      `Modo: ${howLong} · pausa calma sorteada de ${pausa}–${2 * pausa} s entre eventos${longer.length ? ` (${longer.join(', ')}: linha de base de 5 min do gatilho)` : ''}`,
      `Tipos sorteados: ${describeTimeline(cenario)}`,
      `Intensidade das crises: ${levels} · variação: ${variationText()}`,
    ];
  }
  const minPause = SCENARIOS[cenario].pausaMinima ?? 0;
  const pauseText = minPause > pausa
    ? `${minPause} s (mínimo deste cenário: a linha de base de 5 min do gatilho precisa voltar ao ambiente calmo)`
    : `${pausa} s`;
  return [
    `Modo: ${howLong} · pausa calma de ${pauseText} entre ciclos${Number.isFinite(ciclos) ? ' (e no final)' : ''}`,
    `1º ciclo = roteiro nominal; a partir do 2º: ${variationText()}`,
  ];
}

function main() {
  const options = parseCli();
  const { cenario, idade, duracao, umaVez, ciclos, pausa, seed } = options;
  const config = loadConfig();
  const aleatorio = cenario === EVENTOS_ALEATORIOS;

  const base = `puzzleband/${config.childId}`;
  const topicReadings = `${base}/leituras`;
  const topicStatus = `${base}/status`;

  const gabarito = createGabaritoWriter(LOGS_DIR, {
    cenario, seed, pausa_s: pausa, ciclos: Number.isFinite(ciclos) ? ciclos : null, uma_vez: umaVez, idade, crianca: config.childId,
  });

  console.log('Puzzle Band — simulador da pulseira (ESP32)');
  console.log(`Cenário: ${cenario} — ${scenarioDescription(cenario)}`);
  if (!aleatorio) console.log(`Linha do tempo (roteiro nominal): ${describeTimeline(cenario)}`);
  for (const line of modeLines(options)) console.log(line);
  console.log(`Seed: ${seed}${options.seedInformada ? '' : ' (sorteada)'} — para repetir a mesma sequência: --seed ${seed}`);
  console.log(`Gabarito: ${relative(process.cwd(), gabarito.csvPath) || gabarito.csvPath} (e .json), uma linha por ${aleatorio ? 'evento' : 'ciclo'}`);
  console.log(`Criança: ${config.childId} · idade ${idade}${Number.isFinite(duracao) ? ` · para em ${duracao} s (--duracao)` : ''}`);
  console.log(`Broker: ${config.url} (usuário ${config.username})`);
  console.log(`Tópicos: ${topicReadings} (QoS 0) · ${topicStatus} (retain)`);
  console.log('Conectando...');

  const ticks = programTicks({ cenario, umaVez, ciclos, pausa, seed, idade });
  const sensorRandom = seeded(seed); // ruido dos sensores (generateReading usa Math.random)
  let current = null; // evento em andamento: { ciclo, inicio, fisiologia }
  let lastTime = null;
  let ticksDone = 0;

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

  let timer = null;
  let stopping = false;
  let wasConnected = false;

  // Evento interrompido (Ctrl+C, --duracao): grava o que se sabe
  function flushCurrent(reason) {
    if (!current) return;
    gabarito.add(gabaritoEntry(current.ciclo, { ...current, fim: lastTime, observacao: `interrompido (${reason})` }));
    current = null;
  }

  async function shutdown(reason, exitCode = 0) {
    if (stopping) {
      console.log('Saindo sem esperar o broker.');
      process.exit(exitCode || 1);
    }
    stopping = true;
    clearInterval(timer);
    flushCurrent(reason);
    console.log(`\nEncerrando (${reason})...`);
    console.log(`Gabarito: ${gabarito.csvPath}`);
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
    const step = ticks.next();
    if (step.done) {
      shutdown('roteiro concluído');
      return;
    }
    const s = step.value;
    const now = new Date();
    lastTime = now;

    if (s.inicioCiclo) {
      console.log(`\n${cycleBanner(s.ciclo, aleatorio)}`);
      console.log(`    ${cycleDetails(s.ciclo)}`);
    }
    if (s.inicioEvento) current = { ciclo: s.ciclo, inicio: now, fisiologia: null };
    if (current && s.t === current.ciclo.tFisiologia) current.fisiologia = now;

    const reading = withRandom(sensorRandom, () => generateReading({ ...s.alvos, timestamp: now.toISOString() }));
    const sent = client.connected;
    if (sent) client.publish(topicReadings, JSON.stringify(reading), { qos: 0 });
    console.log(formatReading(s.t, reading, s.fase, sent));

    if (s.fimEvento && current) {
      gabarito.add(gabaritoEntry(current.ciclo, { ...current, fim: now }));
      current = null;
    }
    ticksDone += 1;
    if (s.ultimo) {
      const unit = aleatorio ? 'evento' : 'ciclo';
      const n = s.ciclo.numero;
      shutdown(umaVez && !aleatorio ? 'roteiro concluído (--uma-vez)' : `${n} ${unit}${n === 1 ? '' : 's'} concluído${n === 1 ? '' : 's'}`);
    } else if (ticksDone >= duracao) {
      shutdown(`duração de ${duracao} s atingida`);
    }
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
