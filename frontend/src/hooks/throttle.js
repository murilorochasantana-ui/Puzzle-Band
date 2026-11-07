// Limitacao de frequencia (throttle) para o "Controle da pulseira": arrastar
// um controle gera dezenas de mudancas por segundo, mas o topico controle
// recebe no maximo 1 mensagem a cada `intervalMs`. A primeira mudanca sai na
// hora; as seguintes dentro do intervalo viram UMA mensagem no fim dele, com o
// valor mais recente (o ultimo valor nunca se perde).
//
// Funcao pura com relogio injetavel (testada em Node, hooks/messages.test.js).

export const CONTROL_MIN_INTERVAL_MS = 500; // no maximo 2 mensagens por segundo

export function createThrottle(fn, intervalMs, clock = {}) {
  const now = clock.now ?? (() => Date.now());
  const schedule = clock.setTimeout ?? ((cb, ms) => setTimeout(cb, ms));
  const unschedule = clock.clearTimeout ?? ((id) => clearTimeout(id));

  let lastSent = -Infinity;
  let timer = null;
  let pending = null; // { value } enquanto houver algo para enviar

  const flush = () => {
    timer = null;
    if (!pending) return;
    const { value } = pending;
    pending = null;
    lastSent = now();
    fn(value);
  };

  return {
    call(value) {
      pending = { value };
      if (timer) return; // ja tem envio marcado: ele leva o valor mais recente
      const wait = lastSent + intervalMs - now();
      if (wait <= 0) flush();
      else timer = schedule(flush, wait);
    },
    cancel() {
      if (timer) unschedule(timer);
      timer = null;
      pending = null;
    },
  };
}
