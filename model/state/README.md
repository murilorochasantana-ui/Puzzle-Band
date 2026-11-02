# model/state — estado do treino incremental (experimental)

Esta pasta é usada só pelo `model/train_incremental.py`:

- `forest_state.pkl` — a floresta acumulada (objeto do scikit-learn), necessária
  para continuar treinando em rodadas futuras. **Não apague** se quiser
  continuar os experimentos.
- `training_history.json` — uma entrada por rodada (dataset, amostras, árvores).

**Atenção: esta floresta NÃO é o modelo do dashboard.** Hoje ela tem 80
árvores (1 rodada com o dataset v4, em 19/09/2026 02:42 UTC). O
`frontend/src/model/forest.json` oficial tem 60 árvores e vem do
`model/train.py`, a fonte oficial, com validação GroupKFold. O
`train.py` rodou depois da rodada incremental e sobrescreveu o
`forest.json`; esta pasta ficou com a versão de 80 árvores.

Rodar o `train_incremental.py` de novo **substitui** o `forest.json` pelo
modelo experimental. O campo `meta` do `forest.json` e o rodapé do dashboard
mostram qual script gerou o modelo em uso. Para voltar ao oficial:

```bash
python model/train.py
```

Detalhes: seção "Qual modelo está em produção" do `model/README.md`.
