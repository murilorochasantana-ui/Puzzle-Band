# Indicação de gatilho provável

Código: `frontend/src/model/trigger.js` (funções puras, sem React).
Testes: `frontend/src/model/trigger.test.js` e `frontend/scripts/cenarios.mjs`.

## Objetivo

Atende ao objetivo específico (f) do TCC: auxiliar o cuidador a identificar
o que pode ter desencadeado um episódio de estresse. Quando o modelo indica
uma possível crise, a pulseira indica também se houve uma mudança no
ambiente (ruído ou luz) logo antes, e qual foi. Isso dá ao cuidador uma pista
concreta para agir ("baixar o som", "sair da sala iluminada") e, com o
histórico de episódios ([historico.md](historico.md)), permite enxergar
padrões ao longo do tempo ("7 de 10 episódios com ruído como provável
gatilho").

## Detectar a crise × indicar o provável gatilho

São duas peças diferentes, com papéis diferentes:

| | Detecção da crise | Indicação do gatilho |
|---|---|---|
| Pergunta | "A criança está entrando em crise?" | "O que mudou no ambiente logo antes?" |
| Técnica | Modelo de *machine learning* (Random Forest, `predict.js`) | Regra explicável (`trigger.js`) |
| Entrada | 24 features de 31 s de leituras (fisiologia, movimento, ambiente) | Luz e ruído dos últimos 60 s, comparados com a linha de base da própria criança |
| Saída | Probabilidade → faixa (baixo risco / atenção / possível crise) | Tipo (`ruido`, `luminosidade`, `ruido_e_luminosidade`, `nenhum_ambiental`) + texto |
| Validação | GroupKFold por criança (AUC 0,960) | Testes com casos sintéticos e cenários de ponta a ponta |

A regra **só roda depois** que o modelo alerta. Ela não muda a probabilidade
nem o nível de risco: apenas acrescenta contexto ao alerta. Foi feita como
regra, e não como um segundo modelo, porque não há dados rotulados com "qual
foi o gatilho real". Uma regra com limites explícitos pode ser explicada ao
cuidador e à banca e ajustada quando houver dados reais.

## Algoritmo passo a passo

Cada leitura (1 por segundo) é classificada pelo modelo e guardada com o seu
nível. O tempo é contado em leituras (1 leitura = 1 s), como no `predict.js`.

1. **Linha de base ambiental.** Mediana do ruído (dB) e da luz (lux) nas
   leituras em que o nível era `baixo_risco`, nos 5 minutos anteriores à
   janela de análise. A mediana ignora picos isolados. As leituras da própria
   janela de análise ficam de fora, para que o gatilho não "contamine" a
   referência. Se houver menos de 60 s de leituras calmas, usa as primeiras
   20 leituras disponíveis e marca `baseline_confiavel = false`. O texto ganha
   o aviso "interpretar com cautela".
2. **Gatilho do cálculo.** Quando o nível sai de `baixo_risco` (para
   `atencao` ou `alto_risco`), começa um episódio e a análise roda uma vez
   sobre os últimos 60 s (incluindo a leitura do alerta).
3. **Início da alteração fisiológica.** BPM acima da referência calma +
   margem (a maior entre 5 bpm e 0,5 desvio-padrão, mesma regra do
   `bpm_tempo_elevado` do `predict.js`) ou EDA acima da referência + margem
   (a maior entre 0,5 µS e 0,5 desvio-padrão). O instante é o início da
   sequência que ainda está acima da margem no momento do alerta; vale o
   primeiro dos dois sinais. Se nem BPM nem EDA passaram da margem (o modelo
   também alerta por HRV, regularidade do movimento etc.), a referência passa
   a ser o próprio instante do alerta e o texto diz "antes do alerta do
   modelo".
4. **Mudança ambiental significativa.** Para cada sinal, procura a primeira
   sequência de pelo menos 3 leituras (tolerando buracos de até 2) acima do
   limite:
   - ruído: `valor − base ≥ 15 dB`, **ou** cruzou 80 dB (com base abaixo de
     80 dB e subida de pelo menos 5 dB);
   - luz: `valor − base ≥ 50% da base` (e ≥ 100 lux), **ou** cruzou 1000 lux
     (com base abaixo de 1000), **ou** variação brusca: desvio-padrão da luz
     na janela > 30% da média (e ≥ 50 lux). Nesse caso o instante é a primeira
     sequência de leituras que se afastam mais de 30% da base, para cima ou
     para baixo.
5. **Ordem temporal.** Antecedência = início fisiológico − instante em que o
   sinal ambiental cruzou o limite. O sinal conta como gatilho se começou
   antes da fisiologia ou até 5 s depois. Se começou mais tarde, recebe o
   status `possivel_consequencia` (exemplo: a própria criança gritando eleva o
   ruído) e não entra no tipo.
6. **Resultado.** Objeto com `tipo`, `texto`, `baseline_confiavel`,
   `linha_de_base`, `fisiologia` e, por sinal (`sinais.ruido`,
   `sinais.luminosidade`): status (`gatilho` / `possivel_consequencia` /
   `estavel`), critérios atendidos, linha de base, valor no pico, variação
   (e % para a luz) e segundos de antecedência. O texto sempre diz
   "provável" ou "possível" e nunca afirma causa.
7. **Durante o episódio.** A cada leitura nova, os sinais que estavam
   estáveis são reavaliados, da mesma janela inicial até o momento atual, com
   a linha de base e o início fisiológico congelados. Se um deles passar a
   cumprir os critérios, o gatilho é atualizado (`atualizado_durante_episodio
   = true`). A mesma regra de ordem temporal vale: quase sempre o resultado é
   `possivel_consequencia`, porque a fisiologia já subiu.

Onde aparece:

- **Alerta** (`AlertBanner`): o texto aparece abaixo da mensagem principal.
- **Histórico** (`EpisodeHistory`): o texto aparece em cada episódio, com
  botões para o cuidador confirmar ou descartar.
- **MQTT**: os alertas publicados em `puzzleband/<id>/alertas` (nos dois
  modos) levam `gatilho` (o objeto completo), `episodio_id` e
  `nivel_anterior`, além de `timestamp`, `nivel`, `probabilidade`,
  `leituras`, `origem`, `fonte` e `crianca`. O estado ao vivo e o histórico
  levam o gatilho resumido (`tipo` + `texto`). Formatos em
  [mqtt.md](mqtt.md).

## Limites usados e por quê

Todos são constantes exportadas em `trigger.js`. As funções aceitam um objeto
de configuração para trocar qualquer um deles sem mexer no código.

| Constante | Valor | Por quê |
|---|---|---|
| `ANALYSIS_WINDOW_S` | 60 s | Cobre a latência típica entre um estímulo e a escalada visível, sem abrir espaço demais para coincidências |
| `BASELINE_WINDOW_S` | 300 s | A referência acompanha o ambiente atual (casa, escola), sem misturar contextos antigos |
| `BASELINE_MIN_CALM_S` | 60 s | Mínimo de amostras para uma mediana estável |
| `NOISE_RISE_DB` | +15 dB | +10 dB já é percebido como "o dobro do volume"; +15 dB é uma mudança clara, bem acima da oscilação normal de uma sala (±2 a 5 dB) |
| `NOISE_ABSOLUTE_DB` | 80 dB | Ambiente muito barulhento (trânsito pesado, refeitório cheio). Fica um pouco abaixo do limite de 85 dB(A) da NR-15 para 8 h, porque hipersensibilidade auditiva é comum no TEA |
| `NOISE_MIN_RISE_DB` | 5 dB | Evita disparar quando a base já está perto de 80 dB e só oscila |
| `LIGHT_RISE_FRACTION` | +50% | Ex.: 300 → 450 lux é uma mudança visível (acender outra luz); variações menores acontecem só por movimento do braço |
| `LIGHT_ABSOLUTE_LUX` | 1000 lux | Interiores ficam em geral entre 300 e 500 lux; acima de 1000 é luz muito forte ou sol direto |
| `LIGHT_FLICKER_CV` | 30% | Com a luz estável, a variação é de poucos % (≈3% no simulador); 30% indica liga/desliga ou luz piscando |
| `LIGHT_MIN_CHANGE_LUX` / `LIGHT_FLICKER_MIN_STD_LUX` | 100 / 50 lux | Em sala escura (10 lux), +50% são só 5 lux de ruído do sensor, não uma mudança real |
| `MIN_RUN_S` / `RUN_GAP_TOLERANCE_S` | 3 s / 2 s | Ignora uma leitura isolada (falha do sensor) sem quebrar uma subida real que oscila |
| `PHYSIO_TOLERANCE_S` | 5 s | Resolução de alguns segundos na detecção do início fisiológico (sensor a 1 Hz, margem do BPM); mudanças "simultâneas" ainda são compatíveis com gatilho |
| `BPM_MIN_MARGIN` / `BPM_MARGIN_STD_FRACTION` | 5 bpm / 0,5 σ | Mesmos parâmetros do `bpm_tempo_elevado` do modelo |
| `EDA_MIN_MARGIN_US` | 0,5 µS | Acima da oscilação do sensor (±0,3 µS no simulador) |
| `PHYSIO_MIN_TRAILING_S` | 2 s | O modelo pode alertar 2 a 3 s após o início da subida; uma sequência ainda em curso no alerta foi "cortada" pela janela |

São **valores iniciais**, escolhidos a partir dos dados sintéticos e de
referências gerais. Precisam ser recalibrados com dados reais (ver
Limitações).

## Exemplo em linha do tempo

Cenário `crise_ruido` (semente 1) de `scripts/cenarios.mjs`, rodando pelo
mesmo caminho da pulseira (buffer de 300 leituras, modelo real):

| t (s) | O que acontece |
|---|---|
| 0–119 | Criança calma: ~45 dB, ~300 lux, ~80 bpm, EDA ~4 µS. Nível `baixo_risco` |
| 120 | O ruído começa a subir para ~88 dB (rampa de 3 s) |
| 121 | O ruído passa de 45 + 15 = 60 dB → **instante do cruzamento ambiental** |
| 132 | BPM e EDA começam a subir, HRV cai (rampa de 8 s) |
| 133 | BPM passa da margem (base + 5 bpm) → **início fisiológico** |
| 134 | Modelo alerta (`atencao`; `alto_risco` em t=135) → **começa o episódio**. Janela de análise: t=75–134. Linha de base: 75 leituras calmas (t=0–74): 44,6 dB e 297 lux |
| 134 | Resultado: `tipo = ruido`, antecedência 133 − 121 = 12 s. Texto: *"Provável gatilho: ruído (45 → 89 dB, cerca de 12 s antes da alteração fisiológica)."* |
| 210 | Ruído e fisiologia voltam ao normal |
| 224–245 | O modelo ainda oscila entre `atencao` e `alto_risco` durante a recuperação (mesmo episódio) |
| 251 | Volta para `baixo_risco` (**fim** do episódio) |
| 281 | 30 s seguidos em `baixo_risco` → episódio encerrado no histórico. Duração: 117 s |

## Resultado dos testes

### Testes automatizados (`npm test`, dentro de `frontend/`)

38 testes com `node:test`, sem dependências; todos passam. Os do gatilho
(`src/model/trigger.test.js`) usam séries sintéticas com ruído determinístico
e o nível do modelo dado explicitamente:

| Caso | Situação | Resultado |
|---|---|---|
| (a) | Ruído sobe ~12 s antes da fisiologia | `ruido`, antecedência entre 8 e 14 s ✔ |
| (b) | Luz 300 → 900 lux antes da fisiologia | `luminosidade` ✔ |
| (b2) | Luz piscando (300 ↔ 80 lux), sem aumento médio | `luminosidade` por oscilação ✔ |
| (c) | Nada muda no ambiente | `nenhum_ambiental`, texto "luz e ruído estáveis" ✔ |
| (d) | Ruído sobe 30 s depois da fisiologia | `nenhum_ambiental`, ruído como `possivel_consequencia` ✔ |
| (d2) | Mesmo caso, detectado na reavaliação durante o episódio | idem, com `atualizado_durante_episodio` ✔ |
| (e) | Ambiente barulhento constante (85 dB) | `nenhum_ambiental` ✔ |
| extra | Ruído ~4 s depois da fisiologia / ~8 s depois | gatilho ("praticamente junto") / consequência ✔ |
| extra | Ruído e luz antes da fisiologia | `ruido_e_luminosidade` ✔ |
| extra | Sala escura (10 lux) com sensor oscilando | não é "luz piscando" ✔ |
| extra | Pico de 1 leitura | ignorado ✔ |
| extra | Alerta com < 60 s de leituras calmas | `baseline_confiavel = false` + aviso ✔ |
| extra | Limites configuráveis / alerta sem subida de BPM/EDA | ✔ |

### Cenários de ponta a ponta com o modelo real

`node scripts/cenarios.mjs --sementes 50`: gerador do simulador manual
(`simulate.js`) → buffer de 300 leituras → Random Forest → episódios →
gatilho. São 120 s calmos antes de cada cenário e 50 sementes de ruído
diferentes por cenário (resultado reprodutível):

| Cenário | Esperado | Acertos | Antecedência do sinal ambiental |
|---|---|---|---|
| `crise_ruido` (ruído 45 → 88 dB, ~12 s antes da fisiologia) | `ruido` | 50/50 | 10 a 13 s |
| `crise_sem_gatilho` (só a fisiologia muda) | `nenhum_ambiental` | 50/50 | – |
| `crise_luz` (controle: 300 → 950 lux) | `luminosidade` | 50/50 | 4 a 14 s |
| `ruido_depois` (controle: ruído 30 s depois) | `nenhum_ambiental` | 50/50 | −29 a −28 s (consequência) |

Cada execução gerou exatamente 1 episódio. Uma observação: em 1 das 50
sementes de `crise_luz`, o próprio modelo alertou em t=124, por causa da
mudança de luz e antes de a fisiologia subir. O modelo também usa features de
luz e ruído. Nesse caso a referência é o alerta e o texto diz "4 s antes do
alerta do modelo". A classificação continuou correta.

Esses cenários usam transições rápidas (3 a 8 s) de propósito, para testar a
regra. Os do simulador da pulseira, abaixo, usam rampas graduais.

### Cenários do simulador da pulseira (`simulator/`)

Os 11 cenários do simulador (`simulator/scenarios.js`, com fase calma inicial
e rampas de 20 a 40 s) são validados offline por
`cd simulator && npm run verificar`. A tabela completa (esperado × obtido,
50 sementes por cenário) e a análise dos casos que não batem estão em
[testes.md](testes.md). Em resumo, para a regra do gatilho:

- `crise_ruido`, `crise_luz`, `crise_ruido_e_luz`, `crise_sem_gatilho` e
  `crise_e_recuperacao` identificam o gatilho esperado em 50/50 execuções,
  com antecedência mediana de 12 s;
- `ruido_depois_da_crise` marca o ruído como `possivel_consequencia` (≈30 s
  depois da fisiologia) em 50/50, sem apontá-lo como gatilho;
- a regra só aponta gatilho quando o **modelo** alerta. Em
  `barulho_sem_crise` o modelo dá "atenção" curta só por causa da luz forte
  em 23 de 50 execuções, e a regra então indica ruído e luz. O mesmo vale para
  o `exercicio`, em que o modelo às vezes chega a "possível crise". Ver
  [testes.md](testes.md#casos-que-não-batem).

## Limitações

- **Correlação não é causa.** A regra só observa que o ambiente mudou antes
  da fisiologia. Um barulho pode coincidir com uma crise que já vinha de
  outra causa. Por isso o texto sempre diz "provável" e o cuidador confirma
  ou descarta.
- **Só luz e ruído.** Gatilhos sociais, mudança de rotina, dor ou desconforto
  físico, fome, cheiros, toque e temperatura não são vistos. Nesses casos o
  resultado é "sem gatilho ambiental aparente", o que não quer dizer "sem
  gatilho".
- **Limites iniciais.** Foram definidos com dados sintéticos. Com dados reais,
  é preciso medir a variação normal dos sensores na pulseira e recalibrar
  (por exemplo, usando as avaliações do cuidador exportadas no CSV).
- **Amostragem a 1 Hz.** Variações mais rápidas que ~0,5 Hz não aparecem: a
  cintilação de lâmpadas (100–120 Hz) é invisível ao sensor, e um estalo
  curto (< 3 s) é ignorado pelo filtro de sequência mínima.
- **O sensor está no pulso.** A manga cobrindo o sensor de luz gera uma queda
  brusca, que pode ser lida como "variação brusca". O microfone também capta
  a própria criança, e é por isso que existe a regra de ordem temporal.
- **O modelo também usa o ambiente.** Uma mudança ambiental forte pode, sozinha,
  levar o modelo a alertar antes da fisiologia. Nesse caso a antecedência é
  medida em relação ao alerta.
- **Linha de base.** Em crises longas ou seguidas, pode haver menos de 60 s
  calmos nos 5 minutos anteriores; o resultado sai como
  `baseline_confiavel = false`.
- **O cuidador decide.** A indicação é apoio, não diagnóstico. A decisão sobre
  o que fazer é sempre do cuidador.
