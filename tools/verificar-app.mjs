#!/usr/bin/env node
// Verifica pelo terminal se a pulseira e o app do cuidador conversam pelo
// broker MQTT (sem navegador e sem emulador). Conecta COMO O APP - host,
// usuario, senha e CHILD_ID do mobile/env.json - e:
//   a) assina estado, alertas, historico e status e mostra o que chega;
//   b) publica um ack ("Estou ciente") e uma avaliacao ("Confirmar gatilho")
//      de teste, no mesmo formato do app;
//   c) confere cada mensagem com o que o codigo Dart espera
//      (mobile/lib/models/models.dart) e imprime OK/FALHA por campo;
//   d) imprime o relatorio "pulseira -> app" e "app -> pulseira".
//
// Uso (de simulator/):
//   npm run verificar-app                    escuta 60 s (ou ate ter os 3 tipos)
//   npm run verificar-app -- --tempo 300     escuta ate 5 min (bom para provocar uma crise)
//   npm run verificar-app -- --sem-publicar  so escuta, nao publica ack/avaliacao
// Ctrl+C durante a escuta: encerra a escuta e segue para a publicacao e o relatorio.
//
// A pulseira precisa estar ligada (npm start ou npm run controle, em
// simulator/): e ela que processa e publica (processamento na borda). O site
// e opcional e pode estar fechado. A senha nunca e impressa. Nao publica em app/status, para nao mexer no indicador
// "App do cuidador" de um app de verdade conectado ao mesmo tempo.
// Conecta com MQTT 5 (o app usa 3.1.1) so para o broker dizer o motivo de uma
// recusa (ACL) e se havia alguem assinando o topico; a ACL e por usuario e
// topico, igual nas duas versoes.

import { readFileSync, realpathSync } from 'node:fs';
import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// Argumentos
// ---------------------------------------------------------------------------

function lerArgumentos(argv) {
  const opcoes = { tempo: 60, publicar: true };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--tempo') {
      const valor = Number(argv[i + 1]);
      if (!Number.isFinite(valor) || valor < 5 || valor > 3600) sair('--tempo espera segundos entre 5 e 3600.');
      opcoes.tempo = valor;
      i += 1;
    } else if (arg === '--sem-publicar') {
      opcoes.publicar = false;
    } else if (arg === '--help' || arg === '-h') {
      console.log('Uso: npm run verificar-app [-- --tempo <segundos>] [-- --sem-publicar]');
      process.exit(0);
    } else {
      sair(`Argumento desconhecido: ${arg} (use --help).`);
    }
  }
  return opcoes;
}

function sair(mensagem) {
  console.error(`ERRO: ${mensagem}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Configuracao: mobile/env.json, com as mesmas regras de AppConfig
// (mobile/lib/config/app_config.dart). A senha nao e impressa.
// ---------------------------------------------------------------------------

function lerJson(url, nome) {
  let texto;
  try {
    texto = readFileSync(url, 'utf8');
  } catch {
    return { erro: `${nome} não encontrado` };
  }
  try {
    return { dados: JSON.parse(texto.replace(/^﻿/, '')) };
  } catch (e) {
    return { erro: `${nome} não é um JSON válido (${e.message})` };
  }
}

function lerConfig() {
  const env = lerJson(new URL('../mobile/env.json', import.meta.url), 'mobile/env.json');
  if (env.erro) sair(`${env.erro}. Copie mobile/env.example.json para mobile/env.json e preencha MQTT_PASS.`);
  const exemplo = lerJson(new URL('../mobile/env.example.json', import.meta.url), 'mobile/env.example.json');

  const dados = env.dados;
  // --dart-define-from-file transforma numeros em texto; aqui tambem
  const texto = (v) => (v === undefined || v === null ? '' : String(v));
  const config = {
    host: texto(dados.MQTT_HOST).trim(),
    port: Number.parseInt(texto(dados.MQTT_PORT ?? '8883').trim(), 10),
    user: texto(dados.MQTT_USER).trim(),
    pass: texto(dados.MQTT_PASS),
    childId: texto(dados.CHILD_ID ?? 'C01').trim(),
  };
  const problemas = [
    !config.host && 'MQTT_HOST',
    !(config.port > 0 && config.port <= 65535) && 'MQTT_PORT',
    !config.user && 'MQTT_USER',
    !config.pass && 'MQTT_PASS',
    !/^[A-Za-z0-9_-]+$/.test(config.childId) && 'CHILD_ID',
  ].filter(Boolean);

  const avisos = [];
  if (exemplo.dados) {
    const esperadas = Object.keys(exemplo.dados);
    const faltando = esperadas.filter((k) => !(k in dados));
    const sobrando = Object.keys(dados).filter((k) => !esperadas.includes(k));
    if (faltando.length) avisos.push(`faltam no env.json (existem no env.example.json): ${faltando.join(', ')}`);
    if (sobrando.length) avisos.push(`o app não lê estas chaves do env.json: ${sobrando.join(', ')}`);
  }
  return { config, problemas, avisos };
}

// O pacote mqtt vem do simulator/ (ou do frontend/, se o simulator ainda nao
// teve npm install): tools/ nao tem package.json proprio.
function carregarMqtt() {
  for (const pasta of ['simulator', 'frontend']) {
    try {
      const requireDaPasta = createRequire(new URL(`../${pasta}/package.json`, import.meta.url));
      const modulo = requireDaPasta('mqtt');
      return { connect: modulo.connect ?? modulo.default?.connect, pasta };
    } catch {
      // tenta a proxima pasta
    }
  }
  return sair('Pacote "mqtt" não encontrado. Rode "npm install" dentro de simulator/.');
}

// ---------------------------------------------------------------------------
// Formatos esperados pelo app (espelho de mobile/lib/models/models.dart).
// Cada campo: [nome, tipo, { obrigatorio, uso, filhos }].
// obrigatorio = sem ele o app DESCARTA a mensagem (ou o episodio);
// os demais, com tipo errado, viram "vazio" na tela.
// ---------------------------------------------------------------------------

const NIVEIS = ['baixo_risco', 'atencao', 'alto_risco'];
const AVALIACOES = ['pendente', 'confirmado', 'descartado'];

const ehObjeto = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const ehNumero = (v) => typeof v === 'number' && Number.isFinite(v);
const ehIso = (v) => typeof v === 'string' && !Number.isNaN(Date.parse(v));

const T = {
  nivel: { desc: 'baixo_risco | atencao | alto_risco', ok: (v) => NIVEIS.includes(v) },
  avaliacao: { desc: 'pendente | confirmado | descartado', ok: (v) => AVALIACOES.includes(v) },
  iso: { desc: 'data ISO 8601', ok: ehIso },
  num: { desc: 'número', ok: ehNumero },
  texto: { desc: 'texto', ok: (v) => typeof v === 'string' },
  id: { desc: 'texto não vazio', ok: (v) => typeof v === 'string' && v.trim() !== '' },
  objeto: { desc: 'objeto', ok: ehObjeto },
  lista: { desc: 'lista', ok: Array.isArray },
  pulseira: { desc: '"pulseira"', ok: (v) => v === 'pulseira' },
};
const ouNull = (tipo) => ({ desc: `${tipo.desc} ou null`, ok: (v) => v === null || tipo.ok(v) });

const GATILHO = [
  ['tipo', ouNull(T.texto)],
  ['texto', T.texto, { uso: 'texto da notificação e do card de alerta' }],
];

const ESTADO = [
  ['nivel', T.nivel, { obrigatorio: true }],
  ['timestamp', T.iso, { uso: 'o app só mostra "ao vivo" um estado retido com até 6 s' }],
  ['fonte', T.texto],
  ['probabilidade', ouNull(T.num)],
  ['leituras', ouNull(T.objeto), {
    filhos: [
      ['timestamp', T.texto, { uso: 'evita repetir o mesmo ponto no gráfico de BPM' }],
      ['bpm', ouNull(T.num)],
      ['eda_uS', ouNull(T.num)],
      ['hrv_ms', ouNull(T.num)],
      ['gyro_mag_dps', ouNull(T.num)],
      ['regularidade', ouNull(T.num)],
      ['luz_lux', ouNull(T.num)],
      ['ruido_db', ouNull(T.num)],
    ],
  }],
  ['media_bpm_5min', ouNull(T.num)],
  ['gatilho', ouNull(T.objeto), { filhos: GATILHO }],
  ['episodio', ouNull(T.objeto), {
    filhos: [
      ['id', T.id, { obrigatorio: true, uso: 'sem ele o app ignora o episódio em andamento' }],
      ['inicio', T.iso],
      ['nivel_maximo', T.nivel],
      ['visto_pelo_cuidador_em', ouNull(T.iso)],
    ],
  }],
  ['origem', T.pulseira, { uso: 'quem publicou: a pulseira (processamento na borda)' }],
];

const ALERTA = [
  ['nivel', T.nivel, { obrigatorio: true }],
  ['nivel_anterior', ouNull(T.nivel)],
  ['episodio_id', T.id, { uso: 'o app notifica no máximo uma vez por episódio' }],
  ['probabilidade', ouNull(T.num)],
  ['gatilho', ouNull(T.objeto), { filhos: GATILHO }],
  ['timestamp', T.iso, { uso: 'alerta com mais de 10 min não notifica' }],
  ['fonte', T.texto],
  ['origem', T.pulseira],
];

const EPISODIO = [
  ['id', T.id, { obrigatorio: true }],
  ['inicio', T.iso, { obrigatorio: true }],
  ['nivel_maximo', T.nivel, { obrigatorio: true }],
  ['crianca', ouNull(T.texto)],
  ['fonte', ouNull(T.texto)],
  ['fim', ouNull(T.iso)],
  ['duracao_s', ouNull(T.num)],
  ['encerramento', ouNull(T.texto), { uso: 'null = em andamento' }],
  ['probabilidade_maxima', ouNull(T.num)],
  ['gatilho', ouNull(T.objeto), { filhos: GATILHO }],
  ['avaliacao_cuidador', T.avaliacao],
  ['observacao', T.texto],
  ['avaliacao_origem', ouNull(T.texto)],
  ['avaliacao_em', ouNull(T.iso)],
  ['visto_pelo_cuidador_em', ouNull(T.iso)],
];

const HISTORICO = [
  ['episodios', T.lista, { obrigatorio: true }],
  ['timestamp', T.iso],
  ['origem', T.pulseira],
];

const resumoValor = (v) => {
  const s = JSON.stringify(v);
  if (s === undefined) return 'undefined';
  return s.length > 48 ? `${s.slice(0, 45)}...` : s;
};

const tipoJs = (v) => (v === null ? 'null' : Array.isArray(v) ? 'lista' : typeof v === 'string' ? 'texto' : typeof v);

// Devolve [{ campo, ok, obrigatorio, detalhe }] para os campos do esquema.
function validar(esquema, obj, prefixo = '') {
  const linhas = [];
  for (const [nome, tipo, extra = {}] of esquema) {
    const campo = `${prefixo}${nome}`;
    if (!(nome in obj)) {
      linhas.push({ campo, ok: false, obrigatorio: extra.obrigatorio, detalhe: `ausente (o app lê "${nome}")` });
      continue;
    }
    const valor = obj[nome];
    if (!tipo.ok(valor)) {
      linhas.push({
        campo,
        ok: false,
        obrigatorio: extra.obrigatorio,
        detalhe: `esperado ${tipo.desc}, veio ${resumoValor(valor)} (${tipoJs(valor)})`,
      });
      continue;
    }
    linhas.push({ campo, ok: true, detalhe: resumoValor(valor) });
    if (extra.filhos && ehObjeto(valor)) linhas.push(...validar(extra.filhos, valor, `${campo}.`));
  }
  return linhas;
}

const camposExtras = (esquema, obj) => {
  const conhecidos = new Set(esquema.map(([nome]) => nome));
  return Object.keys(obj).filter((k) => !conhecidos.has(k));
};

function imprimirValidacao(linhas, { soFalhas = false, limite = Infinity } = {}) {
  let impressas = 0;
  for (const l of linhas) {
    if (soFalhas && l.ok) continue;
    if (impressas >= limite) {
      console.log(`    ... (${linhas.filter((x) => !x.ok).length - impressas} falhas a mais)`);
      return;
    }
    const marca = l.ok ? 'OK   ' : 'FALHA';
    const obrig = !l.ok && l.obrigatorio ? '  ← obrigatório: o app descarta a mensagem' : '';
    console.log(`    ${marca}  ${l.campo.padEnd(34)} ${l.detalhe}${obrig}`);
    impressas += 1;
  }
}

// ---------------------------------------------------------------------------
// Estado da verificacao
// ---------------------------------------------------------------------------

const hora = (d = new Date()) => d.toLocaleTimeString('pt-BR', { hour12: false });
const horaIso = (iso) => (ehIso(iso) ? hora(new Date(iso)) : '?');
const ESTADO_AO_VIVO_MS = 6000; // mesma regra do app (MqttService._estadoMaxAtraso)

const rel = {
  estado: { total: 0, aoVivo: 0, retidas: 0, falhas: 0, chegadas: [], ultimo: null, ultimoNivel: null, ultimoEpisodio: null },
  alertas: { total: 0, falhas: 0, lista: [] },
  historico: { total: 0, retidas: 0, falhas: 0, ultimo: null, ultimoEm: 0, episodiosInvalidos: 0 },
  status: { total: 0, valor: null, retida: false, invalidas: 0 },
  assinaturas: {},
  publicacoes: [],
  respostaPulseira: null,
};

function linhaEstado(m, retida) {
  const l = m.leituras ?? {};
  const prob = ehNumero(m.probabilidade) ? m.probabilidade.toFixed(3) : '—';
  const bpm = ehNumero(l.bpm) ? l.bpm : '—';
  const media = ehNumero(m.media_bpm_5min) ? m.media_bpm_5min : '—';
  const ep = m.episodio?.id ? `${m.episodio.id} (máx ${m.episodio.nivel_maximo})` : '—';
  const gat = m.gatilho?.texto ? ` gatilho="${m.gatilho.texto}"` : '';
  const quando = retida ? ` [retida, publicada às ${horaIso(m.timestamp)}]` : '';
  return `nivel=${m.nivel} prob=${prob} bpm=${bpm} média5min=${media} fonte=${m.fonte} episódio=${ep}${gat}${quando}`;
}

function tratarEstado(m, retida) {
  const r = rel.estado;
  r.total += 1;
  const agora = Date.now();
  let aoVivo = !retida;
  if (retida) {
    r.retidas += 1;
    aoVivo = ehIso(m.timestamp) && agora - Date.parse(m.timestamp) <= ESTADO_AO_VIVO_MS;
  }
  if (aoVivo) {
    r.aoVivo += 1;
    if (!retida) r.chegadas.push(agora);
  }
  const linhas = validar(ESTADO, m);
  const falhou = linhas.some((l) => !l.ok);
  if (falhou) r.falhas += 1;

  const mudouNivel = m.nivel !== r.ultimoNivel;
  const mudouEpisodio = (m.episodio?.id ?? null) !== r.ultimoEpisodio;
  r.ultimoNivel = m.nivel;
  r.ultimoEpisodio = m.episodio?.id ?? null;
  r.ultimo = m;

  const primeira = r.total === 1;
  if (primeira || r.total <= 5 || mudouNivel || mudouEpisodio || falhou || r.total % 10 === 0) {
    const sufixo = r.total > 5 && !primeira ? ` (${r.total}ª mensagem)` : '';
    const situacao = aoVivo ? 'ao vivo' : 'VELHA (a pulseira não está publicando agora)';
    console.log(`[${hora()}] estado     ${situacao}${sufixo} | ${linhaEstado(m, retida)}`);
  }
  if (primeira) {
    imprimirValidacao(linhas);
    const extras = camposExtras(ESTADO, m);
    if (extras.length) console.log(`    info   campos que o app não usa: ${extras.join(', ')}`);
  } else if (falhou) {
    imprimirValidacao(linhas, { soFalhas: true, limite: 6 });
  }
}

function tratarAlerta(m, retida) {
  const r = rel.alertas;
  r.total += 1;
  r.lista.push(m);
  const linhas = validar(ALERTA, m);
  const falhou = linhas.some((l) => !l.ok);
  if (falhou) r.falhas += 1;
  const gat = m.gatilho?.texto ? `"${m.gatilho.texto}"` : '(sem texto de gatilho)';
  console.log(
    `[${hora()}] ALERTA     ${m.nivel_anterior ?? '?'} → ${m.nivel} | episódio=${m.episodio_id ?? '—'} ` +
    `prob=${ehNumero(m.probabilidade) ? m.probabilidade : '—'} | gatilho: ${gat}${retida ? ' [retida?!]' : ''}`,
  );
  if (r.total === 1) imprimirValidacao(linhas);
  else if (falhou) imprimirValidacao(linhas, { soFalhas: true, limite: 6 });
  if (retida) console.log('    FALHA  alertas não deveria ser retido (um alerta velho notificaria quem conecta depois)');
  console.log(`    → ${previsaoDeNotificacao(m)}`);
}

// Mesma regra de MqttService._notificarSePreciso: no maximo uma notificacao
// por episodio; se o nivel SOBE, a mesma notificacao e atualizada sem som.
const notificados = new Map(); // episodio_id -> nivel ja notificado
const ALERTA_MAX_ATRASO_MS = 10 * 60 * 1000;

function previsaoDeNotificacao(m) {
  const rank = NIVEIS.indexOf(m.nivel);
  if (rank < 0) return 'o app descarta (nível inválido)';
  if (rank === 0) return 'o app não notifica (nível calmo)';
  if (ehIso(m.timestamp) && Date.now() - Date.parse(m.timestamp) > ALERTA_MAX_ATRASO_MS) {
    return 'o app não notifica (alerta com mais de 10 min)';
  }
  const chave = m.episodio_id ?? `sem_id_${m.timestamp}`;
  const anterior = notificados.get(chave);
  if (anterior !== undefined && rank <= anterior) return 'o app NÃO notifica de novo (mesmo episódio, nível não subiu)';
  notificados.set(chave, rank);
  const titulo = rank === 2 ? 'Possível crise' : 'Atenção';
  const texto = m.gatilho?.texto || 'texto padrão (sem gatilho)';
  return anterior === undefined
    ? `o app notifica com som: "${titulo}" — ${texto}`
    : `o app atualiza a mesma notificação, sem tocar de novo: "${titulo}" — ${texto}`;
}

function tratarHistorico(m, retida) {
  const r = rel.historico;
  r.total += 1;
  if (retida) r.retidas += 1;
  const linhas = validar(HISTORICO, m);
  const episodios = Array.isArray(m.episodios) ? m.episodios : [];
  const porEpisodio = episodios.map((ep, i) => (ehObjeto(ep)
    ? validar(EPISODIO, ep, `episodios[${i}].`)
    : [{ campo: `episodios[${i}]`, ok: false, obrigatorio: true, detalhe: `esperado objeto, veio ${resumoValor(ep)}` }]));
  const invalidos = porEpisodio.filter((ls) => ls.some((l) => !l.ok && l.obrigatorio)).length;
  const falhas = [...linhas, ...porEpisodio.flat()].filter((l) => !l.ok);
  if (falhas.length) r.falhas += 1;
  r.episodiosInvalidos = invalidos;
  r.ultimo = m;
  r.ultimoEm = Date.now();

  const recente = episodios[0];
  const descricao = recente
    ? `mais recente: ${recente.id} (${recente.nivel_maximo}, ${recente.encerramento ?? 'em andamento'}, ` +
      `${recente.avaliacao_cuidador}${recente.avaliacao_origem ? ` pelo ${recente.avaliacao_origem}` : ''}` +
      `${recente.visto_pelo_cuidador_em ? `, visto às ${horaIso(recente.visto_pelo_cuidador_em)}` : ''})`
    : 'lista vazia';
  const quando = retida ? ` [retida, publicada às ${horaIso(m.timestamp)}]` : '';
  console.log(`[${hora()}] historico  ${episodios.length} episódio(s) | ${descricao}${quando}`);

  if (r.total === 1) {
    imprimirValidacao(linhas);
    if (porEpisodio.length) {
      console.log('    -- primeiro episódio da lista:');
      imprimirValidacao(porEpisodio[0]);
      const resto = porEpisodio.slice(1).flat().filter((l) => !l.ok);
      if (porEpisodio.length > 1) {
        if (resto.length) imprimirValidacao(resto, { limite: 8 });
        else console.log(`    OK     demais ${porEpisodio.length - 1} episódio(s) no mesmo formato`);
      }
    }
  } else if (falhas.length) {
    imprimirValidacao(falhas, { limite: 8 });
  }
  if (invalidos) console.log(`    FALHA  ${invalidos} episódio(s) seriam pulados pelo app (campo obrigatório inválido)`);
}

function tratarStatus(texto, retida) {
  const r = rel.status;
  r.total += 1;
  const valor = texto.trim().toLowerCase();
  if (valor !== 'online' && valor !== 'offline') {
    r.invalidas += 1;
    console.log(`[${hora()}] status     FALHA: esperado "online" ou "offline", veio ${resumoValor(texto)}`);
    return;
  }
  r.valor = valor;
  r.retida = retida;
  console.log(`[${hora()}] status     pulseira ${valor}${retida ? ' [retida]' : ''}`);
}

// ---------------------------------------------------------------------------
// Execucao
// ---------------------------------------------------------------------------

async function main() {
  const opcoes = lerArgumentos(process.argv.slice(2));
  const { config, problemas, avisos } = lerConfig();
  const { connect, pasta } = carregarMqtt();

  console.log('== verificar-app: conecta no broker COMO O APP do cuidador ==');
  console.log(`config    mobile/env.json → host ${config.host || '(vazio)'} · porta ${config.port || '(inválida)'} · ` +
    `usuário ${config.user || '(vazio)'} · senha ${config.pass ? '(preenchida)' : '(VAZIA)'} · CHILD_ID ${config.childId}`);
  for (const aviso of avisos) console.log(`AVISO     ${aviso}`);
  if (problemas.length) sair(`mobile/env.json incompleto: ${problemas.join(', ')} (o app mostraria "Configuração ausente").`);

  const base = `puzzleband/${config.childId}`;
  const topicos = {
    estado: `${base}/estado`,
    alertas: `${base}/alertas`,
    historico: `${base}/historico`,
    status: `${base}/status`,
    avaliacao: `${base}/avaliacao`,
    ack: `${base}/ack`,
  };

  const client = connect(`mqtts://${config.host}:${config.port}`, {
    username: config.user,
    password: config.pass,
    clientId: `puzzleband-verificar-app-${config.childId}-${randomBytes(3).toString('hex')}`,
    protocolVersion: 5,
    clean: true,
    keepalive: 60,
    reconnectPeriod: 0, // teste: falha rapido em vez de tentar para sempre
    connectTimeout: 10000,
  });
  console.log(`conexão   mqtts://${config.host}:${config.port} (TLS) · pacote mqtt de ${pasta}/`);

  await new Promise((resolve) => {
    const limite = setTimeout(() => {
      sair('o broker não respondeu em 15 s (sem internet, firewall bloqueando a porta 8883 ou host errado).');
    }, 15000);
    client.once('connect', () => {
      clearTimeout(limite);
      resolve();
    });
    client.once('error', (err) => {
      clearTimeout(limite);
      const codigo = err.code;
      if (codigo === 134 || codigo === 4) sair('usuário ou senha recusados pelo broker (confira MQTT_USER e MQTT_PASS no mobile/env.json).');
      if (codigo === 135 || codigo === 5) sair(`o broker recusou o usuário "${config.user}" (não autorizado). Confira o usuário no EMQX.`);
      if (err.code === 'ENOTFOUND') sair(`host não encontrado: ${config.host} (sem internet ou MQTT_HOST errado).`);
      sair(`falha ao conectar: ${err.message}`);
    });
  });
  console.log(`[${hora()}] conectado ao broker como "${config.user}"`);
  let encerrando = false;
  client.on('error', (err) => console.log(`[${hora()}] erro do broker: ${err.message}`));
  client.on('close', () => {
    if (!encerrando) console.log(`[${hora()}] FALHA: conexão com o broker caiu (o relatório fica incompleto)`);
  });

  // PUBACK do MQTT 5 traz o motivo: 0 = entregue a assinante, 16 = ninguem
  // assinando, 135 = negado pela ACL
  const motivoPuback = new Map();
  client.on('packetreceive', (pacote) => {
    if (pacote.cmd === 'puback') motivoPuback.set(pacote.messageId, pacote.reasonCode ?? 0);
  });

  // Tudo o que interessa chegou: estado ao vivo, um alerta e um historico
  // que ja contem o episodio do alerta (a pulseira republica na mesma leitura).
  const completo = () => {
    if (!rel.estado.aoVivo || !rel.alertas.total || !rel.historico.ultimo) return false;
    const idAlerta = rel.alertas.lista.at(-1)?.episodio_id;
    if (!idAlerta) return true;
    return (rel.historico.ultimo.episodios ?? []).some((ep) => ep?.id === idAlerta);
  };

  let ouvindo = true;
  let concluir = () => {};
  const tratar = (topico, texto, retida) => {
    if (topico === topicos.status) {
      tratarStatus(texto, retida);
      return;
    }
    let json;
    try {
      json = JSON.parse(texto);
    } catch {
      json = undefined;
    }
    const chave = Object.keys(topicos).find((k) => topicos[k] === topico);
    if (!ehObjeto(json)) {
      const motivo = json === undefined ? 'não é JSON' : 'o JSON não é um objeto';
      console.log(`[${hora()}] ${chave}: FALHA - ${motivo}, o app descarta: ${resumoValor(texto)}`);
      if (rel[chave]?.falhas !== undefined) rel[chave].falhas += 1;
      return;
    }
    if (chave === 'estado') tratarEstado(json, retida);
    else if (chave === 'alertas') tratarAlerta(json, retida);
    else if (chave === 'historico') tratarHistorico(json, retida);
  };
  client.on('message', (topico, payload, pacote) => {
    tratar(topico, payload.toString(), Boolean(pacote.retain));
    if (ouvindo && completo()) concluir();
  });

  // a) assinaturas, uma por vez para saber qual a ACL negou
  const assinar = (nome, qos) => new Promise((resolve) => {
    client.subscribe(topicos[nome], { qos }, (err, concedidas) => {
      const codigo = err ? err.code : concedidas?.[0]?.qos;
      const ok = !err && codigo !== undefined && codigo < 128;
      rel.assinaturas[nome] = ok ? 'ok' : `negada (${err?.message ?? codigo})`;
      console.log(`assinou   ${topicos[nome].padEnd(28)} QoS ${qos}  ${ok ? 'OK' : `FALHA: ${rel.assinaturas[nome]} — ACL do usuário "${config.user}"?`}`);
      resolve();
    });
  });
  await assinar('estado', 0);
  await assinar('alertas', 1);
  await assinar('historico', 1);
  await assinar('status', 1);

  console.log(`\nEscutando por até ${opcoes.tempo} s (para antes se chegarem estado ao vivo, alerta e histórico). Ctrl+C encerra a escuta.\n`);
  await new Promise((resolve) => {
    const fim = setTimeout(resolve, opcoes.tempo * 1000);
    concluir = () => {
      clearTimeout(fim);
      resolve();
    };
    process.once('SIGINT', () => {
      console.log('\n(Ctrl+C: encerrando a escuta)');
      concluir();
    });
    if (completo()) concluir();
  });
  ouvindo = false;
  if (completo()) console.log(`\n[${hora()}] Recebidos estado ao vivo, alerta e histórico: encerrando a escuta.`);

  // b) ack + avaliacao, no formato de MqttService.enviarCiente/enviarAvaliacao
  if (opcoes.publicar) await publicarTeste(client, topicos, motivoPuback);

  const falhas = imprimirRelatorio(opcoes, config) +
    Object.values(rel.assinaturas).filter((v) => v !== 'ok').length;
  encerrando = true;
  await client.endAsync().catch(() => {});
  process.exit(falhas ? 1 : 0);
}

async function publicarTeste(client, topicos, motivoPuback) {
  const historico = rel.historico.ultimo?.episodios?.filter((ep) => ehObjeto(ep) && T.id.ok(ep.id)) ?? [];
  const idAlerta = rel.alertas.lista.at(-1)?.episodio_id;
  const escolhido = historico.find((ep) => ep.id === idAlerta) ?? historico[0] ?? null;
  const episodioId = escolhido?.id ?? 'teste-verificacao';
  rel.episodioTeste = { id: episodioId, doHistorico: Boolean(escolhido) };

  console.log(`\n== app → pulseira: publicando ack e avaliação de teste ==`);
  if (escolhido) {
    console.log(`episódio  ${episodioId} (${escolhido.id === idAlerta ? 'o do alerta recebido' : 'o mais recente do histórico'})`);
  } else {
    console.log('episódio  "teste-verificacao" — nenhum histórico recebido; a pulseira não conhece esse id e deve só republicar o histórico');
  }

  const agora = new Date();
  const ack = { episodio_id: episodioId, timestamp: agora.toISOString(), origem: 'app' };
  const observacao = `teste do verificar-app às ${hora(agora).slice(0, 5)}`;
  const avaliacao = {
    episodio_id: episodioId,
    avaliacao: 'confirmado',
    observacao,
    origem: 'app',
    timestamp: new Date(agora.getTime() + 1).toISOString(),
  };
  const desde = Date.now();

  const publicar = (nome, mensagem) => new Promise((resolve) => {
    client.publish(topicos[nome], JSON.stringify(mensagem), { qos: 1 }, (err, pacote) => {
      const codigo = err?.code ?? motivoPuback.get(pacote?.messageId);
      const resultado = { nome, mensagem, ok: !err, codigo, erro: err?.message };
      rel.publicacoes.push(resultado);
      let situacao;
      if (err) situacao = `FALHA: ${err.message} — ACL não deixa o usuário do app publicar em ${topicos[nome]}?`;
      else if (codigo === 16) situacao = 'OK (broker aceitou, mas NINGUÉM assina este tópico agora: a pulseira está ligada?)';
      else situacao = 'OK (broker aceitou e entregou a um assinante)';
      console.log(`publicou  ${topicos[nome].padEnd(28)} QoS 1  ${situacao}`);
      console.log(`          ${JSON.stringify(mensagem)}`);
      resolve();
    });
  });
  await publicar('ack', ack);
  await publicar('avaliacao', avaliacao);
  if (rel.publicacoes.some((p) => !p.ok)) return;

  // A pulseira aplica e republica o historico na hora; confere se veio com o ack e a avaliacao
  console.log('\nAguardando a pulseira republicar o histórico (até 8 s)...');
  const confere = () => {
    if (rel.historico.ultimoEm < desde) return null;
    const lista = rel.historico.ultimo?.episodios ?? [];
    if (!escolhido) return { republicou: true };
    const ep = lista.find((e) => e?.id === episodioId);
    if (!ep) return null;
    const mesmaHora = (a, b) => ehIso(a) && Date.parse(a) === Date.parse(b);
    const visto = mesmaHora(ep.visto_pelo_cuidador_em, ack.timestamp);
    const avaliado = ep.avaliacao_cuidador === 'confirmado' && ep.avaliacao_origem === 'app' &&
      mesmaHora(ep.avaliacao_em, avaliacao.timestamp) && ep.observacao === observacao;
    return visto && avaliado ? { republicou: true, visto, avaliado, ep } : null;
  };
  rel.respostaPulseira = await new Promise((resolve) => {
    const inicio = Date.now();
    const timer = setInterval(() => {
      const r = confere();
      if (r || Date.now() - inicio > 8000) {
        clearInterval(timer);
        resolve(r ?? { republicou: rel.historico.ultimoEm >= desde, visto: false, avaliado: false });
      }
    }, 200);
  });
  rel.respostaPulseira.observacao = observacao;
}

function imprimirRelatorio(opcoes, config) {
  const e = rel.estado;
  const a = rel.alertas;
  const h = rel.historico;
  const s = rel.status;
  let falhas = 0;
  const marca = (ok, aviso = false) => {
    if (ok) return 'OK   ';
    if (aviso) return 'AVISO';
    falhas += 1;
    return 'FALHA';
  };

  const intervalos = e.chegadas.slice(1).map((t, i) => t - e.chegadas[i]);
  const media = intervalos.length ? intervalos.reduce((x, y) => x + y, 0) / intervalos.length / 1000 : null;

  console.log('\n================ RELATÓRIO ================');
  console.log(`criança ${config.childId} · usuário "${config.user}" · escuta de até ${opcoes.tempo} s`);

  console.log('\npulseira → app');
  if (!e.total) {
    console.log(`  ${marca(false)}  estado      nenhuma mensagem: a pulseira nunca publicou (ou a ACL negou a assinatura)`);
  } else if (!e.aoVivo) {
    console.log(`  ${marca(false, true)}  estado      só o estado retido, velho (de ${horaIso(e.ultimo?.timestamp)}): a pulseira não está ligada/conectada agora`);
  } else {
    const ritmo = media ? `, intervalo médio ${media.toFixed(2)} s` : '';
    console.log(`  ${marca(!e.falhas)}  estado      ${e.total} mensagem(ns), ${e.aoVivo} ao vivo${ritmo}${e.falhas ? `, ${e.falhas} com FALHA de formato` : ', formato OK'}`);
  }
  if (!a.total) {
    console.log(`  ${marca(false, true)}  alertas     nenhum em ${opcoes.tempo} s — só chega quando o nível MUDA para atenção ou possível crise`);
  } else {
    const ultimo = a.lista.at(-1);
    console.log(`  ${marca(!a.falhas)}  alertas     ${a.total} alerta(s), último ${ultimo.nivel_anterior} → ${ultimo.nivel}, gatilho: ${ultimo.gatilho?.texto ? `"${ultimo.gatilho.texto}"` : '—'}${a.falhas ? ', com FALHA de formato' : ', formato OK'}`);
  }
  if (!h.total) {
    console.log(`  ${marca(false)}  historico   nenhuma mensagem: a pulseira nunca publicou (é retido, chegaria na hora)`);
  } else {
    const n = h.ultimo?.episodios?.length ?? 0;
    const origem = h.retidas === h.total ? ` (só a retida, de ${horaIso(h.ultimo?.timestamp)})` : ` (${h.total - h.retidas} nova(s) nesta execução)`;
    console.log(`  ${marca(!h.falhas)}  historico   ${n} episódio(s)${origem}${h.falhas ? ', com FALHA de formato' : ', formato OK'}`);
  }
  if (!s.total) console.log(`  ${marca(false, true)}  status      nenhum (a pulseira nunca conectou com este CHILD_ID)`);
  else console.log(`  ${marca(!s.invalidas)}  status      ${s.valor ?? 'inválido'}${s.retida ? ' (retido)' : ''}`);

  console.log('\napp → pulseira');
  if (!opcoes.publicar) {
    console.log('  —      não publicado (--sem-publicar)');
  } else {
    for (const p of rel.publicacoes) {
      const ninguem = p.codigo === 16 ? ' — mas ninguém assinava (pulseira desligada?)' : '';
      console.log(`  ${marca(p.ok)}  ${p.nome.padEnd(10)}  ${p.ok ? `publicado (PUBACK)${ninguem}` : `RECUSADO: ${p.erro}`}`);
    }
    const r = rel.respostaPulseira;
    const id = rel.episodioTeste?.id;
    if (!r) {
      // publicacao recusada: ja reportado acima
    } else if (rel.episodioTeste?.doHistorico) {
      if (r.visto && r.avaliado) {
        console.log(`  OK     resposta    a pulseira aplicou o ack e a avaliação e republicou o histórico (episódio ${id})`);
      } else if (r.republicou) {
        console.log(`  ${marca(false)}  resposta    a pulseira republicou o histórico, mas sem o ack/avaliação deste teste`);
      } else {
        console.log('  AVISO  resposta    a pulseira não republicou o histórico em 8 s (ela está ligada e conectada?)');
      }
    } else {
      console.log(r.republicou
        ? '  OK     resposta    a pulseira recebeu e republicou o histórico (não conhece "teste-verificacao")'
        : '  AVISO  resposta    a pulseira não respondeu em 8 s (ela está ligada e conectada?)');
    }
    if (rel.episodioTeste?.doHistorico) {
      console.log('\n  Confira no app, no painel do site (se estiver aberto) ou em simulator/data/historico_<id>.json:');
      console.log(`    - episódio ${id}: "✓ confirmado pelo cuidador", etiqueta "avaliado pelo app às HH:MM"`);
      console.log(`      e a observação "${r?.observacao ?? ''}" (pode apagar ou reavaliar depois);`);
      console.log('    - "Alerta visto pelo cuidador às HH:MM" no episódio e, se ele ainda estiver em andamento, no banner.');
    }
  }
  console.log('===========================================');
  return falhas;
}

// Os formatos ficam exportados para conferir mensagens geradas offline
// (ex.: pelas funcoes de frontend/src/hooks/buildMessages.js).
export { ESTADO, ALERTA, EPISODIO, HISTORICO, validar };

// Roda so quando chamado direto (node tools/verificar-app.mjs), nao no import
function ehPrincipal() {
  try {
    const chamado = realpathSync(process.argv[1]);
    const este = realpathSync(fileURLToPath(import.meta.url));
    return process.platform === 'win32' ? chamado.toLowerCase() === este.toLowerCase() : chamado === este;
  } catch {
    return false;
  }
}

if (ehPrincipal()) main().catch((err) => sair(err?.stack ?? String(err)));
