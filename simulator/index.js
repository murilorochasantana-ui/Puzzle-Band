#!/usr/bin/env node
// Pulseira Puzzle Band (simulacao do ESP32) com PROCESSAMENTO NA BORDA: a
// cada segundo gera uma leitura, roda o modelo, os episodios e o gatilho
// (borda.js, com os mesmos modulos de frontend/src/model) e publica no broker:
//   leituras   leitura bruta (QoS 0)            -> painel do site (graficos)
//   estado     nivel, probabilidade... (retain) -> app do cuidador e painel
//   alertas    mudanca de nivel (QoS 1)         -> app e painel
//   historico  lista de episodios (retain)      -> app e painel
//   status     online/offline (retain + Last Will)
// e aplica no historico o ack ("Estou ciente") e a avaliacao que chegam do
// app ou do painel. O app funciona so com a pulseira ligada: o site e opcional.
//
// As leituras vem do mesmo gerador de sempre (frontend/src/model/simulate.js),
// seguindo um cenario (scenarios.js) ou, no modo controle, os valores-alvo
// enviados pelo painel do site (controle.js).
//
// Por padrao o cenario roda em LOOP (ciclo -> pausa calma -> ciclo ...) ate
// o Ctrl+C; o 1o ciclo e o roteiro nominal e os seguintes variam um pouco.
//
//   node index.js --cenario crise_ruido [--ciclos 3] [--pausa 120] [--seed 42]
//   node index.js --cenario crise_ruido --uma-vez          # roteiro nominal e encerra
//   node index.js --cenario eventos_aleatorios --ciclos 20 --seed 42
//   node index.js --cenario controle                       # controle remoto pelo painel
//
// Cada evento/ciclo vira uma linha do gabarito em logs/eventos_<data-hora>.csv
// (e .json). O historico de episodios fica em data/historico_<id>.json.
// Enquanto roda, a pulseira mantem a trava data/pulseira_<id>.lock (o reset,
// npm run resetar, recusa apagar com ela ativa) e aplica a ordem de reset
// retida em comando (o id aplicado fica em data/reset_<id>.json).
// Configuracao em simulator/.env (ver .env.example).

import { randomInt } from 'node:crypto';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import mqtt from 'mqtt';
import { CALM_CONTROL, generateReading } from '../frontend/src/model/simulate.js';
import { describeModel, modelInfoFrom } from '../frontend/src/model/modelInfo.js';
import forest from '../frontend/src/model/forest.json' with { type: 'json' };
import {
  EVENTOS_ALEATORIOS, INTENSIDADES, PAUSA_MIN_S, PAUSA_PADRAO_S, SCENARIOS, SCENARIO_NAMES, TIPOS_DE_EVENTO, VARIACAO_LIMITES,
  cycleBanner, cycleDetails, describeTimeline, nominalScenario, programTicks, scenarioDescription, seeded, withRandom,
} from './scenarios.js';
import { createGabaritoWriter, gabaritoEntry } from './gabarito.js';
import { createEdgeLink, createEdgeProcessor } from './borda.js';
import { openHistoryFile, readLastReset, saveLastReset } from './historico.js';
import { AUTH_ERROR_CODES, describeError, loadConfig } from './config.js';
import { createLock } from './trava.js';
import { CONTROLE, CONTROLE_DESCRICAO, RAMPA_CONTROLE_S, controlTicks, createControl } from './controle.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ENV_PATH = join(HERE, '.env');
const LOGS_DIR = join(HERE, 'logs');
const DATA_DIR = join(HERE, 'data');
const IDADE_MIN = 5;
const IDADE_MAX = 12; // mesma faixa do controle de idade do painel
const SEED_MAX = 4294967295;
const CENARIOS_VALIDOS = [...SCENARIO_NAMES, CONTROLE];

const USAGE = `Uso: node index.js --cenario <nome> [opções]
     npm start -- --cenario <nome> ...      (ou um atalho: npm run crise-ruido -- --ciclos 3, npm run controle)

  --cenario            um dos cenários abaixo (padrão: calmo)
  --idade              idade da criança, ${IDADE_MIN} a ${IDADE_MAX} anos (padrão: 8; no controle, até o painel mandar outra)
  --uma-vez            só o roteiro nominal, uma vez, e encerra (comportamento antigo)
  --ciclos             roda N ciclos (no eventos_aleatorios, N eventos) e encerra (padrão: loop até Ctrl+C)
  --pausa              segundos de pausa calma entre ciclos (padrão: ${PAUSA_PADRAO_S}; mínimo ${PAUSA_MIN_S});
                       no eventos_aleatorios a pausa é sorteada entre S e 2×S (padrão: ${PAUSA_PADRAO_S}–${2 * PAUSA_PADRAO_S} s)
  --seed               semente do sorteio e do ruído dos sensores (mesma seed = mesma sequência)
  --duracao            para depois de N segundos, em qualquer modo
  --limpar-historico   começa com o histórico de episódios vazio (esvazia data/historico_<id>.json
                       e publica a lista vazia em historico, também para o app)

  No modo controle (--cenario controle) não há ciclos: a pulseira segue os valores
  do painel do site até o Ctrl+C (ou --duracao). --uma-vez, --ciclos e --pausa não se aplicam.`;

const describeScenario = (name) => (name === CONTROLE ? CONTROLE_DESCRICAO : scenarioDescription(name));

function scenarioList() {
  const width = Math.max(...CENARIOS_VALIDOS.map((n) => n.length));
  return CENARIOS_VALIDOS.map((n) => `  ${n.padEnd(width)}  ${describeScenario(n)}`).join('\n');
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
        'limpar-historico': { type: 'boolean', default: false },
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
  if (!CENARIOS_VALIDOS.includes(cenario)) fail(`cenário inválido: "${cenario}".`, { showScenarios: true });
  const controle = cenario === CONTROLE;

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

  if (controle && (values['uma-vez'] || values.ciclos !== undefined)) {
    fail('--uma-vez e --ciclos não se aplicam ao modo controle (ele segue o painel até o Ctrl+C; use --duracao para limitar).');
  }
  if (controle && values.pausa !== undefined) console.warn('Aviso: --pausa não se aplica ao modo controle.');

  let umaVez = values['uma-vez'];
  if (umaVez && values.ciclos !== undefined) fail('use --uma-vez OU --ciclos, não os dois.');
  let ciclos = values.ciclos === undefined ? Infinity : positiveInt('ciclos', values.ciclos, 'um número inteiro maior que zero');
  if (umaVez && cenario === EVENTOS_ALEATORIOS) {
    // nao ha roteiro nominal: --uma-vez = um evento sorteado (+ pausa final)
    umaVez = false;
    ciclos = 1;
  }

  let pausa = PAUSA_PADRAO_S;
  if (values.pausa !== undefined && !controle) {
    pausa = positiveInt('pausa', values.pausa, 'um número inteiro de segundos');
    if (umaVez && cenario !== EVENTOS_ALEATORIOS) console.warn('Aviso: --pausa não se aplica com --uma-vez (não há segundo ciclo).');
    if (pausa < PAUSA_MIN_S) {
      console.warn(`Aviso: --pausa ${pausa} é menor que o mínimo de ${PAUSA_MIN_S} s (30 s para o episódio anterior fechar`
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
  return {
    cenario,
    controle,
    idade,
    duracao,
    umaVez,
    ciclos,
    pausa,
    seed,
    seedInformada: values.seed !== undefined,
    limparHistorico: values['limpar-historico'],
  };
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

const TIER_SHORT = { baixo_risco: 'normal ', atencao: 'ATENÇÃO', alto_risco: 'CRISE  ' };

// Nivel do modelo calculado na pulseira: "normal   12%" | "ATENÇÃO  64%" | "coletando" (< 31 leituras)
function formatTier(tier, probability) {
  if (!Number.isFinite(probability)) return 'coletando   ';
  return `${TIER_SHORT[tier] ?? tier} ${String(Math.round(probability * 100)).padStart(3)}%`;
}

// [tempo] bpm, eda, hrv, gyro, reg, luz, ruido | nivel | fase
function formatReading(t, r, step, fase) {
  const cols = [
    `bpm ${String(r.bpm).padStart(3)}`,
    `eda ${r.eda_uS.toFixed(2).padStart(5)}`,
    `hrv ${r.hrv_ms.toFixed(1).padStart(5)}`,
    `gyro ${r.gyro_mag_dps.toFixed(1).padStart(5)}`,
    `reg ${r.regularidade.toFixed(2)}`,
    `luz ${String(r.luz_lux).padStart(4)}`,
    `ruido ${r.ruido_db.toFixed(1).padStart(5)}`,
  ];
  return `[${formatElapsed(t)}] ${cols.join('  ')} | ${formatTier(step.tier, step.probability)} | ${fase}`
    + `${step.sent ? '' : '  (não enviada: sem conexão)'}`;
}

// ---------------------------------------------------------------------------
// Simulacao
// ---------------------------------------------------------------------------

const pct = (x) => `${Math.round(x * 100)}%`;
const fmtFactor = (x) => String(x).replace('.', ',');

// "pico ±15%, fases ±20%, antecedência do ambiente 8–15 s"
function variationText() {
  const L = VARIACAO_LIMITES;
  return `pico ±${pct(L.pico[1] - 1)}, fases ±${pct(L.duracao[1] - 1)}, antecedência do ambiente ${L.antecedencia[0]}–${L.antecedencia[1]} s`;
}

function modeLines({ cenario, controle, umaVez, ciclos, pausa }) {
  if (controle) {
    return [
      'Modo: controle remoto até o Ctrl+C — abra o painel do site ("Controle da pulseira") para mudar os valores',
      `Transição: rampa linear de ${RAMPA_CONTROLE_S} s até cada novo valor-alvo · valores fora da faixa são ignorados`,
    ];
  }
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

const rel = (path) => relative(process.cwd(), path) || path;

function main() {
  const options = parseCli();
  const { cenario, controle, idade, duracao, umaVez, ciclos, pausa, seed } = options;
  const config = loadConfig(ENV_PATH);
  const aleatorio = cenario === EVENTOS_ALEATORIOS;

  // Historico de episodios: arquivo local; sem arquivo, recupera da mensagem retida
  const historyFile = openHistoryFile(DATA_DIR, config.childId, {
    onError: (err) => console.error(`Erro ao gravar ${rel(historyFile.storage.path)}: ${err.message} (o histórico segue em memória)`),
  });
  const processor = createEdgeProcessor({
    childId: config.childId,
    source: controle ? 'manual' : 'pulseira',
    storage: historyFile.storage,
  });
  let historyLine;
  if (options.limparHistorico) {
    processor.clear();
    historyFile.storage.flush();
    historyLine = `${rel(historyFile.storage.path)} — começando VAZIO (--limpar-historico; a lista vazia vai também para o app)`;
  } else if (historyFile.status === 'ok') {
    historyLine = `${rel(historyFile.storage.path)} (${historyFile.episodes} episódio(s) recuperado(s) do arquivo)`;
  } else {
    const why = historyFile.status === 'corrompido'
      ? `arquivo corrompido, guardado como ${rel(historyFile.backup)}`
      : 'arquivo ainda não existe';
    historyLine = `${rel(historyFile.storage.path)} (${why}: recupera da mensagem retida em historico, se houver)`;
  }
  const recoverFromRetained = !options.limparHistorico && historyFile.status !== 'ok';

  // Trava: o reset (npm run resetar) recusa apagar com a pulseira rodando.
  // Sai em qualquer encerramento (process.exit inclusive).
  const trava = createLock(DATA_DIR, config.childId, { cenario });
  process.on('exit', () => trava.remove());

  // Ultima ordem de reset aplicada (a ordem fica retida em comando)
  const lastReset = readLastReset(DATA_DIR, config.childId);

  const control = controle ? createControl({ inicial: { ...CALM_CONTROL, idade } }) : null;

  const base = `puzzleband/${config.childId}`;
  const topicStatus = `${base}/status`;

  const gabarito = controle ? null : createGabaritoWriter(LOGS_DIR, {
    cenario, seed, pausa_s: pausa, ciclos: Number.isFinite(ciclos) ? ciclos : null, uma_vez: umaVez, idade, crianca: config.childId,
  });

  console.log('Puzzle Band — pulseira simulada (ESP32) com processamento na borda');
  console.log(`Cenário: ${cenario} — ${describeScenario(cenario)}`);
  if (!aleatorio && !controle) console.log(`Linha do tempo (roteiro nominal): ${describeTimeline(cenario)}`);
  for (const line of modeLines(options)) console.log(line);
  console.log(`Seed: ${seed}${options.seedInformada ? '' : ' (sorteada)'} — para repetir a mesma sequência: --seed ${seed}`);
  if (gabarito) console.log(`Gabarito: ${rel(gabarito.csvPath)} (e .json), uma linha por ${aleatorio ? 'evento' : 'ciclo'}`);
  console.log(`Criança: ${config.childId} · idade ${idade}${Number.isFinite(duracao) ? ` · para em ${duracao} s (--duracao)` : ''}`);
  console.log(`Processamento: ${describeModel(modelInfoFrom(forest.meta, forest.trees.length))} + episódios + gatilho,`
    + ' aqui na pulseira (o site é opcional)');
  console.log(`Histórico: ${historyLine}`);
  if (trava.anterior.estado === 'ativa') {
    console.warn(`Aviso: outra pulseira com a criança ${config.childId} parece estar rodando (PID ${trava.anterior.dados.pid}).`
      + ' Duas pulseiras com o mesmo CHILD_ID publicam por cima uma da outra.');
  }
  console.log(`Broker: ${config.url} (usuário ${config.username})`);
  console.log(`Publica: ${base}/{leituras, estado (retain), alertas (QoS 1), historico (retain), status (retain)}`);
  console.log(`Assina:  ${base}/{ack, avaliacao, comando${controle ? ', controle' : ''}}`
    + `${recoverFromRetained ? ` e, só na partida, ${base}/historico (recuperação)` : ''}`);
  console.log(`Reset:   ordem retida em ${base}/comando com id novo = começa com o histórico vazio`
    + ` (última aplicada: ${lastReset ? `${lastReset.id}, em ${lastReset.aplicado_em}` : 'nenhuma'})`);
  console.log('Conectando...');

  const ticks = controle ? controlTicks(control) : programTicks({ cenario, umaVez, ciclos, pausa, seed, idade });
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

  // (a ligacao com a borda e criada depois do handler de 'connect' abaixo,
  // para o terminal mostrar "Conectado" antes do que ela publica)
  let link = null;

  let timer = null;
  let stopping = false;
  let wasConnected = false;

  // Evento interrompido (Ctrl+C, --duracao): grava o que se sabe
  function flushCurrent(reason) {
    if (!current || !gabarito) return;
    gabarito.add(gabaritoEntry(current.ciclo, { ...current, fim: lastTime, observacao: `interrompido (${reason})` }));
    current = null;
  }

  async function shutdown(reason, exitCode = 0) {
    if (stopping) {
      console.log('Saindo sem esperar o broker.');
      historyFile.storage.flush();
      process.exit(exitCode || 1);
    }
    stopping = true;
    clearInterval(timer);
    flushCurrent(reason);
    console.log(`\nEncerrando (${reason})...`);
    if (gabarito) console.log(`Gabarito: ${gabarito.csvPath}`);
    const forceExit = setTimeout(() => {
      console.error('O broker não respondeu a tempo; saindo mesmo assim (o Last Will publica "offline").');
      historyFile.storage.flush();
      process.exit(exitCode || 1);
    }, 5000);
    try {
      await link.close(); // fecha o episodio aberto e publica o historico final
      historyFile.storage.flush();
      console.log(`Histórico gravado em ${historyFile.storage.path}`);
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
      historyFile.storage.flush();
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
    // publica a leitura, roda o modelo/episodios/gatilho e publica estado, alertas e historico
    const result = link.step(reading);
    console.log(formatReading(s.t, reading, result, s.fase));

    if (s.fimEvento && current && gabarito) {
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
    if (link.recovering()) console.log(`Recuperando o histórico da mensagem retida em ${base}/historico...`);
    if (link.checkingReset()) console.log(`Conferindo se há uma ordem de reset retida em ${base}/comando...`);
  });

  // Processamento na borda: publica estado/alertas/historico e aplica ack,
  // avaliacao, controle e a ordem de reset (assina e publica o historico ao
  // conectar)
  link = createEdgeLink({
    client,
    processor,
    control,
    recoverFromRetained,
    reset: {
      lastAppliedId: lastReset?.id ?? null,
      onApply(order) {
        historyFile.storage.flush(); // o arquivo vazio vai para o disco na hora
        try {
          saveLastReset(DATA_DIR, config.childId, order);
        } catch (err) {
          console.error(`Erro ao gravar a ordem de reset aplicada: ${err.message} (na próxima partida ela seria aplicada de novo)`);
        }
      },
    },
    log: (evento, texto) => {
      const marca = {
        alerta: '▲', aviso: '!', recuperacao: '↺', controle: '⇢', ack: '✓', avaliacao: '✓', reset: '⌫',
      }[evento] ?? '·';
      console.log(`  ${marca} ${texto}`);
    },
  });

  client.on('connect', () => {
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
    if (!stopping && wasConnected) {
      console.log('Conexão perdida; a pulseira segue processando (episódios vão para o arquivo) e republica o histórico ao reconectar.');
    }
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
