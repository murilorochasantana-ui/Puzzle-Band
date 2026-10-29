import { useCallback, useEffect, useRef, useState } from 'react';
import mqtt from 'mqtt';
import { parseBandStatus, parseReading } from './parseMessages';

// Status do broker: conectando | conectado | desconectado | erro
// Status da pulseira: online | offline | desconhecido (ainda sem mensagem de status)

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
const randomSuffix = () => Math.random().toString(16).slice(2, 8);

// Conecta ao broker (WebSocket + TLS) enquanto `enabled` for true; ao
// desligar ou desmontar, desconecta e zera o estado.
export default function useMqttReadings({ enabled, maxBuffer }) {
  const configured = missing.length === 0;
  const active = enabled && configured;

  const [readings, setReadings] = useState([]);
  const [brokerStatus, setBrokerStatus] = useState('conectando');
  const [bandStatus, setBandStatus] = useState('desconhecido');
  const [errorMessage, setErrorMessage] = useState(null);
  const clientRef = useRef(null);

  useEffect(() => {
    if (!active) return undefined;

    const base = `puzzleband/${config.childId}`;
    const topicReadings = `${base}/leituras`;
    const topicStatus = `${base}/status`;
    let lastError = null;
    let disposed = false; // eventos tardios de um cliente ja encerrado sao ignorados

    const client = mqtt.connect(config.url, {
      username: config.username,
      password: config.password,
      clientId: `puzzleband-dash-${config.childId}-${randomSuffix()}`,
      reconnectPeriod: 3000,
      connectTimeout: 10000,
    });
    clientRef.current = client;

    client.on('connect', () => {
      if (disposed) return;
      lastError = null;
      setErrorMessage(null);
      setBrokerStatus('conectado');
      // clean session: as assinaturas precisam ser refeitas a cada (re)conexao.
      // Leituras em QoS 0; status em QoS 1 (recebe o "retain" da pulseira na hora).
      client.subscribe(topicReadings, { qos: 0 });
      client.subscribe(topicStatus, { qos: 1 });
    });
    client.on('reconnect', () => {
      if (!disposed && !lastError) setBrokerStatus('conectando');
    });
    client.on('close', () => {
      if (disposed) return;
      setBrokerStatus(lastError ? 'erro' : 'desconectado');
      // sem conexao nao sabemos mais se a pulseira esta online
      setBandStatus('desconhecido');
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
      if (topic === topicReadings) {
        const reading = parseReading(text);
        if (!reading) return; // malformada: descarta sem quebrar a tela
        setReadings((prev) => {
          const next = [...prev, reading];
          return next.length > maxBuffer ? next.slice(next.length - maxBuffer) : next;
        });
      } else if (topic === topicStatus) {
        const status = parseBandStatus(text);
        if (status) setBandStatus(status);
      }
    });

    return () => {
      disposed = true;
      clientRef.current = null;
      client.end(true);
      setReadings([]);
      setBrokerStatus('conectando');
      setBandStatus('desconhecido');
      setErrorMessage(null);
    };
  }, [active, maxBuffer]);

  // Alertas vao para puzzleband/<id>/alertas (QoS 1, sem retain). So publica
  // com o broker conectado - um alerta velho entregue depois da reconexao
  // seria enganoso.
  const publishAlert = useCallback((alert) => {
    const client = clientRef.current;
    if (!client?.connected) return;
    client.publish(`puzzleband/${config.childId}/alertas`, JSON.stringify(alert), { qos: 1 });
  }, []);

  let status = brokerStatus;
  let error = errorMessage;
  if (!active) {
    status = enabled ? 'erro' : 'desconectado';
    error = enabled ? `Configuração ausente no .env: ${missing.join(', ')}` : null;
  }

  return {
    readings: active ? readings : [],
    brokerStatus: status,
    bandStatus: active ? bandStatus : 'desconhecido',
    error,
    childId: config.childId,
    publishAlert,
  };
}
