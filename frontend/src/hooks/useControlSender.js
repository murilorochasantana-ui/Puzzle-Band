import { useEffect, useRef, useState } from 'react';
import { CONTROL_MIN_INTERVAL_MS, createThrottle } from './throttle';

// Envia os valores do "Controle da pulseira" para puzzleband/<id>/controle:
//   - a cada mudanca, no maximo 2x por segundo (throttle), sempre com o
//     ultimo valor;
//   - de novo quando o painel (re)conecta ou a pulseira volta a ficar online:
//     a pulseira comeca calma e nao guarda o comando anterior, entao assim o
//     que ela segue fica igual ao que o painel mostra.
// Devolve quando foi o ultimo envio (ISO) ou null.
export default function useControlSender({ values, publishControl, connected, bandStatus, connectionId }) {
  const [lastSentAt, setLastSentAt] = useState(null);
  const publishRef = useRef(publishControl);
  const valuesRef = useRef(values);
  useEffect(() => {
    publishRef.current = publishControl;
    valuesRef.current = values;
  });

  // O throttle vive enquanto o painel estiver aberto (criado antes dos
  // efeitos abaixo, que rodam na ordem em que estao declarados)
  const throttleRef = useRef(null);
  useEffect(() => {
    const throttle = createThrottle((next) => {
      if (publishRef.current(next)) setLastSentAt(new Date().toISOString());
    }, CONTROL_MIN_INTERVAL_MS);
    throttleRef.current = throttle;
    return () => {
      throttle.cancel();
      throttleRef.current = null;
    };
  }, []);

  useEffect(() => {
    throttleRef.current?.call(values);
  }, [values]);

  const bandOnline = connected && bandStatus === 'online';
  useEffect(() => {
    if (bandOnline) throttleRef.current?.call(valuesRef.current);
  }, [bandOnline, connectionId]);

  return lastSentAt;
}
