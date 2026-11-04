import { useEffect, useRef } from 'react';
import {
  STATE_INTERVAL_MS,
  buildHistoryMessage,
  buildStateMessage,
  historySignature,
} from './buildMessages';

// Sincronia site <-> app do cuidador pelo MQTT (ver docs/mqtt.md), nos dois
// modos (Simulador manual e Pulseira):
//   - publica puzzleband/<id>/estado 1x/s (QoS 0, retain);
//   - republica puzzleband/<id>/historico (QoS 1, retain) quando um episodio
//     abre, fecha ou e avaliado, e a cada (re)conexao;
//   - aplica a avaliacao (puzzleband/<id>/avaliacao) e o "Estou ciente"
//     (puzzleband/<id>/ack) recebidos do app no historico local.
// Os alertas (puzzleband/<id>/alertas) saem do useEpisodeMonitor (onAlert).

const HISTORY_DEBOUNCE_MS = 800; // agrupa mudancas proximas (ex.: digitacao da observacao)

export default function useCaregiverSync({ link, monitor, source, tier, probability, readings }) {
  const { childId, connected, connectionId, publishState, publishHistory, addMessageListener } = link;
  const { evaluate, setObservation, markSeen } = monitor;

  // Ultimo estado da tela, lido pelos timers sem reiniciar a cada render
  const latestRef = useRef(null);
  useEffect(() => {
    latestRef.current = {
      source,
      tier,
      probability,
      readings,
      openEpisode: monitor.openEpisode,
      episodes: monitor.episodes,
    };
  });

  // Estado ao vivo, 1x por segundo enquanto conectado
  useEffect(() => {
    if (!connected) return undefined;
    const tick = () => {
      const snapshot = latestRef.current;
      if (!snapshot) return;
      publishState(buildStateMessage({ ...snapshot, childId, timestamp: new Date().toISOString() }));
    };
    tick();
    const timer = setInterval(tick, STATE_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [connected, childId, publishState]);

  // Historico: so quando a assinatura muda (abre/fecha/avaliado/visto), e ao (re)conectar
  const signature = historySignature(monitor.episodes);
  useEffect(() => {
    if (!connected) return undefined;
    const timer = setTimeout(() => {
      const episodes = latestRef.current?.episodes ?? [];
      publishHistory(buildHistoryMessage(episodes, { childId, timestamp: new Date().toISOString() }));
    }, HISTORY_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [signature, connected, connectionId, childId, publishHistory]);

  // Mensagens do app
  useEffect(() => addMessageListener((type, message) => {
    const episodes = latestRef.current?.episodes ?? [];
    if (!episodes.some((ep) => ep.id === message.episodio_id)) {
      // Episodio que o site nao tem (historico limpo, outro navegador): reenvia
      // a lista atual para o app se corrigir.
      publishHistory(buildHistoryMessage(episodes, { childId, timestamp: new Date().toISOString() }));
      return;
    }
    if (type === 'avaliacao') {
      evaluate(message.episodio_id, message.avaliacao, { origem: 'app', em: message.timestamp ?? undefined });
      if (message.observacao !== undefined) setObservation(message.episodio_id, message.observacao);
    } else if (type === 'ack') {
      markSeen(message.episodio_id, message.timestamp);
    }
  }), [addMessageListener, childId, evaluate, setObservation, markSeen, publishHistory]);
}
