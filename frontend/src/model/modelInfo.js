// Origem do modelo em uso, para o terminal da pulseira e o rodape do painel.
// O campo "meta" do forest.json e gravado por model/train.py; forest.json
// antigos nao tem esse campo. Sem importar o forest.json aqui: o painel le so o "meta" (as arvores
// ficam fora do bundle do site, que nao roda o modelo) e a pulseira passa o
// numero de arvores que carregou.

export function modelInfoFrom(meta, arvores = meta?.n_arvores ?? null) {
  return {
    arvores,
    script: meta?.script ?? null,
    dataset: meta?.dataset ?? null,
    treinadoEm: meta?.treinado_em ?? null,
  };
}

export function describeModel(info) {
  let text = `Modelo: ${info.arvores ?? '?'} árvores`;
  const date = info.treinadoEm ? new Date(info.treinadoEm) : null;
  if (date && !Number.isNaN(date.getTime())) text += `, treinado em ${date.toLocaleDateString('pt-BR')}`;
  if (info.script) text += ` (${info.script})`;
  return text;
}
