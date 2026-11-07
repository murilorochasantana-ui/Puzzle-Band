// Apoio aos testes da pulseira (node:test): cliente MQTT falso e execucao de
// cenarios sem relogio, com semente (resultado reprodutivel).

import { EventEmitter } from 'node:events';
import { generateReading } from '../../frontend/src/model/simulate.js';
import { programTicks, seeded, withRandom } from '../scenarios.js';

export const T0 = Date.parse('2026-01-01T12:00:00Z');
export const isoAt = (t) => new Date(T0 + t * 1000).toISOString();

// Cliente MQTT falso: guarda o que foi publicado/assinado e entrega mensagens
// como o broker entregaria. Nao ha site nenhum do outro lado.
//   retained   { topico: payload }: entregues (retain) logo apos subscribeAsync
//   deny       topicos que a "ACL" recusa (SUBACK 135 / PUBACK com erro)
//   onPublish  (mensagem) => void, chamado a cada publicacao (ex.: o app responder)
export class FakeClient extends EventEmitter {
  constructor({ retained = {}, deny = [], onPublish = null } = {}) {
    super();
    this.connected = false;
    this.published = [];
    this.subscribed = new Set();
    this.unsubscribed = [];
    this.retained = { ...retained };
    this.deny = new Set(deny);
    this.onPublish = onPublish;
  }

  connect() {
    this.connected = true;
    this.emit('connect');
  }

  disconnect() {
    this.connected = false;
  }

  publish(topic, payload, options = {}) {
    const message = { topic, payload: String(payload), qos: options.qos ?? 0, retain: Boolean(options.retain) };
    this.published.push(message);
    this.onPublish?.(message);
  }

  async publishAsync(topic, payload, options) {
    if (this.deny.has(topic)) {
      const err = new Error('Publish error: Not authorized');
      err.code = 135;
      throw err;
    }
    this.publish(topic, payload, options);
  }

  subscribe(topics) {
    const list = typeof topics === 'string' ? [topics] : Array.isArray(topics) ? topics : Object.keys(topics);
    for (const t of list) this.subscribed.add(t);
  }

  // Como o mqtt.js com MQTT 5: devolve o "granted" (qos 135 = recusado pela
  // ACL) e entrega os retidos dos topicos assinados logo depois.
  async subscribeAsync(topics, options = {}) {
    const list = typeof topics === 'string' ? [topics] : Array.isArray(topics) ? topics : Object.keys(topics);
    const granted = list.map((topic) => ({ topic, qos: this.deny.has(topic) ? 135 : options.qos ?? 0 }));
    for (const { topic, qos } of granted) if (qos < 128) this.subscribed.add(topic);
    setImmediate(() => {
      for (const { topic, qos } of granted) {
        if (qos < 128 && topic in this.retained) this.deliver(topic, this.retained[topic], { retain: true });
      }
    });
    return granted;
  }

  unsubscribe(topic) {
    for (const t of Array.isArray(topic) ? topic : [topic]) {
      this.subscribed.delete(t);
      this.unsubscribed.push(t);
    }
  }

  async unsubscribeAsync(topic) {
    this.unsubscribe(topic);
  }

  // Mensagem chegando do broker (do app, do painel ou retida)
  deliver(topic, message, { retain = false } = {}) {
    const text = typeof message === 'string' ? message : JSON.stringify(message);
    this.emit('message', topic, Buffer.from(text), { retain });
  }

  // Mensagens publicadas num topico (JSON ja decodificado)
  sent(topic) {
    return this.published.filter((p) => p.topic === topic);
  }

  lastJson(topic) {
    const list = this.sent(topic);
    return list.length ? JSON.parse(list[list.length - 1].payload) : null;
  }
}

// Ticks de um cenario (scenarios.js) -> leituras com o gerador de sempre.
// `onReading(reading, tick)` recebe cada leitura (ex.: link.step).
export function runTicks(ticks, seed, onReading, { offset = 0 } = {}) {
  return withRandom(seeded(seed), () => {
    let n = 0;
    for (const tick of ticks) {
      const reading = generateReading({ ...tick.alvos, timestamp: isoAt(offset + n) });
      onReading(reading, tick);
      n += 1;
    }
    return n;
  });
}

// Roteiro nominal de um cenario, uma vez
export const nominalTicks = (cenario, seed = 1) => programTicks({ cenario, umaVez: true, seed });

// N segundos calmos depois (para o ultimo episodio fechar)
export function* calmTicks(n, alvos) {
  for (let t = 0; t < n; t += 1) yield { t, alvos };
}
