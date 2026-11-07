#!/usr/bin/env node
// Reset para uma apresentacao (npm run resetar): apaga o historico da
// pulseira, limpa as mensagens retidas no broker e manda o app do cuidador
// (e o site) apagarem os dados locais - sem mexer no celular. Usa as
// credenciais do simulator/.env (usuario "simulador").
//
//   npm run resetar                  mostra o que vai apagar e pede "RESETAR"
//   npm run resetar -- --sim         sem perguntar
//   npm run resetar -- --simular     so mostra: nao apaga nem publica nada
//   npm run resetar -- --tudo        tambem os logs/gabaritos e as preferencias do app
//   npm run resetar -- --id C05      outra crianca (padrao: CHILD_ID do .env)
//   npm run resetar -- --forcar      nao confere se a pulseira esta rodando
//
// Passos:
//   1. confere se a pulseira esta rodando (trava data/pulseira_<id>.lock de
//      um processo vivo, ou status "online" retido) e, se estiver, recusa;
//   2. mostra o plano e pede a confirmacao;
//   3. apaga data/historico_<id>.json (e, com --tudo, a pasta logs/);
//   4. limpa os retidos estado, historico, status e app/status (payload
//      vazio, retain) e publica historico retido com a lista vazia;
//   5. publica a ordem em comando (QoS 1, retain): a pulseira, o app e o
//      site aplicam ao receber (ou ao conectar, se estavam desligados);
//   6. espera ate 30 s a confirmacao do app em comando/resposta.
// Topicos, formatos e ACL: docs/mqtt.md.

import { randomUUID } from 'node:crypto';
import { readdirSync, rmSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import mqtt from 'mqtt';
import { buildHistoryMessage, buildResetCommand, topicsFor } from '../frontend/src/hooks/buildMessages.js';
import {
  parseBandStatus, parseCommandResponse, parseHistory, parseResetCommand,
} from '../frontend/src/hooks/parseMessages.js';
import { AUTH_ERROR_CODES, CHILD_ID_PATTERN, describeError, loadConfig } from './config.js';
import { historyFiles } from './historico.js';
import { checkLock } from './trava.js';

const HERE = dirname(fileURLToPath(import.meta.url));
export const PATHS = { env: join(HERE, '.env'), data: join(HERE, 'data'), logs: join(HERE, 'logs') };

export const CONFIRMATION = 'RESETAR';
export const RESPONSE_TIMEOUT_MS = 30000; // espera pela confirmacao do app
export const RETAINED_TIMEOUT_MS = 3000; // espera pelos retidos (status, historico, comando)
// Retidos apagados com payload vazio (chaves de topicsFor)
export const RETAINED_KEYS = ['estado', 'historico', 'status', 'appStatus'];

const USAGE = `Uso: npm run resetar [-- opções]      (ou: node resetar.js [opções])

  --sim        não pede a confirmação (digitar ${CONFIRMATION})
  --simular    só mostra o que seria apagado; não apaga nem publica nada
  --tudo       também apaga os logs/gabaritos do simulador (logs/) e volta as
               preferências do app ao padrão (nome da criança, aparência e
               alertas sonoros). Sem --tudo, só os dados são apagados.
  --id <id>    criança (padrão: CHILD_ID do simulator/.env)
  --forcar     não confere se a pulseira está rodando

Antes: encerre a pulseira (Ctrl+C no terminal dela). Deixe o app aberto no
celular para ver "App limpo" (fechado, ele aplica quando abrir).`;

// ---------------------------------------------------------------------------
// Argumentos
// ---------------------------------------------------------------------------

export function parseCli(argv) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      options: {
        id: { type: 'string' },
        tudo: { type: 'boolean', default: false },
        sim: { type: 'boolean', default: false },
        simular: { type: 'boolean', default: false },
        forcar: { type: 'boolean', default: false },
        ajuda: { type: 'boolean', short: 'h', default: false },
        help: { type: 'boolean', default: false },
      },
      strict: true,
      allowPositionals: false,
    }));
  } catch (err) {
    throw new Error(`argumento inválido (${err.message})`);
  }
  const id = values.id?.trim() ?? null;
  if (id !== null && !CHILD_ID_PATTERN.test(id)) {
    throw new Error(`--id inválido: "${values.id}". Use só letras, números, _ ou -.`);
  }
  return {
    id,
    tudo: values.tudo,
    sim: values.sim,
    simular: values.simular,
    forcar: values.forcar,
    ajuda: values.ajuda || values.help,
  };
}

// ---------------------------------------------------------------------------
// Arquivos locais
// ---------------------------------------------------------------------------

function safeReaddir(dir) {
  try {
    return readdirSync(dir).sort();
  } catch {
    return [];
  }
}

function sizeOf(path) {
  try {
    return statSync(path).size;
  } catch {
    return 0;
  }
}

// { path, tipo: 'historico' | 'log', bytes } que existem hoje
export function listLocalFiles({ dataDir, logsDir, childId, tudo }) {
  const files = historyFiles(dataDir, childId).map((path) => ({ path, tipo: 'historico' }));
  if (tudo) for (const name of safeReaddir(logsDir)) files.push({ path: join(logsDir, name), tipo: 'log' });
  return files.map((f) => ({ ...f, bytes: sizeOf(f.path) }));
}

// ---------------------------------------------------------------------------
// Broker
// ---------------------------------------------------------------------------

const denied = (granted) => (granted ?? []).filter((g) => g.qos >= 128).map((g) => g.topic);

function waitUntil(done, timeoutMs, poll = 25) {
  return new Promise((resolveWait) => {
    const started = Date.now();
    const check = () => {
      if (done() || Date.now() - started >= timeoutMs) resolveWait();
      else setTimeout(check, poll);
    };
    check();
  });
}

// Le (sem publicar nada) os retidos de status, historico e comando. Os que
// nao existem nao chegam: espera ate `timeoutMs`.
export async function readRetained(client, topics, { timeoutMs = RETAINED_TIMEOUT_MS } = {}) {
  const wanted = [topics.status, topics.historico, topics.comando];
  const found = {};
  const onMessage = (topic, payload) => {
    if (wanted.includes(topic) && !(topic in found)) found[topic] = payload.toString();
  };
  client.on('message', onMessage);
  let negados = [];
  try {
    negados = denied(await client.subscribeAsync(wanted, { qos: 1 }));
    await waitUntil(() => wanted.every((t) => t in found || negados.includes(t)), timeoutMs);
  } finally {
    client.removeListener('message', onMessage);
    await client.unsubscribeAsync(wanted).catch(() => {});
  }
  const text = (topic) => found[topic] ?? '';
  return {
    status: parseBandStatus(text(topics.status)), // 'online' | 'offline' | null
    historico: parseHistory(text(topics.historico)),
    ordem: parseResetCommand(text(topics.comando)),
    negados,
  };
}

// Motivos para achar que a pulseira esta rodando ([] = parada)
export function bandRunning({ trava, status, topics, rel = (p) => p }) {
  const motivos = [];
  if (trava?.estado === 'ativa') motivos.push(`a trava ${rel(trava.path)} é de um processo vivo (PID ${trava.dados.pid})`);
  if (status === 'online') motivos.push(`o status retido em ${topics.status} é "online"`);
  return motivos;
}

// Passos 3 a 6. Nao lanca: um erro do broker (ex.: ACL) fica em `erro`, com
// o que ja foi feito ate ali. `app`: 'limpo' | 'sem_resposta' |
// 'interrompido' (Ctrl+C na espera) | 'sem_permissao' (nao deu para
// assinar comando/resposta) | null (nao chegou a esperar).
export async function executeReset({
  client,
  topics,
  childId,
  files,
  manterPreferencias,
  id = randomUUID(),
  now = () => new Date(),
  responseTimeoutMs = RESPONSE_TIMEOUT_MS,
  signal = null,
  log = () => {},
}) {
  const result = { id, apagados: [], falhas: [], retidosLimpos: [], historicoVazio: false, ordem: null, app: null, erro: null };

  // A confirmacao do app pode chegar em milissegundos: escuta antes de publicar
  let answered = false;
  let onAnswer = () => {};
  const onMessage = (topic, payload) => {
    if (topic !== topics.comandoResposta) return;
    const resposta = parseCommandResponse(payload.toString());
    if (resposta?.id === id && resposta.status === 'aplicado') {
      answered = true;
      onAnswer();
    }
  };
  client.on('message', onMessage);

  const publish = async (topic, payload, what) => {
    try {
      await client.publishAsync(topic, payload, { qos: 1, retain: true });
    } catch (err) {
      const e = new Error(`o broker recusou publicar em ${topic} (${what}): ${describeError(err)}`);
      e.topic = topic;
      throw e;
    }
  };

  try {
    let respostaNegada = false;
    try {
      respostaNegada = denied(await client.subscribeAsync(topics.comandoResposta, { qos: 1 })).length > 0;
    } catch {
      respostaNegada = true;
    }
    if (respostaNegada) log('aviso', `sem permissão para assinar ${topics.comandoResposta}: não dá para saber se o app aplicou`);

    // 3. arquivos locais
    for (const file of files) {
      try {
        rmSync(file.path, { force: true, recursive: true });
        result.apagados.push(file);
      } catch (err) {
        result.falhas.push({ ...file, erro: err.message });
        log('erro', `não foi possível apagar ${file.path}: ${err.message}`);
      }
    }
    log('arquivo', `${result.apagados.length} arquivo(s) apagado(s)`);

    // 4. retidos: payload vazio apaga a mensagem retida no broker
    for (const key of RETAINED_KEYS) {
      await publish(topics[key], '', 'apagar o retido');
      result.retidosLimpos.push(topics[key]);
      log('broker', `retido apagado: ${topics[key]}`);
    }
    // ...e quem conectar depois recebe "sem episódios"
    const vazio = buildHistoryMessage([], { childId, timestamp: now().toISOString() });
    await publish(topics.historico, JSON.stringify(vazio), 'histórico vazio');
    result.historicoVazio = true;
    log('broker', `${topics.historico} (retain) = lista vazia`);

    // 5. ordem para a pulseira, o app e o site
    const ordem = buildResetCommand({ id, timestamp: now().toISOString(), manterPreferencias });
    await publish(topics.comando, JSON.stringify(ordem), 'ordem de reset');
    result.ordem = ordem;
    log('broker', `${topics.comando} (QoS 1, retain) = ordem ${id} (manter_preferencias: ${manterPreferencias})`);

    // 6. confirmacao do app
    if (respostaNegada) {
      result.app = 'sem_permissao';
    } else {
      log('espera', `esperando a confirmação do app em ${topics.comandoResposta} (até ${Math.round(responseTimeoutMs / 1000)} s)...`);
      result.app = await new Promise((resolveApp) => {
        if (answered) {
          resolveApp('limpo');
          return;
        }
        const timer = setTimeout(() => resolveApp('sem_resposta'), responseTimeoutMs);
        onAnswer = () => {
          clearTimeout(timer);
          resolveApp('limpo');
        };
        signal?.addEventListener('abort', () => {
          clearTimeout(timer);
          resolveApp(answered ? 'limpo' : 'interrompido');
        }, { once: true });
      });
    }
  } catch (err) {
    result.erro = err.message;
  } finally {
    client.removeListener('message', onMessage);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Fluxo (testavel com um cliente MQTT falso)
// ---------------------------------------------------------------------------

const relToCwd = (path) => relative(process.cwd(), path) || path;

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1).replace('.', ',')} KB`;
  return `${(n / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
}

function printPlan(out, { childId, topics, paths, files, retidos, manterPreferencias, tudo, rel }) {
  const historico = files.filter((f) => f.tipo === 'historico');
  const logs = files.filter((f) => f.tipo === 'log');
  const episodios = retidos.historico ? `hoje: ${retidos.historico.total} episódio(s)` : 'hoje: nenhum';
  const status = retidos.status ? `hoje: ${retidos.status}` : 'hoje: nenhum';

  out.log('\nO que vai ser apagado:');
  out.log(`  Pulseira, criança ${childId}:`);
  if (historico.length) for (const f of historico) out.log(`    ${rel(f.path)} (${formatBytes(f.bytes)})`);
  else out.log(`    (nenhum arquivo de histórico em ${rel(paths.data)})`);
  if (tudo) {
    const total = logs.reduce((s, f) => s + f.bytes, 0);
    out.log(`  Logs e gabaritos (--tudo): ${logs.length ? `${logs.length} arquivo(s) em ${rel(paths.logs)} (${formatBytes(total)})` : 'nenhum'}`);
  }
  out.log('  Broker (mensagens retidas, publicação retida com payload vazio):');
  out.log(`    ${topics.estado}`);
  out.log(`    ${topics.historico} (${episodios}) → depois volta como lista vazia`);
  out.log(`    ${topics.status} (${status})`);
  out.log(`    ${topics.appStatus}`);
  out.log(`  Ordem em ${topics.comando} (QoS 1, retain), manter_preferencias: ${manterPreferencias}`);
  out.log('    app:   cópia do histórico, episódios notificados, lembretes (e os avisos agendados) e gráficos'
    + `${manterPreferencias ? '' : ', e as preferências (nome da criança, aparência, alertas sonoros)'}`);
  if (manterPreferencias) out.log('           as preferências (nome, aparência, alertas sonoros) ficam; --tudo volta ao padrão');
  out.log('    site:  o que estiver na tela');
  if (retidos.ordem) {
    out.log(`  (a ordem retida hoje é ${retidos.ordem.id}${retidos.ordem.timestamp ? `, de ${retidos.ordem.timestamp}` : ''}: será substituída)`);
  }
}

// Passos 1 a 6 com o cliente ja conectado. Devolve { estado, ... }:
//   'recusado'  pulseira rodando (sem --forcar)
//   'simulado'  --simular: nada apagado nem publicado
//   'cancelado' a confirmacao nao foi "RESETAR"
//   'erro'      o broker recusou uma publicacao (result.erro)
//   'executado' feito (result.app diz se o app confirmou)
export async function runReset({
  client,
  childId,
  options,
  paths = PATHS,
  ask = () => Promise.resolve(false),
  out = console,
  signal = null,
  onWaiting = () => {},
  isAlive,
  id,
  rel = relToCwd,
  retainedTimeoutMs = RETAINED_TIMEOUT_MS,
  responseTimeoutMs = RESPONSE_TIMEOUT_MS,
}) {
  const topics = topicsFor(childId);
  const manterPreferencias = !options.tudo;

  // 1. a pulseira esta rodando?
  const trava = checkLock(paths.data, childId, isAlive ? { isAlive } : {});
  if (trava.estado === 'velha') {
    out.log(`Aviso: a trava ${rel(trava.path)} é de um processo que não está mais rodando (PID ${trava.dados.pid ?? '?'}): ignorada.`);
  }
  const retidos = await readRetained(client, topics, { timeoutMs: retainedTimeoutMs });
  if (retidos.negados.includes(topics.status)) {
    out.log(`Aviso: sem permissão para ler ${topics.status} (ACL): a verificação usa só a trava.`);
  }
  const motivos = bandRunning({ trava, status: retidos.status, topics, rel });
  if (motivos.length && !options.forcar) {
    out.error(`\nA pulseira parece estar rodando: ${motivos.join('; ')}.`);
    out.error('Encerre-a com Ctrl+C no terminal dela e rode o reset de novo.');
    out.error('(Se ela não estiver rodando de verdade, por exemplo depois de uma queda, use --forcar.)');
    return { estado: 'recusado', motivos };
  }
  if (motivos.length) {
    out.log(`Aviso (--forcar): ${motivos.join('; ')}. Seguindo: se estiver rodando, a pulseira também aplica a ordem.`);
  }

  // 2. plano e confirmacao
  const files = listLocalFiles({ dataDir: paths.data, logsDir: paths.logs, childId, tudo: options.tudo });
  printPlan(out, { childId, topics, paths, files, retidos, manterPreferencias, tudo: options.tudo, rel });
  if (options.simular) {
    out.log('\n--simular: nada foi apagado nem publicado.');
    return { estado: 'simulado', files, motivos };
  }
  if (!options.sim && !(await ask())) {
    out.log('Cancelado: nada foi apagado.');
    return { estado: 'cancelado', files, motivos };
  }

  // 3 a 6
  out.log('');
  const result = await executeReset({
    client,
    topics,
    childId,
    files,
    manterPreferencias,
    id,
    signal,
    responseTimeoutMs,
    log: (evento, texto) => {
      const line = `  ${{ arquivo: '✓', broker: '✓', espera: '…', aviso: '!', erro: '✗' }[evento] ?? '·'} ${texto}`;
      if (evento === 'erro') out.error(line);
      else out.log(line);
      if (evento === 'espera') {
        out.log('    (Ctrl+C para não esperar)');
        onWaiting();
      }
    },
  });

  out.log('');
  if (result.erro) {
    out.error(`Erro: ${result.erro}`);
    out.error('Confira a ACL do usuário da pulseira no EMQX (docs/mqtt.md, "ACL sugerida") e rode o reset de novo.');
    return { estado: 'erro', files, motivos, result };
  }
  if (result.app === 'limpo') {
    out.log('App limpo.');
  } else {
    out.log('O app não respondeu: abra o app no celular para ele aplicar o reset (a ordem fica guardada no broker).');
  }
  if (result.falhas.length) out.log(`Atenção: ${result.falhas.length} arquivo(s) não foram apagados (veja acima).`);
  out.log('Pulseira e broker zerados. Agora inicie a pulseira para a apresentação, por exemplo: npm run demo -- --ciclos 1');
  out.log('O site, se estiver aberto, limpa a tela sozinho.');
  return { estado: 'executado', files, motivos, result };
}

// ---------------------------------------------------------------------------
// Terminal
// ---------------------------------------------------------------------------

// true so se digitar exatamente RESETAR. Ctrl+C ou fim da entrada cancelam.
function confirm() {
  return new Promise((resolveConfirm) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      rl.close();
      resolveConfirm(ok);
    };
    rl.on('SIGINT', () => {
      process.stdout.write('\n');
      finish(false);
    });
    rl.on('close', () => finish(false));
    rl.question(`\nDigite ${CONFIRMATION} para confirmar (Enter cancela): `, (answer) => finish(answer.trim() === CONFIRMATION));
  });
}

function connect(config, childId) {
  return new Promise((resolveConnect) => {
    const client = mqtt.connect(config.url, {
      username: config.username,
      password: config.password,
      // MQTT 5: o broker diz o motivo de uma recusa (ACL) no PUBACK/SUBACK
      protocolVersion: 5,
      clientId: `puzzleband-reset-${childId}-${Math.random().toString(16).slice(2, 8)}`,
      clean: true,
      reconnectPeriod: 0,
      connectTimeout: 10000,
    });
    const fail = (message) => {
      console.error(`Erro: ${message}`);
      client.end(true);
      process.exit(1);
    };
    const onError = (err) => {
      if (AUTH_ERROR_CODES.has(err.code)) fail(`o broker recusou o login (${err.message}). Confira MQTT_USER e MQTT_PASS no simulator/.env.`);
      else fail(`não foi possível conectar ao broker: ${describeError(err)}`);
    };
    const onClose = () => fail('a conexão com o broker fechou antes de conectar (rede ou broker fora do ar).');
    client.on('error', onError);
    client.on('close', onClose);
    client.once('connect', () => {
      client.removeListener('error', onError);
      client.removeListener('close', onClose);
      // depois de conectado, um erro de rede aparece na etapa que falhar
      client.on('error', (err) => console.error(`Erro de conexão: ${describeError(err)}`));
      resolveConnect(client);
    });
  });
}

async function main() {
  let options;
  try {
    options = parseCli(process.argv.slice(2));
  } catch (err) {
    console.error(`Erro: ${err.message}\n\n${USAGE}`);
    process.exit(1);
  }
  if (options.ajuda) {
    console.log(USAGE);
    return;
  }

  const config = loadConfig(PATHS.env);
  const childId = options.id ?? config.childId;

  console.log('Puzzle Band — reset para uma apresentação');
  console.log(`Criança: ${childId}${options.id ? ' (--id)' : ' (CHILD_ID do simulator/.env)'}`
    + ` · broker ${config.url} (usuário ${config.username})`);
  if (options.simular) console.log('Modo --simular: só mostra; nada é apagado nem publicado.');

  // Ctrl+C: na espera pela resposta do app, so para de esperar; antes, sai
  const abort = new AbortController();
  let waiting = false;
  process.on('SIGINT', () => {
    if (waiting) {
      abort.abort();
      return;
    }
    console.log('\nInterrompido: nada mais foi feito.');
    process.exit(130);
  });

  console.log('Conectando ao broker...');
  const client = await connect(config, childId);
  const outcome = await runReset({
    client,
    childId,
    options,
    ask: confirm,
    signal: abort.signal,
    onWaiting: () => {
      waiting = true;
    },
  });
  await client.endAsync().catch(() => {});
  process.exit(outcome.estado === 'executado' || outcome.estado === 'simulado' ? 0 : 1);
}

// So roda o main quando chamado direto (os testes importam as funcoes)
const isMain = process.argv[1]
  && (process.platform === 'win32'
    ? resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase()
    : resolve(process.argv[1]) === fileURLToPath(import.meta.url));
if (isMain) {
  main().catch((err) => {
    console.error(`Erro: ${describeError(err)}`);
    process.exit(1);
  });
}

