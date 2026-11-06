// Tema do painel: leitura e gravacao no localStorage (com falhas), atributo
// data-theme e os dois blocos escuros de index.css iguais (node --test).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CHAVE_TEMA, TEMAS, aplicarTema, lerTema, salvarTema } from './theme.js';

function armazenamento() {
  const dados = new Map();
  return {
    dados,
    getItem: (k) => (dados.has(k) ? dados.get(k) : null),
    setItem: (k, v) => dados.set(k, String(v)),
    removeItem: (k) => dados.delete(k),
  };
}

const quebrado = {
  getItem() { throw new Error('bloqueado'); },
  setItem() { throw new Error('cota cheia'); },
  removeItem() { throw new Error('bloqueado'); },
};

function raiz() {
  const atributos = new Map();
  return {
    atributos,
    setAttribute: (k, v) => atributos.set(k, v),
    removeAttribute: (k) => atributos.delete(k),
  };
}

test('sem nada salvo, o tema e "sistema"', () => {
  assert.equal(lerTema(armazenamento()), 'sistema');
  assert.equal(lerTema(null), 'sistema');
});

test('salva e le claro e escuro; "sistema" apaga a chave', () => {
  const a = armazenamento();
  assert.equal(salvarTema('escuro', a), true);
  assert.equal(a.dados.get(CHAVE_TEMA), 'escuro');
  assert.equal(lerTema(a), 'escuro');
  salvarTema('claro', a);
  assert.equal(lerTema(a), 'claro');
  salvarTema('sistema', a);
  assert.equal(a.dados.has(CHAVE_TEMA), false);
  assert.equal(lerTema(a), 'sistema');
});

test('valor estranho ou localStorage com erro nao quebram a pagina', () => {
  const a = armazenamento();
  a.setItem(CHAVE_TEMA, 'roxo');
  assert.equal(lerTema(a), 'sistema');
  assert.equal(salvarTema('roxo', a), false);
  assert.equal(lerTema(quebrado), 'sistema');
  assert.equal(salvarTema('escuro', quebrado), false);
});

test('data-theme no <html>: claro = light, escuro = dark, sistema = sem atributo', () => {
  const r = raiz();
  aplicarTema('escuro', r);
  assert.equal(r.atributos.get('data-theme'), 'dark');
  aplicarTema('claro', r);
  assert.equal(r.atributos.get('data-theme'), 'light');
  aplicarTema('sistema', r);
  assert.equal(r.atributos.has('data-theme'), false);
  assert.doesNotThrow(() => aplicarTema('escuro', undefined));
  assert.deepEqual(TEMAS, ['sistema', 'claro', 'escuro']);
});

test('index.css: o escuro do sistema e o escuro escolhido usam os mesmos tokens', () => {
  const css = readFileSync(new URL('./index.css', import.meta.url), 'utf8');
  const bloco = (inicio) => {
    const i = css.indexOf(inicio);
    assert.notEqual(i, -1, inicio);
    const corpo = css.slice(css.indexOf('{', i) + 1, css.indexOf('}', i));
    return corpo.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('/*')).join('\n');
  };
  const sistema = bloco(':root:not([data-theme="light"])');
  const escolhido = bloco(':root[data-theme="dark"]');
  assert.equal(escolhido, sistema);
  assert.match(sistema, /--text-primary: #f0efec/, 'texto sem branco puro');
  assert.doesNotMatch(sistema, /#000000|#000;|#fff;|#ffffff/i, 'sem preto nem branco puros no escuro');
});
