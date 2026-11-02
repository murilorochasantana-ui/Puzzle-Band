import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { classifyAt } from '../model/classify';
import {
  closeOpenEpisode,
  createEpisodeStore,
  createMonitor,
  ingestReadings,
  updateEpisode,
  upsertEpisode,
} from '../model/episodes';

// Liga o rastreador de episodios (model/episodes.js) ao dashboard: classifica
// cada leitura NOVA do buffer com o modelo, detecta inicio/fim de episodio,
// calcula o provavel gatilho e guarda o historico no localStorage. Toda a
// logica fica em funcoes puras (testadas em Node); aqui so o "encanamento".

// Acessar localStorage pode lancar excecao (modo privado, bloqueio de cookies)
function browserStorage() {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export default function useEpisodeMonitor({ readings, source, childId, onAlert }) {
  const [store] = useState(() => createEpisodeStore(browserStorage()));
  const { episodes, storageOk } = useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot);

  const monitorRef = useRef(null);
  const lastReadingRef = useRef(null);
  const discardedRef = useRef(new Set()); // episodios apagados enquanto ainda abertos
  const onAlertRef = useRef(onAlert);
  useEffect(() => {
    onAlertRef.current = onAlert;
  });

  const applyEpisodes = useCallback((changed) => {
    const list = changed.filter((ep) => ep && !discardedRef.current.has(ep.id));
    if (!list.length) return;
    store.update((prev) => list.reduce((acc, ep) => upsertEpisode(acc, ep), prev));
  }, [store]);

  // Troca de fonte ou de crianca: encerra o episodio aberto e recomeca.
  useEffect(() => {
    applyEpisodes([closeOpenEpisode(monitorRef.current)]);
    monitorRef.current = createMonitor({ childId, source });
    lastReadingRef.current = null;
  }, [source, childId, applyEpisodes]);

  useEffect(() => {
    if (!monitorRef.current) return;
    const result = ingestReadings(monitorRef.current, lastReadingRef.current, readings, classifyAt);
    monitorRef.current = result.monitor;
    lastReadingRef.current = result.lastReading;
    applyEpisodes(result.changed);
    // puzzleband/<id>/alertas: mesmo formato de antes + episodio_id e gatilho
    const publish = onAlertRef.current;
    if (publish) result.alerts.forEach((alert) => publish({ timestamp: new Date().toISOString(), ...alert }));
  }, [readings, applyEpisodes]);

  const evaluate = useCallback((id, avaliacao) => {
    store.update((prev) => updateEpisode(prev, id, { avaliacao_cuidador: avaliacao }));
  }, [store]);

  const setObservation = useCallback((id, observacao) => {
    store.update((prev) => updateEpisode(prev, id, { observacao }));
  }, [store]);

  const clearHistory = useCallback(() => {
    const open = monitorRef.current?.open?.episode;
    if (open) discardedRef.current.add(open.id);
    store.update(() => []);
  }, [store]);

  return {
    episodes,
    openEpisode: episodes.find((ep) => !ep.encerramento) ?? null,
    storageOk,
    evaluate,
    setObservation,
    clearHistory,
  };
}
