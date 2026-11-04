// Gabarito dos testes: simulator/logs/eventos_<data-hora>.csv (e .json), uma
// linha por evento (eventos_aleatorios) ou por ciclo (demais cenarios),
// gravada quando o trecho ativo termina. Serve para comparar com o CSV do
// historico exportado pelo site (mesmo formato: ";", virgula decimal, BOM).
// Os logs sao locais (simulator/.gitignore).

import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export const GABARITO_COLUMNS = [
  'numero', 'tipo', 'intensidade', 'inicio', 'fim', 'crise_real', 'gatilho_esperado', 'seed',
  // extras: detalhes do sorteio, para conferir e reproduzir
  'cenario', 'fator_pico', 'fator_ambiente', 'antecedencia_s', 'fisiologia_inicio', 'pausa_depois_s', 'observacao',
];

const pad = (n) => String(n).padStart(2, '0');

// ISO 8601 no horario LOCAL, com o fuso: "2026-11-04T14:03:12-03:00"
// (o CSV do site usa a hora local, entao fica facil comparar)
export function isoLocal(date) {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? '+' : '-';
  const abs = Math.abs(off);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
    + `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

// "2026-11-04_14-03-12" (nome do arquivo)
const fileStamp = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;

// Linha do gabarito (valores tipados, como no .json)
export function gabaritoEntry(ciclo, { inicio, fim, fisiologia = null, observacao = '' }) {
  const v = ciclo.variacao;
  return {
    numero: ciclo.numero,
    tipo: ciclo.tipo,
    intensidade: ciclo.intensidade,
    inicio: inicio ? isoLocal(inicio) : null,
    fim: fim ? isoLocal(fim) : null,
    crise_real: ciclo.criseReal,
    gatilho_esperado: ciclo.gatilhoEsperado ?? 'sem_episodio',
    seed: ciclo.seed,
    cenario: ciclo.cenario,
    fator_pico: Math.round(v.pico * v.nivel * 100) / 100,
    fator_ambiente: v.ambiente,
    antecedencia_s: ciclo.roteiro.antecedencia,
    fisiologia_inicio: fisiologia ? isoLocal(fisiologia) : null,
    pausa_depois_s: ciclo.pausaDepois,
    observacao,
  };
}

function csvCell(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'boolean') return value ? 'sim' : 'não';
  if (typeof value === 'number') return Number.isInteger(value) ? String(value) : String(value).replace('.', ',');
  const s = String(value);
  return /[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export const csvHeader = () => GABARITO_COLUMNS.join(';');
export const csvRow = (entry) => GABARITO_COLUMNS.map((c) => csvCell(entry[c])).join(';');

// Cria logs/eventos_<data-hora>.csv (cabecalho ja gravado) e .json; add()
// acrescenta uma linha no CSV e regrava o JSON inteiro.
export function createGabaritoWriter(dir, meta, now = new Date()) {
  mkdirSync(dir, { recursive: true });
  // dois simuladores no mesmo segundo nao sobrescrevem um ao outro
  let base = join(dir, `eventos_${fileStamp(now)}`);
  for (let n = 2; existsSync(`${base}.csv`); n += 1) base = join(dir, `eventos_${fileStamp(now)}_${n}`);
  const csvPath = `${base}.csv`;
  const jsonPath = `${base}.json`;
  const entries = [];
  const writeJson = () => writeFileSync(jsonPath, `${JSON.stringify({ ...meta, iniciado_em: isoLocal(now), eventos: entries }, null, 2)}\n`);
  writeFileSync(csvPath, `﻿${csvHeader()}\r\n`); // BOM: o Excel abre os acentos em UTF-8
  writeJson();
  return {
    csvPath,
    jsonPath,
    add(entry) {
      entries.push(entry);
      appendFileSync(csvPath, `${csvRow(entry)}\r\n`);
      writeJson();
    },
  };
}
