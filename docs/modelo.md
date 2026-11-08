# Modelo preditivo

Como rodar o treino: seção "Treinando o modelo" do [README](../README.md).

## Arquivos

- `model/features.py` — engenharia de features (usada pelo treino; a
  pulseira calcula as mesmas em `frontend/src/model/predict.js`)
- `model/train.py` — treina e valida (GroupKFold por criança) e exporta
  `frontend/src/model/forest.json`
- `model/gerar_dataset_v4.py` — gerador do dataset sintético v4 (semente
  fixa)
- `data/raw/dataset_pulseira_TEA_estresse_v4.xlsx` — o dataset do treino

## Modelo em produção

O `frontend/src/model/forest.json` (o que a pulseira usa) é gerado pelo
`model/train.py`: 60 árvores, profundidade máxima 6, dataset v4, com
validação GroupKFold por criança. As métricas desta página vêm dele.
Conferido em 02/11/2026: rodar `python model/train.py` gera um
`forest.json` com as mesmas 60 árvores que estão versionadas.

O `forest.json` tem um campo `meta` (script de origem, dataset, número de
árvores, data do treino). O `predict.js` ignora esse campo; a pulseira o
mostra no início, e o rodapé do painel do site também ("Modelo: 60 árvores,
treinado em … (model/train.py)").

> Histórico: um treino incremental experimental (`train_incremental.py`,
> com o estado em `model/state/`) e os datasets e scripts de análise
> anteriores (v1, v2, v3 e `model/eda/`) saíram do projeto na limpeza de
> 11/2026. Continuam no histórico do git, por exemplo
> `git show 9f7f8aa:data/raw/dataset_pulseira_TEA_estresse_v3.xlsx > v3.xlsx`.

## Treino (`train.py`)

```bash
pip install pandas scikit-learn openpyxl numpy
python model/train.py
```

Isso reescreve `frontend/src/model/forest.json`, consumido pela pulseira
(`frontend/src/model/predict.js`, chamado por `simulator/borda.js`) — sem
precisar de backend, a inferência roda na própria pulseira (processamento na
borda; num ESP32 real, o modelo teria de ser convertido para C, o que fica
como trabalho futuro). O site não carrega as árvores: lê só o campo `meta`
para o rodapé.

## Decisões de design

**Alvo binário (crise / sem crise), não os 4 rótulos do dataset.**
Testamos multiclasse (nenhum/leve/moderado/alto) primeiro — a fronteira
entre "leve" e "nenhum" é muito ruidosa (F1 chegou a 0.12 em alguns folds).
O binário com probabilidade de saída é uma base mais confiável para um
alerta que vai para um cuidador real; a pulseira converte a probabilidade
em 3 faixas de risco (baixo / atenção / possível crise).

**Feature de "batimento sobe de repente" (jerk) — histórico.**
No dataset v2 (herdado do dataset original), essa feature tinha importância
~0: todo episódio subia de forma igualmente gradual, sem exemplo de "salto
súbito" nos dados. O dataset v3 (gerador histórico, ver "Modelo em produção")
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
classificar a média de uma janela de 30s já elevada.

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

| Dataset | Features | AUC médio | Observação |
|---|---|---|---|
| v2 (histórico) | 12 | 0.985 | mais fácil — EDA sozinha quase resolve |
| v3 (histórico) | 12 | 0.952 | mais difícil de propósito — sobreposição real entre exercício intenso e estresse leve |
| **v4 (atual)** | **24** | **0.960** | mesma dificuldade do v3 + 4 grupos de sinais novos (ver abaixo) |

As linhas v2 e v3 são registro histórico: esses datasets não têm as colunas
de HRV, acelerômetro e ambiente que o `features.py` atual exige (os arquivos
e o código da época estão no histórico do git).

Recall 0.85-0.96, precisão varia bastante por criança (0.27-0.93 entre
folds, v4; valores conferidos no retreino de 02/11/2026) — o modelo erra
mais pro lado de alertar demais do que deixar
passar uma crise real, que é a troca certa pra esse tipo de sistema, mas
é uma limitação real a citar no TCC (a fronteira "leve vs. atividade
física intensa" continua sendo a mais difícil de acertar com precisão).

## v4 — features novas (HRV, acelerômetro, ambiente, tempo elevado)

Gerador: `model/gerar_dataset_v4.py`. Mantém a mesma dinâmica de
onset súbito/gradual do v3, e adiciona:

- **HRV** (`hrv_rmssd_ms`) — cai um pouco com atividade física (acoplada ao
  offset de atividade) e cai MUITO MAIS durante um episódio de estresse
  real (retirada vagal costuma ser mais rápida e mais forte que o simples
  aumento de BPM). Calibrado pra ficar sempre abaixo do nível de exercício
  puro em todas as severidades (nenhum 53,5 > leve 42,2 > moderado 40,7 >
  alto 32,6ms).
- **Acelerômetro + regularidade do movimento** (`acelerometro_magnitude_g`,
  `movimento_regularidade`, 0-1) — a regularidade fica alta especificamente
  quando o episódio de estresse vem com agitação motora visível
  (estereotipia: balançar o corpo, bater as mãos), um padrão fisicamente
  diferente de "correr" (movimento intenso, mas IRREGULAR). Como a
  amostragem é 1Hz, não reconstruímos a forma de onda de alta frequência
  (1-5Hz típico de estereotipia) — simulamos direto o índice resumido,
  como um MPU6050 real reportaria após análise a bordo em alta frequência.
- **Sensores ambientais** (`luminosidade_lux`, `ruido_db`) — em ~40% dos
  episódios há um pico ambiental coincidente (gatilho plausível); nos
  outros 60% não há correlato externo (crise sem causa óbvia, tão real
  quanto a outra situação).
- **Tempo acumulado em estado elevado** (`bpm_tempo_elevado`) — streak de
  segundos consecutivos, dentro da janela de 30s, em que o BPM ficou acima
  da própria tendência da janela + margem. Não exige histórico extra além
  do que as outras features já usam (dropna continua em 30 amostras).

### Ablação controlada (mesmo dataset v4, só muda o conjunto de features)

| Conjunto de features | AUC | Acurácia | F1 | Recall | Precisão |
|---|---|---|---|---|---|
| 12 antigas (bpm/eda/gyro + idade) | 0.939 | 85.4% | 0.540 | 83.9% | 45.4% |
| **24 completas (v4)** | **0.960** | **91.1%** | **0.669** | **88.7%** | **58.2%** |

Ganho real e isolado das features novas (mesmo split, mesmas crianças de
teste): **+12,8 pontos de precisão**, **+12,9% de F1**. Não é só ruído.

### Importância das features (dataset v4, floresta final)

As duas maiores surpresas: `regularidade_mean_long` ficou em **2º lugar
geral** (15,7%) e a soma das 3 features de HRV chegou a **19,8%** — maior
que giroscópio inteiro. `bpm_jerk`/`bpm_slope_short` continuam com
importância ~0, pelo mesmo motivo documentado acima (onset é uma fatia
pequena do total de segundos).

| Feature | Importância |
|---|---|
| eda_mean_long | 20.4% |
| **regularidade_mean_long** | **15.7%** |
| eda | 13.5% |
| **hrv_mean_long** | **9.9%** |
| eda_slope_long | 9.6% |
| **hrv** | **6.4%** |
| bpm_mean_long | 4.9% |
| **hrv_slope_long** | **3.5%** |
| gyro_mean_long | 3.2% |
| bpm_slope_long | 3.1% |
| bpm | 2.5% |
| accel_mean_long | 1.4% |
| ruido_slope_long | 1.0% |
| accel_mag | 0.9% |
| gyro_slope_long / gyro_mag | 0.8% cada |
| luz_mean_long / idade | 0.6% cada |
| ruido_mean_long | 0.5% |
| bpm_tempo_elevado | 0.3% |
| luz / ruido | 0.2% cada |
| bpm_jerk / bpm_slope_short | ~0% |

### Uma nota sobre "transição abrupta" no simulador manual

Se você mudar os sliders de um salto só (em vez de gradualmente), o modelo
pode marcar risco alto momentaneamente mesmo num cenário de exercício —
isso NÃO é um bug. A janela de 30s ainda contém a mistura entre o estado
anterior e o novo, e uma mudança rápida em qualquer sinal é ambígua até
que se sustente por tempo suficiente (o mesmo aconteceria com um sensor
real). Pra testar "isso é exercício sustentado, não crise", suba os
valores em degraus graduais e espere ~30s+ depois da última mudança antes
de olhar a previsão.
