// Tema do painel escolhido pelo usuario: "sistema" (padrao), "claro" ou
// "escuro". Fica salvo no localStorage deste navegador e vira o atributo
// data-theme do <html>, que troca os tokens de src/index.css. O index.html
// repete a leitura num script curto, antes do React, para a pagina nao abrir
// no tema errado.

export const TEMAS = ['sistema', 'claro', 'escuro'];
export const CHAVE_TEMA = 'puzzleband:tema';

const ATRIBUTO = { claro: 'light', escuro: 'dark' };

function armazenamentoPadrao() {
  try {
    return globalThis.localStorage ?? null;
  } catch {
    return null; // acesso bloqueado (ex.: cookies desligados)
  }
}

/** Tema salvo; sem nada salvo (ou sem localStorage), "sistema". */
export function lerTema(armazenamento = armazenamentoPadrao()) {
  try {
    const valor = armazenamento?.getItem(CHAVE_TEMA);
    return TEMAS.includes(valor) ? valor : 'sistema';
  } catch {
    return 'sistema';
  }
}

/** Salva o tema ("sistema" apaga a chave). Devolve false se nao deu. */
export function salvarTema(tema, armazenamento = armazenamentoPadrao()) {
  if (!TEMAS.includes(tema) || !armazenamento) return false;
  try {
    if (tema === 'sistema') armazenamento.removeItem(CHAVE_TEMA);
    else armazenamento.setItem(CHAVE_TEMA, tema);
    return true;
  } catch {
    return false; // cota cheia ou modo privado
  }
}

/** Aplica o tema no <html>: "sistema" tira o data-theme. */
export function aplicarTema(tema, raiz = globalThis.document?.documentElement) {
  if (!raiz) return;
  const atributo = ATRIBUTO[tema];
  if (atributo) raiz.setAttribute('data-theme', atributo);
  else raiz.removeAttribute('data-theme');
}
