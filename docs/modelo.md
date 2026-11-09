# Modelo preditivo

Como rodar o treino: [Treino](#treino-trainpy), abaixo.

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
Conferido em 02/11/2026 e de novo em 08/11/2026 (scikit-learn 1.9.1):
rodar `python model/train.py` gera as mesmas 60 árvores que estão
versionadas.

Desde 08/11/2026 o arquivo é **compactado**: limiares e probabilidades com
4 casas decimais e JSON sem espaços (366 → 273 KB). O `train.py` já grava
assim. Por episódio, isso muda 1 de 1000 eventos do `verificar.js` (ver
"Versão simplificada").

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

Rode na raiz do projeto. Para trocar de dataset, edite a constante `DATASET`
no topo de `model/train.py`. Depois de treinar, reinicie a pulseira (Ctrl+C
e rode de novo) para ela carregar o modelo novo.

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

## Versão simplificada (comparação de 11/2026)

Pergunta: dá para ter um modelo mais simples (menos features, menos árvores,
sem luz e ruído nas **entradas**) ou melhor (features com memória) sem
perder nas métricas por episódio? A regra de gatilho (`trigger.js`) não muda
em nenhuma versão: luz e ruído continuam nas leituras, no MQTT, nos gráficos
e na regra; a pergunta é só se o **modelo** precisa deles.

**Decisão (08/11/2026): manter o modelo atual, só compactado.** Nenhuma
versão foi igual ou melhor por episódio sem perder crises (detalhes abaixo).
Os resultados negativos estão registrados de propósito.

### Hipótese da subida súbita (features com memória)

> **Hipótese de projeto, não fato fisiológico validado.** A ideia é que, na
> crise, o batimento sobe de repente (em 5 a 15 s) e sem movimento que
> explique; no exercício, sobe aos poucos e junto com o movimento. Ela está
> **implementada nos dados sintéticos**: o gerador do v4
> (`model/gerar_dataset_v4.py`) faz ~70% das crises com subida súbita
> (5–15 s) e ~30% gradual (40–90 s), e o exercício com transições de 30–50 s;
> desde 11/2026 os cenários do simulador seguem a mesma proporção. Por isso,
> um ganho aqui mostra que o modelo **consegue usar** essa pista se ela
> existir, não que ela exista em crianças reais. **Precisa ser validada com
> dados reais**: no início de um exercício (uma corrida que começa de
> repente) o BPM também sobe rápido nos primeiros segundos, e uma crise pode
> começar devagar.

As três features antigas dessa ideia (`bpm_jerk`, `bpm_slope_short`,
`bpm_tempo_elevado`) têm importância ~0 porque a subida súbita só dura os
primeiros 5–15 s da crise e o modelo decide segundo a segundo, com janelas
de 30 s. As features novas guardam a pista por **90 s** (mesmas contas em
`model/features.py`, `_memory_features`, e em `frontend/src/model/predict.js`,
`memoryFeatures`; conferido em 26.910 segundos de 3 crianças do v4:
diferença zero entre Python e JS):

| Feature | O que mede |
|---|---|
| `bpm_jerk_max_90` | o maior `bpm_jerk` dos últimos 90 s |
| `bpm_excesso_mov` | subida do BPM não explicada pelo movimento: (média de 5 s do BPM − menor valor dela em 90 s) − 0,34 × (o mesmo para o giroscópio). 0,34 bpm/dps é a relação do exercício no v4 (+38 bpm para +112 dps), fixa para não vazar dados da validação |
| `bpm_tempo_subida` | segundos que a média de 5 s do BPM levou de 20% a 80% da subida até o pico mais recente dos 90 s (90 se a subida for menor que 10 bpm) |

Com o modelo atual (sem essas features), nada muda: o `predict.js` só as
calcula se o `forest.json` as usar, e o `classifyAt` passa até 120 leituras
(antes, 31) para o cálculo olhar 90 s para trás.

### Como foi comparado

- **Por segundo:** `python model/comparar_modelos.py --saida <pasta>`, com o
  mesmo GroupKFold por criança (4 folds) do `train.py` no dataset v4 e
  limiar 0,5 para precisão, recall e F1 (todas as previsões fora do fold
  juntas; por isso a precisão aqui é menor que a da ablação acima, que era a
  média dos folds). A linha "atual" reproduz o `forest.json` de produção (60
  árvores idênticas, conferido com scikit-learn 1.9.1).
- **Por episódio:** `node model/comparar_episodios.mjs <pasta>/*.compacto.json --cenarios-antigos <scenarios.js anterior>`
  roda o `simulator/verificar.js` (seeds fixas: laço com 20 sementes × 3
  ciclos por cenário e 1000 eventos aleatórios, seeds 1–50) com cada versão
  compactada (limiares e probabilidades com 4 casas, JSON sem espaços), nos
  cenários com subida súbita/gradual e nos antigos (subida de 30 s). Mede
  também o tempo de inferência por leitura (`classifyAt`).
- Versões: **a** atual (24 features, 60 árvores, profundidade 6); **b** sem
  as features de importância < 1% (`bpm_jerk`, `bpm_slope_short`,
  `bpm_tempo_elevado`, `idade`, `accel_mag`, `gyro_mag`,
  `gyro_slope_long`); **c** b sem luz e ruído (`luz`, `luz_mean_long`,
  `ruido`, `ruido_mean_long`, `ruido_slope_long`); **d** b e c com 30 e 40
  árvores; e as mesmas com as 3 features de memória.

### Por segundo (dataset v4)

| Versão | Features | Árvores | AUC | Precisão | Recall | F1 | Precisão por criança (mín · mediana · máx) | forest.json compacto |
|---|---|---|---|---|---|---|---|---|
| atual (24 features) | 24 | 60 | 0.960 | 0.470 | 0.888 | 0.614 | 0.13 · 0.92 · 0.96 | 267 KB |
| b) sem importância < 1% | 17 | 60 | 0.959 | 0.419 | 0.878 | 0.567 | 0.08 · 0.91 · 0.96 | 275 KB |
| c) b sem ambiente | 12 | 60 | 0.959 | 0.423 | 0.883 | 0.572 | 0.08 · 0.89 · 0.96 | 280 KB |
| b com 30 árvores | 17 | 30 | 0.958 | 0.408 | 0.880 | 0.557 | 0.08 · 0.88 · 0.97 | 140 KB |
| b com 40 árvores | 17 | 40 | 0.959 | 0.416 | 0.881 | 0.565 | 0.08 · 0.89 · 0.96 | 185 KB |
| c com 30 árvores | 12 | 30 | 0.954 | 0.417 | 0.882 | 0.567 | 0.08 · 0.89 · 0.96 | 140 KB |
| c com 40 árvores | 12 | 40 | 0.957 | 0.423 | 0.881 | 0.572 | 0.08 · 0.91 · 0.96 | 186 KB |
| a + memória | 27 | 60 | 0.965 | 0.680 | 0.885 | 0.769 | 0.34 · 0.84 · 0.96 | 277 KB |
| b + memória | 20 | 60 | 0.966 | 0.721 | 0.883 | 0.794 | 0.34 · 0.88 · 0.95 | 274 KB |
| c + memória | 15 | 60 | 0.966 | 0.684 | 0.888 | 0.773 | 0.34 · 0.84 · 0.96 | 282 KB |
| c + memória, 30 árvores | 15 | 30 | 0.966 | 0.701 | 0.889 | 0.784 | 0.34 · 0.84 · 0.96 | 141 KB |
| c + memória, 40 árvores | 15 | 40 | 0.966 | 0.684 | 0.887 | 0.772 | 0.34 · 0.84 · 0.96 | 188 KB |
| b + memória, 30 árvores | 20 | 30 | 0.966 | 0.716 | 0.883 | 0.791 | 0.34 · 0.84 · 0.95 | 137 KB |
| b + memória, 40 árvores | 20 | 40 | 0.966 | 0.716 | 0.884 | 0.791 | 0.34 · 0.85 · 0.95 | 184 KB |
| 12 antigas (ablação) | 12 | 60 | 0.939 | 0.337 | 0.840 | 0.481 | 0.08 · 0.84 · 0.97 | 289 KB |

### Por episódio (simulador, cenários com subida súbita/gradual)

| Versão | Crises detectadas (eventos) | Crises certas no laço | Exercício no laço: sem alerta · só atenção · possível crise (de 60) | Exercício (eventos) com alarme | barulho_sem_crise sem alerta (de 60) | Ambiente sem crise (eventos) com alarme | calmo sem alerta (de 60) | Episódios nas pausas calmas (eventos) | Tempo até o alerta | KB |
|---|---|---|---|---|---|---|---|---|---|---|
| atual (antes de compactar) | 852/852 | 420/420 | 0 · 37 · 23 | 96/96 | 40 | 21/52 | 60 | 0 | 6,4 s | 358 |
| **atual, compactado (em produção)** | 852/852 | 420/420 | 0 · 37 · 23 | 96/96 | 40 | 22/52 | 60 | 0 | 6,4 s | 267 |
| b) sem importância < 1% | 831/852 | 400/420 | 0 · 44 · 16 | 96/96 | 18 | 36/52 | 34 | 182 | 6,1 s | 275 |
| c) b sem ambiente | 806/852 | 392/420 | 0 · 35 · 25 | 96/96 | 24 | 30/52 | 18 | 324 | 6,6 s | 280 |
| b, 30 árvores | 793/852 | 380/420 | 0 · 42 · 18 | 96/96 | 13 | 41/52 | 17 | 410 | 6,2 s | 140 |
| b, 40 árvores | 818/852 | 396/420 | 0 · 47 · 13 | 96/96 | 17 | 36/52 | 23 | 259 | 6,4 s | 185 |
| c, 30 árvores | 810/852 | 396/420 | 0 · 30 · 30 | 96/96 | 25 | 29/52 | 21 | 277 | 6,8 s | 140 |
| c, 40 árvores | 807/852 | 388/420 | 0 · 37 · 23 | 96/96 | 24 | 29/52 | 20 | 292 | 6,7 s | 186 |
| a + memória | 837/852 | 410/420 | 0 · 49 · 11 | 96/96 | 37 | 22/52 | 41 | 125 | 6,7 s | 277 |
| b + memória | 848/852 | 412/420 | 0 · 38 · 22 | 96/96 | 56 | 6/52 | 50 | 37 | 7,5 s | 274 |
| c + memória | 820/852 | 404/420 | 0 · 29 · 31 | 96/96 | 32 | 28/52 | 29 | 244 | 7,1 s | 282 |
| c + memória, 30 árvores | 841/852 | 412/420 | 0 · 31 · 29 | 96/96 | 50 | 10/52 | 47 | 85 | 7 s | 141 |
| c + memória, 40 árvores | 822/852 | 407/420 | 0 · 31 · 29 | 96/96 | 35 | 23/52 | 31 | 220 | 6,9 s | 188 |
| b + memória, 30 árvores | 839/852 | 411/420 | 0 · 42 · 18 | 96/96 | 44 | 12/52 | 40 | 142 | 7,6 s | 137 |
| b + memória, 40 árvores | 843/852 | 411/420 | 0 · 41 · 19 | 96/96 | 47 | 10/52 | 43 | 117 | 7,5 s | 184 |
| 12 antigas (ablação) | 852/852 | 420/420 | 0 · 44 · 16 | 96/96 | 60 | 0/52 | 60 | 0 | 6,9 s | 289 |

"Episódios nas pausas calmas" são episódios abertos sem evento nenhum (a
criança calma entre um evento e outro): também são alarmes falsos. Tempo de
inferência por leitura (`classifyAt`): ~0,01 ms nas versões sem memória e
~0,04 ms nas com memória, irrisório nos dois casos. Nos cenários antigos
(subida de 30 s) as conclusões são as mesmas.

### Limiares mais baixos para "b + memória"

Teste para ver se limiares de alerta mais baixos recuperam as crises que
"b + memória" perde (o limiar fica no `predict.js`, `riskTierFromProbability`;
`node model/comparar_episodios.mjs <forest.json> --limiares 0.35,0.65`):

| b + memória, limiares (atenção / possível crise) | Precisão · recall por segundo no limiar de atenção | Crises detectadas (eventos) | Crises certas no laço | barulho_sem_crise sem alerta (de 60) | calmo sem alerta (de 60) | Episódios nas pausas calmas (eventos) | Exercício no laço: sem alerta · só atenção · possível crise |
|---|---|---|---|---|---|---|---|
| 0,40 / 0,70 (padrão) | 0,590 · 0,902 | 848/852 | 412/420 | 56 | 50 | 37 | 0 · 38 · 22 |
| 0,35 / 0,65 | 0,476 · 0,913 | 840/852 | 411/420 | 45 | 42 | 125 | 0 · 22 · 38 |
| 0,30 / 0,60 | 0,361 · 0,925 | 824/852 | 405/420 | 34 | 30 | 204 | 0 · 4 · 56 |
| 0,35 / 0,70 | 0,476 · 0,913 | 840/852 | 411/420 | 45 | 42 | 125 | 0 · 38 · 22 |
| 0,25 / 0,55 | 0,268 · 0,942 | 797/852 | 402/420 | 22 | 18 | 330 | 0 · 0 · 60 |
| *atual, para comparar: 0,40 / 0,70* | *0,330 · 0,911* | *852/852* | *420/420* | *40* | *60* | *0* | *0 · 37 · 23* |

**Não recupera, piora.** Baixar o limiar faz o modelo abrir mais episódios
nas pausas calmas (de 37 para 125 e para 330), e um episódio que ainda está
aberto quando a crise seguinte começa "engole" essa crise: ela não gera
episódio próprio e conta como não detectada. Por isso as crises detectadas
**caem** (848 → 840 → 797) em vez de subir, e o barulho sem crise e o calmo
também pioram. A precisão por segundo no limiar de atenção continua maior
que a do atual, mas isso não aparece por episódio.

### O que os números dizem

- **A hipótese da subida súbita ajuda por segundo, mas não resolve o
  exercício.** Com as features de memória, a precisão por segundo sobe de
  0,47 para 0,68–0,72 (F1 de 0,61 para 0,77–0,79; a pior criança, de 0,13
  para 0,34), com o mesmo recall (~0,88), e duas delas viram as mais
  importantes do modelo (`bpm_excesso_mov` 15–19%, `bpm_tempo_subida`
  9–13%). Mas, por episódio, **todas** as versões continuam alarmando nos 96
  de 96 exercícios dos eventos aleatórios e nos 60 de 60 ciclos de
  exercício. O motivo, visto no diagnóstico: o pico de probabilidade vem no
  **começo** do exercício ("começando a correr"), quando o BPM ainda está
  subindo e o trecho já subido parece súbito (`bpm_tempo_subida` = 13 s), que
  é exatamente a ressalva da hipótese. O que muda é a proporção entre "só
  atenção" e "possível crise".
- **Só o modelo atual (e as "12 antigas") não alarmam na calma.** Todas as
  outras versões abrem episódios no cenário `calmo` e nas pausas calmas dos
  eventos aleatórios; o atual tem 60/60 e 0.
- **b + memória** é a melhor das novas no barulho sem crise (56 de 60 ciclos
  sem alerta; atual: 40) e nos eventos de ambiente (6 de 52 com alarme;
  atual: 22), mas perde 4 de 852 crises nos eventos e 8 de 420 no laço,
  alarma em 10 de 60 ciclos do `calmo`, abre 37 episódios nas pausas e
  alerta ~1 s mais tarde. Com limiares mais baixos fica pior (acima).
- **Simplificar piora (resultado negativo).** Tirar as features de
  importância < 1% (b) ou também luz e ruído (c) perde de 21 a 46 das 852
  crises, **aumenta** os alarmes do barulho sem crise (18 a 25 de 60 ciclos
  sem alerta, contra 40) e passa a alarmar na calma. Importância baixa (Gini)
  não quer dizer feature inútil: luz e ruído ajudam o modelo a **não**
  confundir ambiente barulhento com crise. Menos árvores (30 ou 40) piora
  mais.
- **Compactar o atual** (4 casas, sem espaços) reduz o arquivo de 358 para
  267 KB e muda 1 de 1000 eventos (um alarme a mais num ambiente sem crise).
  **Aplicado em 08/11/2026.**
- **As 12 antigas** (sem HRV, regularidade, acelerômetro e ambiente) vão
  muito bem nos cenários do simulador (852/852 crises, nenhum alarme na calma
  ou no barulho), mas são as piores por segundo no dataset (precisão 0,34,
  recall 0,84, AUC 0,939): os cenários do simulador são mais "limpos" que o
  dataset, e por isso as duas medidas precisam ser lidas juntas.

### Conclusão (para Resultados e Limitações do TCC)

**Resultado negativo da hipótese da subida súbita.** A memória da subida
súbita do batimento (maior salto dos últimos 90 s, subida não explicada pelo
movimento e tempo de subida) **melhora a precisão segundo a segundo** no
dataset sintético (de 0,47 para até 0,72, com o mesmo recall), mas **não
reduz os alarmes falsos do exercício**: em todas as versões, os 96
exercícios dos eventos aleatórios continuam gerando alerta. O motivo é que
o **início do exercício também tem subida rápida** do batimento, e é nele
que o modelo alerta. Além disso, as versões com memória perdem algumas
crises e passam a alertar em momentos calmos. Por isso o modelo atual foi
mantido (só compactado). Distinguir exercício de crise continua sendo a
principal limitação do sistema; a hipótese, implementada só nos dados
sintéticos, precisa de dados reais para ser confirmada ou descartada, e
outras pistas (contexto da atividade, confirmação do cuidador) tendem a ser
necessárias.

O que fica no código: o modelo atual compactado; as features de memória em
`features.py` e `predict.js`, prontas para testar com dados reais (só são
calculadas se um `forest.json` as pedir; com o atual, o `verificar.js` e os
testes não mudam); os dois scripts de comparação; e os cenários com subida
súbita/gradual.
