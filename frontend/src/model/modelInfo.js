import forest from './forest.json' with { type: 'json' };

// Origem do modelo em uso, para o rodape do dashboard. O campo "meta" e
// gravado por model/train.py (oficial) e model/train_incremental.py
// (experimental); forest.json antigos nao tem esse campo.
const meta = forest.meta ?? null;

export const MODEL_INFO = {
  arvores: forest.trees.length,
  script: meta?.script ?? null,
  dataset: meta?.dataset ?? null,
  treinadoEm: meta?.treinado_em ?? null,
};

export function describeModel(info = MODEL_INFO) {
  let text = `Modelo: ${info.arvores} árvores`;
  const date = info.treinadoEm ? new Date(info.treinadoEm) : null;
  if (date && !Number.isNaN(date.getTime())) text += `, treinado em ${date.toLocaleDateString('pt-BR')}`;
  if (info.script) text += ` (${info.script})`;
  return text;
}
