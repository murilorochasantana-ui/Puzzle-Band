import { useCallback, useEffect, useRef, useState } from 'react';
import mqtt from 'mqtt';
import {
  parseAlert,
  parseAppStatus,
  parseBandStatus,
  parseHistory,
  parseReading,
  parseState,
} from './parseMessages';
import { buildControlMessage, buildEvaluationMessage, topicsFor } from './buildMessages';

// Ligacao do PAINEL (site) com o broker (WebSocket + TLS). O site nao
// processa nada: a pulseira (simulator/) roda o modelo, os episodios e o
// gatilho - processamento na borda - e publica o resultado. O painel so
// assina e mostra, e publica dois topicos de comando para a pulseira:
//   controle   valores-alvo do "Controle da pulseira" (modo npm run controle)
//   avaliacao  "Confirmar gatilho" / "Descartar" do historico, com origem "site"
//
// Assinaturas: leituras (QoS 0), status, app/status, estado, alertas e
// historico (QoS 1). O painel NAO publica estado, alertas nem historico: a
// pulseira e a unica dona desses topicos.
//
// Status do broker: conectando | conectado | desconectado | erro
// Status da pulseira e do app: online | offline | desconhecido (sem mensagem ainda)

function readConfig() {
  const env = import.meta.env;
  const config = {
    url: env.VITE_MQTT_URL,
    username: env.VITE_MQTT_USER,
    password: env.VITE_MQTT_PASS,
    childId: env.VITE_CHILD_ID,
  };
  const missing = [
    ['VITE_MQTT_URL', config.url],
    ['VITE_MQTT_USER', config.username],
    ['VITE_MQTT_PASS', config.password],
    ['VITE_CHILD_ID', config.childId],
  ].filter(([, value]) => !value).map(([name]) => name);
  return { config, missing };
}

// As variaveis VITE_* sao fixadas no build, entao a leitura e feita uma vez so.
const { config, missing } = readConfig();
const configured = missing.length === 0;
const topics = configured ? topicsFor(config.childId) : null;
const randomSuffix = () => Math.random().toString(16).slice(2, 8);

export default function useBandLink({ maxBuffer }) {
  const [readings, setReadings] = useState([]);
  const [brokerStatus, setBrokerStatus] = useState('conectando');
  const [bandStatus, setBandStatus] = useState('desconhecido');
  const [appStatus, setAppStatus] = useState('desconhecido');
  const [errorMessage, setErrorMessage] = useState(null);
  const [state, setState] = useState(null); // ultimo estado (parseState)
  const [history, setHistory] = useState(null); // ultimo historico (parseHistory)
  const [lastAlert, setLastAlert] = useState(null); // ultimo alerta (parseAlert)
  // +1 a cada (re)conexao: o painel reenvia os valores do controle
  const [connectionId, setConnectionId] = useState(0);
  const clientRef = useRef(null);

  useEffect(() => {
    if (!configured) return undefined;

    let lastError = null;
    let disposed = false; // eventos tardios de um cliente ja encerrado sao ignorados

    const client = mqtt.connect(config.url, {
      username: config.username,
      password: config.password,
      clientId: `puzzleband-dash-${config.childId}-${randomSuffix()}`,
      reconnectPeriod: 3000,
      connectTimeout: 10000,
      queueQoSZero: false,
    });
    clientRef.current = client;

    client.on('connect', () => {
      if (disposed) return;
      lastError = null;
      setErrorMessage(null);
      setBrokerStatus('conectado');
      // clean session: as assinaturas sao refeitas a cada (re)conexao. Os
      // topicos com retain (status, app/status, estado, historico) entregam o
      // ultimo valor logo apos a assinatura.
      client.subscribe(topics.leituras, { qos: 0 });
      client.subscribe([topics.status, topics.appStatus, topics.estado, topics.alertas, topics.historico], { qos: 1 });
      setConnectionId((n) => n + 1);
    });
    client.on('reconnect', () => {
      if (!disposed && !lastError) setBrokerStatus('conectando');
    });
    client.on('close', () => {
      if (disposed) return;
      setBrokerStatus(lastError ? 'erro' : 'desconectado');
      // sem conexao nao sabemos mais se a pulseira e o app estao online
      setBandStatus('desconhecido');
      setAppStatus('desconhecido');
    });
    client.on('error', (err) => {
      if (disposed) return;
      lastError = err;
      setErrorMessage(err.message);
      setBrokerStatus('erro');
    });

    client.on('message', (topic, payload, packet) => {
      if (disposed) return;
      const text = payload.toString();
      if (topic === topics.leituras) {
        const reading = parseReading(text);
        if (!reading) return; // malformada: descarta sem quebrar a tela
        setReadings((prev) => {
          const next = [...prev, reading];
          return next.length > maxBuffer ? next.slice(next.length - maxBuffer) : next;
        });
      } else if (topic === topics.estado) {
        const message = parseState(text);
        if (message) setState(message);
      } else if (topic === topics.alertas) {
        const message = parseAlert(text);
        // alerta e sem retain; um "retido" seria lixo antigo no broker
        if (message && !packet?.retain) setLastAlert(message);
      } else if (topic === topics.historico) {
        const message = parseHistory(text);
        if (message) setHistory(message);
      } else if (topic === topics.status) {
        const status = parseBandStatus(text);
        if (status) setBandStatus(status);
      } else if (topic === topics.appStatus) {
        const status = parseAppStatus(text);
        if (status) setAppStatus(status);
      }
    });

    return () => {
      disposed = true;
      clientRef.current = null;
      client.end(true);
      setReadings([]);
      setState(null);
      setHistory(null);
      setLastAlert(null);
      setBrokerStatus('conectando');
      setBandStatus('desconhecido');
      setAppStatus('desconhecido');
      setErrorMessage(null);
    };
  }, [maxBuffer]);

  // So publica com o broker conectado (um comando velho entregue depois da
  // reconexao seria enganoso). Devolve true se enviou.
  const publish = useCallback((topicKey, message) => {
    const client = clientRef.current;
    if (!client?.connected) return false;
    client.publish(topics[topicKey], JSON.stringify(message), { qos: 1 });
    return true;
  }, []);

  // Valores-alvo do "Controle da pulseira" (QoS 1, sem retain)
  const publishControl = useCallback(
    (values) => publish('controle', buildControlMessage(values, { timestamp: new Date().toISOString() })),
    [publish],
  );

  // Confirmar / Descartar / desfazer ("pendente") um episodio: quem aplica e a pulseira
  const publishEvaluation = useCallback(
    ({ episodioId, avaliacao, observacao }) => publish('avaliacao', buildEvaluationMessage({
      episodioId, avaliacao, observacao, timestamp: new Date().toISOString(),
    })),
    [publish],
  );

  return {
    readings: configured ? readings : [],
    state: configured ? state : null,
    history: configured ? history : null,
    lastAlert: configured ? lastAlert : null,
    brokerStatus: configured ? brokerStatus : 'erro',
    bandStatus: configured ? bandStatus : 'desconhecido',
    appStatus: configured ? appStatus : 'desconhecido',
    error: configured ? errorMessage : `Configuração ausente no .env: ${missing.join(', ')}`,
    childId: config.childId,
    connected: configured && brokerStatus === 'conectado',
    connectionId,
    publishControl,
    publishEvaluation,
  };
}
