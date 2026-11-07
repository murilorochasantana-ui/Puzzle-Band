// Modo "controle remoto" da pulseira (npm run controle): em vez de seguir um
// cenario, as leituras seguem os valores-alvo que o painel do site publica em
// puzzleband/<id>/controle. Sem comando recebido, fica no estado calmo.
//
// As leituras saem do MESMO gerador de sempre (generateReading, em
// frontend/src/model/simulate.js: mesmo ruido de sensor). A diferenca e a
// transicao: cada sinal vai do valor atual ate o novo alvo numa RAMPA linear
// de RAMPA_CONTROLE_S segundos (a mesma das rampas ambientais dos cenarios),
// como um sinal real, que nao muda de um segundo para o outro. A idade nao
// tem rampa (muda na hora).

import { CALM_CONTROL, CONTROL_LIMITS, controlTargets } from '../frontend/src/model/simulate.js';

export const CONTROLE = 'controle'; // nome do "cenario" na linha de comando
export const RAMPA_CONTROLE_S = 20;
const SEM_RAMPA = new Set(['idade']);

export const CONTROLE_DESCRICAO = 'Controle remoto: segue os valores-alvo enviados pelo painel do site'
  + ` (puzzleband/<id>/controle), com transição de ${RAMPA_CONTROLE_S} s; sem comando, fica calmo`;

// Relogio em ticks (1 tick = 1 leitura = 1 s). set() pode ser chamado a
// qualquer momento (mensagem MQTT); next() avanca um tick e devolve os
// valores daquele instante.
export function createControl({ inicial = CALM_CONTROL, rampaS = RAMPA_CONTROLE_S } = {}) {
  let t = 0;
  const canais = Object.fromEntries(
    Object.keys(CONTROL_LIMITS).map((campo) => [campo, { de: inicial[campo], para: inicial[campo], inicio: 0 }]),
  );
  let recebidos = 0;

  const valorDe = (campo, tick) => {
    const c = canais[campo];
    if (SEM_RAMPA.has(campo) || tick - c.inicio >= rampaS) return c.para;
    return c.de + ((c.para - c.de) * (tick - c.inicio)) / rampaS;
  };
  const valores = (tick) => Object.fromEntries(Object.keys(canais).map((campo) => [campo, valorDe(campo, tick)]));

  return {
    // `novos`: so os campos validos (parseControl ja filtrou as faixas)
    set(novos) {
      recebidos += 1;
      for (const [campo, alvo] of Object.entries(novos)) {
        if (!canais[campo] || canais[campo].para === alvo) continue;
        canais[campo] = { de: valorDe(campo, t), para: alvo, inicio: t };
      }
    },
    next() {
      const atual = valores(t);
      t += 1;
      return atual;
    },
    alvos: () => Object.fromEntries(Object.entries(canais).map(([campo, c]) => [campo, c.para])),
    emTransicao: () => Object.keys(canais).filter((campo) => valorDe(campo, t) !== canais[campo].para),
    comandosRecebidos: () => recebidos,
  };
}

const fmt = (campo, v) => (campo === 'eda' || campo === 'regularidade' ? v.toFixed(2) : String(Math.round(v)));

// Ticks no mesmo formato de programTicks (scenarios.js), sem fim (Ctrl+C ou --duracao)
export function* controlTicks(control) {
  for (let t = 0; ; t += 1) {
    const indo = control.emTransicao();
    const alvos = control.alvos();
    let fase;
    if (!control.comandosRecebidos()) fase = 'controle remoto · calmo (nenhum comando recebido ainda)';
    else if (indo.length) fase = `controle remoto · em transição para ${indo.map((c) => `${c} ${fmt(c, alvos[c])}`).join(', ')}`;
    else fase = 'controle remoto · nos valores-alvo';
    yield { t, alvos: controlTargets(control.next()), fase };
  }
}
