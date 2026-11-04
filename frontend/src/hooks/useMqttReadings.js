import { useCallback, useEffect, useRef, useState } from 'react';
import mqtt from 'mqtt';
import { parseAck, parseAppStatus, parseBandStatus, parseEvaluation, parseReading } from './parseMessages';
import { topicsFor } from './buildMessages';

// Ligacao do site com o broker (WebSocket + TLS). Fica conectada nos DOIS
// modos (Simulador manual e Pulseira), porque o site e o "servidor" do app do
// cuidador: publica estado/alertas/historico e recebe avaliacao/ack.
//
// Status do broker: conectando | conectado | desconectado | erro
// Status da pulseira e do app: online | offline | desconhecido (sem mensagem ainda)
//
// Assinaturas: leituras, status, app/status, avaliacao, ack. O site NUNCA
// assina estado/alertas/historico (que ele mesmo publica): assim nao
// reprocessa as proprias mensagens.

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

// `readingsEnabled`: so no modo Pulseira as leituras recebidas entram no
// buffer; ao ligar/desligar, o buffer e zerado.
export default function useMqttReadings({ readingsEnabled, maxBuffer }) {
  const [readings, setReadings] = useState([]);
  const [brokerStatus, setBrokerStatus] = useState('conectando');
  const [bandStatus, setBandStatus] = useState('desconhecido');
  const [appStatus, setAppStatus] = useState('desconhecido');
  const [errorMessage, setErrorMessage] = useState(null);
  // +1 a cada (re)conexao: quem publica mensagens "retain" republica ao reconectar
  const [connectionId, setConnectionId] = useState(0);
  const clientRef = useRef(null);
  const readingsEnabledRef = useRef(readingsEnabled);
  const listenersRef = useRef(new Set());

  // Troca de modo: o buffer recomeca vazio (ajuste de estado durante o render,
  // o padrao do React para "resetar quando a prop muda").
  const [bufferMode, setBufferMode] = useState(readingsEnabled);
  if (bufferMode !== readingsEnabled) {
    setBufferMode(readingsEnabled);
    setReadings([]);
  }
  useEffect(() => {
    readingsEnabledRef.current = readingsEnabled;
  }, [readingsEnabled]);

  useEffect(() => {
    if (!configured) return undefined;

    let lastError = null;
    let disposed = false; // eventos tardios de um cliente ja encerrado sao ignorados
    const emit = (type, message) => {
      listenersRef.current.forEach((listener) => listener(type, message));
    };

    const client = mqtt.connect(config.url, {
      username: config.username,
      password: config.password,
      clientId: `puzzleband-dash-${config.childId}-${randomSuffix()}`,
      reconnectPeriod: 3000,
      connectTimeout: 10000,
      queueQoSZero: false, // estado velho nao serve: sem conexao, descarta
    });
    clientRef.current = client;

    client.on('connect', () => {
      if (disposed) return;
      lastError = null;
      setErrorMessage(null);
      setBrokerStatus('conectado');
      // clean session: as assinaturas precisam ser refeitas a cada (re)conexao.
      // Leituras em QoS 0; o resto em QoS 1 (status chegam na hora pelo retain).
      client.subscribe(topics.leituras, { qos: 0 });
      client.subscribe([topics.status, topics.appStatus, topics.avaliacao, topics.ack], { qos: 1 });
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

    client.on('message', (topic, payload) => {
      if (disposed) return;
      const text = payload.toString();
      if (topic === topics.leituras) {
        if (!readingsEnabledRef.current) return; // modo manual: leituras da pulseira nao entram
        const reading = parseReading(text);
        if (!reading) return; // malformada: descarta sem quebrar a tela
        setReadings((prev) => {
          const next = [...prev, reading];
          return next.length > maxBuffer ? next.slice(next.length - maxBuffer) : next;
        });
      } else if (topic === topics.status) {
        const status = parseBandStatus(text);
        if (status) setBandStatus(status);
      } else if (topic === topics.appStatus) {
        const status = parseAppStatus(text);
        if (status) setAppStatus(status);
      } else if (topic === topics.avaliacao) {
        const message = parseEvaluation(text);
        if (message) emit('avaliacao', message);
      } else if (topic === topics.ack) {
        const message = parseAck(text);
        if (message) emit('ack', message);
      }
    });

    return () => {
      disposed = true;
      clientRef.current = null;
      client.end(true);
      setReadings([]);
      setBrokerStatus('conectando');
      setBandStatus('desconhecido');
      setAppStatus('desconhecido');
      setErrorMessage(null);
    };
  }, [maxBuffer]);

  // So publica com o broker conectado - um estado ou alerta velho entregue
  // depois da reconexao seria enganoso. Devolve true se enviou.
  const publish = useCallback((topicKey, message, options) => {
    const client = clientRef.current;
    if (!client?.connected) return false;
    client.publish(topics[topicKey], JSON.stringify(message), options);
    return true;
  }, []);

  const publishState = useCallback((message) => publish('estado', message, { qos: 0, retain: true }), [publish]);
  const publishAlert = useCallback((message) => publish('alertas', message, { qos: 1 }), [publish]);
  const publishHistory = useCallback((message) => publish('historico', message, { qos: 1, retain: true }), [publish]);

  // Avaliacao e ack vindos do app: listener(type, message), type = 'avaliacao' | 'ack'.
  // Devolve a funcao que remove o listener (formato de cleanup do useEffect).
  const addMessageListener = useCallback((listener) => {
    listenersRef.current.add(listener);
    return () => {
      listenersRef.current.delete(listener);
    };
  }, []);

  return {
    readings: configured && readingsEnabled ? readings : [],
    brokerStatus: configured ? brokerStatus : 'erro',
    bandStatus: configured ? bandStatus : 'desconhecido',
    appStatus: configured ? appStatus : 'desconhecido',
    error: configured ? errorMessage : `Configuração ausente no .env: ${missing.join(', ')}`,
    childId: config.childId,
    connected: configured && brokerStatus === 'conectado',
    connectionId,
    publishState,
    publishAlert,
    publishHistory,
    addMessageListener,
  };
}
