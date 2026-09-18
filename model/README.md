# Modelo preditivo — Puzzle Band

## Arquivos

- `features.py` — engenharia de features (compartilhado entre treino e avaliação)
- `train.py` — treina o classificador e exporta `frontend/src/model/forest.json`
- `eda/` — scripts de análise exploratória usados para validar o dataset (histórico)

## Rodar o treino

```bash
pip install pandas scikit-learn openpyxl numpy
python3 model/train.py
```

Isso reescreve `frontend/src/model/forest.json`, consumido pelo dashboard
(`frontend/src/model/predict.js`) — sem precisar de backend, a inferência
roda inteira no navegador.

## Decisões de design

**Alvo binário (crise / sem crise), não os 4 rótulos do dataset.**
Testamos multiclasse (nenhum/leve/moderado/alto) primeiro — a fronteira
entre "leve" e "nenhum" é muito ruidosa (F1 chegou a 0.12 em alguns folds).
O binário com probabilidade de saída é uma base mais confiável para um
alerta que vai para um cuidador real; o dashboard converte a probabilidade
em 3 faixas de risco (baixo / atenção / possível crise).

**Feature de "batimento sobe de repente" (jerk) — histórico.**
No dataset v2 (herdado do dataset original), essa feature tinha importância
~0: todo episódio subia de forma igualmente gradual, sem exemplo de "salto
súbito" nos dados. O dataset v3 (`model/eda/08_generate_dataset_v3.py`)
resolve isso: gera episódios com onset súbito (~70%, 5-15s) e gradual
(~30%, 40-90s), e a subida do estresse é sempre um INCREMENTO aditivo sobre
o que já estava acontecendo (nunca um alvo absoluto — isso é um bug real
que corrigimos: antes, um episódio "leve" durante brincadeira_ativa podia
gerar uma *queda* de BPM, porque o alvo absoluto do nível "leve" era mais
baixo que o patamar já elevado da atividade física).

Verificamos diretamente: no instante do início de um episódio (primeiros
~8s), `bpm_jerk` sobe pra média 0,94 contra 0,004 no fundo (~230x maior) —
o sinal existe e é real. Mas a importância AGREGADA da feature no modelo
continua baixa (~0.001): isso é esperado, não é falha. Gini importance
pondera pelo volume total de amostras onde a feature ajuda a decidir, e o
"onset" é só ~0.5% do total de segundos rotulados como estresse (o resto é
platô/recuperação, onde EDA/giroscópio já resolvem sozinhos). Ou seja: a
dinâmica de subida é uma pista real, disponível e correta, só que
estatisticamente pequena diante do volume de dados — mais relevante pra um
sistema de alerta PRECOCE (pegar a subida assim que ela começa) do que pra
classificar a média de uma janela de 30s already-elevada.

O que domina a decisão do modelo (e resolve o problema principal — não
confundir exercício com estresse) é outra pista, mais robusta
estatisticamente: no dataset v3, deixamos de propósito a EDA de
`brincadeira_ativa` alta o bastante pra se sobrepor a um episódio "leve"
real (atividade chega a ~6,7 µS em média; estresse "leve" fica em ~5,8) —
ou seja, **EDA sozinha também não resolve mais**, igual ao BPM. O que
resolve é a combinação: `eda_mean_long` + `gyro_mean_long` juntos —
exercício eleva BPM/EDA E giroscópio JUNTOS; estresse real eleva BPM/EDA
mesmo com a criança parada (giroscópio baixo, ~50% dos episódios do
gerador ficam "congelados" no nível de fundo).

## Validação (GroupKFold por criança)

| Dataset | AUC médio | Observação |
|---|---|---|
| v2 (sem dinâmica de onset, sem sobreposição deliberada) | 0.985 | mais fácil — EDA sozinha quase resolve |
| **v3 (atual)** | **0.952** | mais difícil de propósito — sobreposição real entre exercício intenso e estresse leve, obrigando o modelo a combinar sinais |

Recall ~0.87-0.96, precisão varia bastante por criança (0.23-0.92 entre
folds) — o modelo erra mais pro lado de alertar demais do que deixar
passar uma crise real, que é a troca certa pra esse tipo de sistema, mas
é uma limitação real a citar no TCC (a fronteira "leve vs. atividade
física intensa" continua sendo a mais difícil de acertar com precisão).
