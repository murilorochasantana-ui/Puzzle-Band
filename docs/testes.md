# Testes e roteiro de demonstração

Há dois conjuntos de testes automáticos, ambos rodados pelo terminal:

| Onde | Comando | O que testa |
|---|---|---|
| `frontend/` | `npm test` | Regra do gatilho (casos sintéticos), histórico de episódios, CSV e cenários de ponta a ponta com transições rápidas (38 testes, `node:test`). Detalhes em [gatilho.md](gatilho.md#resultado-dos-testes) |
| `simulator/` | `npm run verificar` | Os 11 cenários do simulador da pulseira em loop (3 ciclos) e o `eventos_aleatorios` (gabarito × episódios detectados), com o modelo real (tabelas abaixo) |

## Como o `verificar.js` funciona

`simulator/verificar.js` roda cada cenário **offline**, sem conectar no
broker. Ele gera em memória as mesmas leituras que o simulador publicaria
(o mesmo `programTicks` de `simulator/scenarios.js` e o mesmo
`generateReading` de `frontend/src/model/simulate.js`) e as passa pelo
mesmo caminho do dashboard:

1. buffer de 300 leituras, como no `App.jsx`;
2. `classifyAt` (`frontend/src/model/classify.js`), que chama
   `computeFeatures`, `predictCrisisProbability` e `riskTierFromProbability`
   do `predict.js`, nas mesmas 31 leituras que o dashboard usa;
3. episódios com histerese de 30 s (`episodes.js`, a mesma função
   `ingestReadings` usada pelo hook do dashboard);
4. gatilho provável (`trigger.js`) no início de cada episódio e na
   reavaliação durante o episódio.

Cada execução usa uma semente (a mesma `--seed` do simulador). Ela controla o
ruído dos sensores e o sorteio do roteiro (variação entre ciclos, tipo e
intensidade dos eventos, pausas), então o resultado é reprodutível. Com a
mesma seed, o simulador ao vivo publica exatamente as mesmas leituras. Isso
foi conferido: 140 leituras de uma execução ao vivo com `--seed 3` bateram
campo a campo com as geradas offline.

O `npm run verificar` tem três partes:

| Parte | O que faz | Tabela |
|---|---|---|
| Loop (padrão) | Cada cenário roda 3 ciclos com a pausa calma entre eles (o 1º nominal, os outros com variação), em 20 sementes. Cada ciclo precisa dar o resultado esperado | [Cenários em loop](#cenários-em-loop-3-ciclos) |
| `eventos_aleatorios` | 20 eventos com a seed 42, comparando o gabarito com os episódios detectados, e o agregado das seeds 1–50 (1000 eventos) | [Teste com eventos aleatórios](#teste-com-eventos-aleatórios) |
| `--uma-vez` | A verificação anterior ao loop: só o roteiro nominal, uma vez por semente | [logo abaixo](#cenários--resultado-esperado--resultado-obtido) |

`--markdown` imprime as tabelas neste formato. O comando sai com código 1
enquanto houver cenário que não bate com o esperado. Hoje isso acontece em
três cenários (ver [Casos que não batem](#casos-que-não-batem)): o resultado
real é reportado, não escondido. O `eventos_aleatorios` é uma medição e não
reprova.

Linha do tempo dos cenários isolados (roteiro nominal): 0–120 s calmo (linha
de base), ruído sobe a partir de 120 s, luz a partir de 125 s, fisiologia
(BPM, EDA, HRV) a partir de 137 s. Assim, um "1º alerta" em t=140 s está ~3 s
depois do início da subida fisiológica.

## Cenários × resultado esperado × resultado obtido

Roteiro nominal, uma vez (o mesmo que o 1º ciclo do loop e o `--uma-vez` do
simulador), 50 sementes por cenário: `npm run verificar -- --uma-vez
--sementes 50`. Esta tabela não mudou com o loop: a saída é idêntica, byte a
byte, à de antes.

| Cenário | Esperado | Nível máx. | 1º alerta (t) | Episódios | Gatilho identificado | Bateu |
|---|---|---|---|---|---|---|
| `calmo` | sem alertas | baixo_risco | — | 0 | — | 50/50 |
| `exercicio` | idealmente sem alertas | atencao 34 · alto_risco 16 | 124–153 s | 2–3 | nenhum_ambiental | 0/50 (34 limitação · 16 falharam) |
| `estereotipia` | atenção/alto · nenhum_ambiental | alto_risco | 124–131 s | 1 | nenhum_ambiental | 50/50 |
| `crise_ruido` | alto_risco · ruido | alto_risco | 140–143 s | 1 | ruido | 50/50 |
| `crise_luz` | alto_risco · luminosidade | alto_risco | 132–143 s | 1 | luminosidade | 50/50 |
| `crise_sem_gatilho` | alto_risco · nenhum_ambiental | alto_risco | 140–144 s | 1 | nenhum_ambiental | 50/50 |
| `crise_ruido_e_luz` | alto_risco · ruido_e_luminosidade | alto_risco | 131–142 s | 1 | ruido_e_luminosidade | 50/50 |
| `barulho_sem_crise` | sem alertas | baixo_risco 27 · atencao 23 | 130–345 s | 0–2 | — 27 · ruido_e_luminosidade 23 | 27/50 (23 falharam) |
| `ruido_depois_da_crise` | alto_risco · nenhum_ambiental (ruído = consequência) | alto_risco | 140–144 s | 1 | nenhum_ambiental | 50/50 |
| `crise_e_recuperacao` | 1 episódio, encerrado, com duração | alto_risco | 140–143 s | 1 | ruido | 50/50 |
| `demo` | 2 episódios principais (ruido, nenhum_ambiental) | alto_risco | 68–82 s | 3–4 | ruido + nenhum_ambiental | 43/50 (7 falharam) |

"Limitação" no `exercicio` = só alertas curtos de "atenção", que é a limitação
conhecida. Quando o exercício chega a "alto_risco", conta como falha.

Detalhes dos cenários que batem:

| Cenário | Antecedência do sinal ambiental | Linha de base confiável | Duração do episódio |
|---|---|---|---|
| `crise_ruido` | 10–14 s (mediana 12 s) | 50/50 | 145–152 s |
| `crise_luz` | 3–14 s (mediana 12 s) | 50/50 | 145–156 s |
| `crise_ruido_e_luz` | ruído 3–14 s, luz 2–14 s (medianas 12 s) | 50/50 | 146–157 s |
| `crise_sem_gatilho` | — | 50/50 | 144–152 s |
| `ruido_depois_da_crise` | ruído 28–32 s **depois** da fisiologia → `possivel_consequencia` | 50/50 | 144–152 s |
| `crise_e_recuperacao` | 10–14 s (mediana 12 s) | 50/50 | 175–180 s, sempre encerrado |
| `estereotipia` | — | 50/50 | 208–218 s |

Observações:

- **Antecedências baixas (2–3 s) com luz.** Em 10/50 (`crise_luz`) e 18/50
  (`crise_ruido_e_luz`) execuções, o modelo alerta antes de BPM/EDA passarem
  da margem, empurrado pela própria luz (ver `barulho_sem_crise`). A regra
  então mede a antecedência em relação ao alerta, e o texto diz "antes do
  alerta do modelo". A classificação do gatilho continua certa em 50/50.
- **Texto do `ruido_depois_da_crise`.** Ele mostra "45 → 67 dB" e não o pico
  de 88 dB, porque a reavaliação registra o sinal no instante em que ele
  passa a cumprir o critério (no meio da rampa). Depois disso, o
  `trigger.js` só atualiza mudanças de status, não o pico.

## Casos que não batem

Seguindo a regra "ajustar o cenário, não o modelo nem os limites do
`trigger.js`", testamos variações dos três cenários abaixo antes de aceitar o
resultado (20 sementes cada).

### `exercicio`: o modelo confunde exercício com estresse

- Algum alerta em 50/50 execuções; "alto_risco" por alguns segundos (1 a 6
  leituras) em 16/50. São 2 ou 3 episódios por execução, quase sempre ao
  começar e ao parar de correr. No platô, o modelo fica ~93% do tempo em
  baixo risco.
- **Reduzir a intensidade não resolve.** Com 100%, 85%, 70%, 60% e 50% da
  `brincadeira_ativa` do dataset (BPM +38 até +19), houve "alto" em 7, 7, 9,
  9 e 6 de 20 execuções e algum alerta em 20 de 20. Rampas de 30 e 40 s e o
  formato cosseno do dataset também não resolvem.
- **Causa: a subida de EDA.** Tirando cada sinal do exercício, 20 sementes
  cada:

  | Variação | Algum alerta | "alto_risco" |
  |---|---|---|
  | exercício completo | 20/20 | 7/20 |
  | sem queda de HRV | 17/20 | 2/20 |
  | sem subida de EDA | 10/20 | 0/20 |
  | sem EDA e sem HRV | 8/20 | 0/20 |
  | só movimento | 1/20 | 0/20 |
  | só BPM | 8/20 | 0/20 |

  Sem a subida de EDA não há "alto"; a queda de HRV reforça. Isso bate com o
  [modelo.md](modelo.md#decisões-de-design): EDA sozinha não separa exercício de estresse leve, e
  essa é a fronteira mais difícil do modelo. Na validação, o modelo marcou
  8 650 de 99 009 segundos sem estresse como crise (~8,7%).
- **Mantido fiel ao exercício real.** Tirar a EDA do cenário faria o teste
  passar, mas esconderia a limitação.

### `barulho_sem_crise`: o modelo reage à luz forte sozinha

- 23/50 execuções têm "atenção" curta (1 a 29 s), nunca "alto_risco". Quando
  isso acontece, a regra indica "Provável gatilho: ruído e luminosidade
  (… antes do alerta do modelo)".
- **Quem dispara é a luz.** Só ruído a 85 dB: 0/20. Só luz a 1200 lux: 7/20.
  Com ruído a 85 dB e luz a 500 lux: 1/20; com 700, 900 ou 1200 lux: 9/20.
  Rampas de 40 s e níveis de 80 dB / 1000 lux não mudam o quadro.
- **Causa: viés do dataset sintético.** No gerador do dataset v4, a luz fica
  em ~320 ± 90 lux e só varia ±60 lux fora de crise. Picos de +200 a +500 lux
  aparecem **apenas junto com episódios de estresse** (40% deles). O modelo
  aprendeu "luz subindo ≈ estresse", uma correlação que não existe na vida
  real. Melhoria futura: gerar mudanças de ambiente também sem crise no
  dataset e retreinar. Não foi feito aqui, porque o pedido era não mexer no
  modelo.
- **É para isso que serve a avaliação do cuidador.** Esses alertas aparecem no
  histórico e podem ser descartados; o CSV exportado registra quantos foram.

### `demo`: as duas crises sempre certas; o exercício às vezes chega a "alto"

- Nas 50 execuções, os dois episódios principais saem certos e fecham antes
  do trecho seguinte:
  - crise com ruído: começa em t=230–233 s, gatilho `ruido`, duração 147–150 s;
  - crise sem gatilho: começa em t=423–426 s, `nenhum_ambiental`, duração
    163–168 s.
- O trecho de exercício gera 1 ou 2 episódios extras (16 a 93 s). Em 7/50
  execuções eles chegam a "alto_risco" por alguns segundos, o mesmo efeito do
  `exercicio`, e por isso a `demo` conta como 43/50.
- A recuperação da `demo` usa rampa de 25 s, e não de 40 s. O modelo continua
  alertando ~20–25 s depois de a fisiologia normalizar (janelas de 30 s), e
  o episódio só fecha após mais 30 s calmos. Com 40 s de rampa, a primeira
  crise ainda estaria aberta quando a segunda começa, e as duas virariam um
  episódio só.

## Cenários em loop (3 ciclos)

`npm run verificar` roda cada cenário por 3 ciclos, com pausa calma de 120 s
entre eles e no final (300 s no `barulho_sem_crise`, ver
[abaixo](#por-que-300-s-depois-do-ambiente_sem_crise)), em 20 sementes. O 1º
ciclo é o roteiro nominal. O 2º e o 3º variam o pico (±15%), a duração das
fases (±20%) e a antecedência do ambiente (8–15 s). O episódio de um ciclo é
o que começa entre o início do trecho ativo e 60 s depois do fim dele. Um
episódio fora disso, na pausa, conta como falha.

Critério por ciclo:

- **Cenários com crise:** exatamente 1 episódio, fechado ("normalizou"), com
  o nível e o gatilho esperados. Isso dá 3 episódios separados por execução.
- **`calmo`, `barulho_sem_crise` e `exercicio`:** o mesmo critério da tabela
  anterior.
- **`demo`:** as 2 crises do ciclo com 1 episódio fechado cada e o gatilho
  certo, e só "atenção" no trecho de exercício.

| Cenário | Esperado em cada ciclo | Episódios/execução | Fechados | Gatilho identificado (por ciclo) | Ciclos certos | Execuções 3/3 |
|---|---|---|---|---|---|---|
| `calmo` | sem alertas | 0 | — | — | 60/60 | 20/20 |
| `exercicio` | idealmente sem alertas | 6–8 | 131/131 | nenhum_ambiental | 0/60 (37 limitação · 23 falharam) | 0/20 (5 limitação · 15 falharam) |
| `estereotipia` | 1 episódio fechado · atenção/alto · nenhum_ambiental | 3 | 60/60 | nenhum_ambiental | 60/60 | 20/20 |
| `crise_ruido` | 1 episódio fechado · alto_risco · ruido | 3 | 60/60 | ruido | 60/60 | 20/20 |
| `crise_luz` | 1 episódio fechado · alto_risco · luminosidade | 3 | 60/60 | luminosidade | 60/60 | 20/20 |
| `crise_sem_gatilho` | 1 episódio fechado · alto_risco · nenhum_ambiental | 3 | 60/60 | nenhum_ambiental | 60/60 | 20/20 |
| `crise_ruido_e_luz` | 1 episódio fechado · alto_risco · ruido_e_luminosidade | 3 | 60/60 | ruido_e_luminosidade | 60/60 | 20/20 |
| `barulho_sem_crise` | sem alertas | 0–4 | 23/23 | — 40 · ruido_e_luminosidade 16 · luminosidade 2 · nenhum_ambiental 1 · ruido 1 | 40/60 (20 falharam) | 6/20 (14 falharam) |
| `ruido_depois_da_crise` | 1 episódio fechado · alto_risco · nenhum_ambiental (ruído = consequência) | 3 | 60/60 | nenhum_ambiental | 60/60 | 20/20 |
| `crise_e_recuperacao` | 1 episódio fechado · alto_risco · ruido | 3 | 60/60 | ruido | 60/60 | 20/20 |
| `demo` | 2 episódios fechados (ruido, nenhum_ambiental) + só "atenção" no exercício | 9–11 | 191/191 | ruido + nenhum_ambiental | 51/60 (9 falharam) | 12/20 (8 falharam) |

Detalhes por ciclo:

| Cenário | 1º ciclo (nominal) | Ciclos variados | Alerta após a fisiologia | Antecedência medida | Linha de base confiável | Duração dos episódios | Episódios nas pausas |
|---|---|---|---|---|---|---|---|
| `calmo` | 20/20 | 40/40 | — | — | — | — | 0 |
| `exercicio` | 0/20 (13 limitação · 7 falharam) | 0/40 (24 limitação · 16 falharam) | 7–32 s (mediana 19,5 s) | — | 60/60 (70–286 leituras) | 1–80 s | 0 |
| `estereotipia` | 20/20 | 40/40 | 3–11 s (mediana 8 s) | — | 60/60 (65–112 leituras) | 185–235 s | 0 |
| `crise_ruido` | 20/20 | 40/40 | 3–7 s (mediana 5 s) | 6–16 s (planejada 8–15 s) | 60/60 (81–167 leituras) | 130–160 s | 0 |
| `crise_luz` | 20/20 | 40/40 | 2–7 s (mediana 4 s) | 7–16 s (planejada 8–15 s) | 60/60 (81–166 leituras) | 128–160 s | 0 |
| `crise_sem_gatilho` | 20/20 | 40/40 | 2–7 s (mediana 5 s) | — | 60/60 (81–156 leituras) | 130–160 s | 0 |
| `crise_ruido_e_luz` | 20/20 | 40/40 | −2 a 6 s (mediana 4 s) | ruído 6–16 s, luz 7–15 s (planejada 8–15 s) | 60/60 (78–166 leituras) | 131–160 s | 0 |
| `barulho_sem_crise` | 11/20 (9 falharam) | 29/40 (11 falharam) | — | — | 20/20 (78–300 leituras) | 1–29 s | 0 |
| `ruido_depois_da_crise` | 20/20 | 40/40 | 2–7 s (mediana 5 s) | — | 60/60 (81–156 leituras) | 130–160 s | 0 |
| `crise_e_recuperacao` | 20/20 | 40/40 | 3–7 s (mediana 4 s) | 7–16 s (planejada 8–15 s) | 60/60 (81–142 leituras) | 155–195 s | 0 |
| `demo` | 17/20 (3 falharam) | 34/40 (6 falharam) | — | — | 120/120 (104–193 leituras) | 16–185 s | 0 |

Leitura das tabelas:

- **Os 7 cenários com crise batem 60/60 ciclos.** Cada execução tem 3
  episódios separados e fechados, sempre com o gatilho esperado; a variação
  não tirou nenhum ciclo do resultado esperado. Com a pausa mínima
  (`node verificar.js --pausa 90 --sementes 40`), eles dão 120/120.
- **A linha de base fica confiável em todos os ciclos**, com pelo menos 65
  leituras calmas (a regra pede 60). Nas crises isoladas, o 1º ciclo tem as
  menores contagens (78–84), porque só conta com os 2 min calmos iniciais;
  nos ciclos seguintes, são 143–167. Na `estereotipia`, os episódios são
  longos (~3,5 min) e ocupam boa parte da janela de 5 min da linha de base,
  então o 1º e o 3º ciclo chegam a 65. Com `--pausa 90`, o mínimo é 64.
- **Antecedência medida de 6–16 s, para a planejada de 8–15 s.** A regra mede
  do cruzamento do limite até o início detectado da fisiologia, e esse início
  varia 1–2 s com o ruído dos sensores e com o pico.
- **`exercicio`, `barulho_sem_crise` e `demo` falham nas mesmas taxas do
  roteiro nominal**, pelas causas de [Casos que não batem](#casos-que-não-batem):
  - `barulho_sem_crise`: 40/60 ciclos sem alerta (67%; no roteiro nominal,
    27/50 = 54%). Com 3 ciclos por execução, só 6/20 execuções passam sem
    nenhum alerta.
  - `demo`: nos ciclos que falham, as duas crises saem certas e fechadas. Em
    100 sementes (300 ciclos), as crises principais acertaram em 300/300; o
    que falha é o trecho de exercício chegar a "alto_risco" (48/300 = 16%;
    no roteiro nominal, 7/50 = 14%).

## Teste com eventos aleatórios

O cenário `eventos_aleatorios` sorteia eventos de 8 tipos (tabela no
[README](../README.md#cenário-eventos_aleatorios)), com intensidade leve
(×0,3), moderada (×0,65) ou alta (×1) nas crises e pausas calmas de 120 a
240 s. O `verificar.js` faz duas coisas:

1. roda 20 eventos com a seed 42 e compara o gabarito do sorteio com os
   episódios detectados pelas mesmas funções do site;
2. repete o teste com as seeds 1 a 50 (1000 eventos), para todos os tipos e
   intensidades terem amostra.

Um episódio pertence a um evento se começa entre o início do evento (o
primeiro sinal mudando) e 60 s depois do fim dele. "Alerta após a
fisiologia" é o início do episódio menos o início da alteração fisiológica;
no `exercicio` e no `motora`, é o início da atividade.

### Seed 42, 20 eventos

Comando: `node verificar.js --cenario eventos_aleatorios` (1,9 h simuladas).
Esta é a sequência que o teste ao vivo repete com `--seed 42`; a coluna
"Início" é o tempo no log do simulador.

| # | Tipo | Intensidade | Início | Crise real | Gatilho esperado | Episódios | Nível máx. | Gatilho identificado | Alerta após a fisiologia | Duração | Resultado |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | sobrecarga_sensorial | leve | 01:58 | sim | ruido_e_luminosidade | 1 | alto_risco | ruido_e_luminosidade | 4 s | 142 s | acerto |
| 2 | interna | leve | 08:22 | sim | nenhum_ambiental | 1 | alto_risco | nenhum_ambiental | 11 s | 119 s | acerto |
| 3 | sonora | alta | 13:17 | sim | ruido | 1 | alto_risco | ruido | 6 s | 137 s | acerto |
| 4 | interna | alta | 17:53 | sim | nenhum_ambiental | 1 | alto_risco | nenhum_ambiental | 4 s | 136 s | acerto |
| 5 | exercicio | — | 22:01 | não | sem episódio | 3 | atencao | nenhum_ambiental | 13 s | 50 s | alerta falso |
| 6 | exercicio | — | 28:23 | não | sem episódio | 3 | atencao | nenhum_ambiental | 24 s | 28 s | alerta falso |
| 7 | consequencia | alta | 33:55 | sim | nenhum_ambiental | 1 | alto_risco | nenhum_ambiental | 6 s | 156 s | acerto |
| 8 | visual | leve | 39:48 | sim | luminosidade | 1 | alto_risco | luminosidade | 11 s | 129 s | acerto |
| 9 | exercicio | — | 44:33 | não | sem episódio | 2 | alto_risco | nenhum_ambiental | 18 s | 60 s | alerta falso |
| 10 | sonora | alta | 51:38 | sim | ruido | 1 | alto_risco | ruido | 5 s | 146 s | acerto |
| 11 | visual | moderada | 56:37 | sim | luminosidade | 1 | alto_risco | luminosidade | 6 s | 132 s | acerto |
| 12 | sobrecarga_sensorial | moderada | 1:00:50 | sim | ruido_e_luminosidade | 1 | alto_risco | ruido_e_luminosidade | 5 s | 149 s | acerto |
| 13 | sonora | leve | 1:05:43 | sim | ruido | 1 | alto_risco | ruido | 15 s | 133 s | acerto |
| 14 | sonora | alta | 1:12:21 | sim | ruido | 1 | alto_risco | ruido | 5 s | 165 s | acerto |
| 15 | consequencia | alta | 1:18:48 | sim | nenhum_ambiental | 1 | alto_risco | nenhum_ambiental | 4 s | 157 s | acerto |
| 16 | sonora | leve | 1:24:28 | sim | ruido | 1 | alto_risco | ruido | 9 s | 110 s | acerto |
| 17 | exercicio | — | 1:29:16 | não | sem episódio | 2 | alto_risco | nenhum_ambiental | 15 s | 56 s | alerta falso |
| 18 | exercicio | — | 1:35:36 | não | sem episódio | 2 | atencao | nenhum_ambiental | 21 s | 33 s | alerta falso |
| 19 | consequencia | leve | 1:43:02 | sim | nenhum_ambiental | 1 | alto_risco | nenhum_ambiental | 12 s | 129 s | acerto |
| 20 | sobrecarga_sensorial | moderada | 1:48:59 | sim | ruido_e_luminosidade | 1 | alto_risco | ruido_e_luminosidade | 7 s | 133 s | acerto |

- Crises reais detectadas: 15 de 15 (100%) · por intensidade: leve 6/6 · moderada 3/3 · alta 6/6
- Alertas falsos: 5 de 5 eventos sem crise viraram episódio (exercicio 5/5)
- Episódios fora dos eventos (nas pausas): 0
- Gatilho certo: 15 de 15 crises detectadas (100%)
- Tempo médio até o alerta: 7,3 s depois do início da alteração fisiológica (17,9 s depois do início do evento)
- Duração média dos episódios: 138 s nas crises · 45 s nos alertas falsos

Acerto do gatilho por tipo:

| Tipo | Gatilho esperado | Eventos | Com episódio | Acertos | Alerta após a fisiologia (média) | Duração média |
|---|---|---|---|---|---|---|
| sonora | ruido | 5 | 5/5 | 5/5 (100%) | 8,0 s | 138 s |
| visual | luminosidade | 2 | 2/2 | 2/2 (100%) | 8,5 s | 131 s |
| sobrecarga_sensorial | ruido_e_luminosidade | 3 | 3/3 | 3/3 (100%) | 5,3 s | 141 s |
| interna | nenhum_ambiental | 2 | 2/2 | 2/2 (100%) | 7,5 s | 128 s |
| motora | nenhum_ambiental | 0 | — | — | — | — |
| consequencia | nenhum_ambiental | 3 | 3/3 | 3/3 (100%) | 7,3 s | 147 s |
| exercicio | sem episódio | 5 | 5/5 (alerta falso) | 0/5 sem alerta | — | 45 s |
| ambiente_sem_crise | sem episódio | 0 | — | — | — | — |

A seed 42 não sorteou nenhum `motora` nem `ambiente_sem_crise` (pesos de 10%
e 5%), e a seed não foi trocada para "melhorar" a amostra. O agregado abaixo
cobre todos os tipos.

### Agregado: seeds 1–50 × 20 eventos

- Crises reais detectadas: 852 de 852 (100%) · por intensidade: leve 248/248 · moderada 303/303 · alta 301/301
- Alertas falsos: 115 de 148 eventos sem crise viraram episódio (exercicio 96/96 · ambiente_sem_crise 19/52)
- Episódios fora dos eventos (nas pausas): 0
- Gatilho certo: 852 de 852 crises detectadas (100%)
- Tempo médio até o alerta: 7,2 s depois do início da alteração fisiológica (15,5 s depois do início do evento)
- Duração média dos episódios: 147 s nas crises · 38 s nos alertas falsos

Acerto do gatilho por tipo:

| Tipo | Gatilho esperado | Eventos | Com episódio | Acertos | Alerta após a fisiologia (média) | Duração média |
|---|---|---|---|---|---|---|
| sonora | ruido | 186 | 186/186 | 186/186 (100%) | 7,2 s | 138 s |
| visual | luminosidade | 134 | 134/134 | 134/134 (100%) | 7,3 s | 137 s |
| sobrecarga_sensorial | ruido_e_luminosidade | 150 | 150/150 | 150/150 (100%) | 5,5 s | 141 s |
| interna | nenhum_ambiental | 172 | 172/172 | 172/172 (100%) | 7,4 s | 139 s |
| motora | nenhum_ambiental | 105 | 105/105 | 105/105 (100%) | 8,2 s | 208 s |
| consequencia | nenhum_ambiental | 105 | 105/105 | 105/105 (100%) | 8,6 s | 138 s |
| exercicio | sem episódio | 96 | 96/96 (alerta falso) | 0/96 sem alerta | — | 43 s |
| ambiente_sem_crise | sem episódio | 52 | 19/52 (alerta falso) | 33/52 sem alerta | — | 10 s |

Por intensidade (só crises reais):

| Intensidade | Crises | Detectadas | Chegaram a alto_risco | Gatilho certo | Alerta após a fisiologia | Duração média |
|---|---|---|---|---|---|---|
| leve (×0,3) | 248 | 248/248 | 248/248 | 248/248 | 11,4 s (−1 a 21 s) | 133 s |
| moderada (×0,65) | 303 | 303/303 | 303/303 | 303/303 | 6,5 s (−8 a 12 s) | 152 s |
| alta (×1) | 301 | 301/301 | 301/301 | 301/301 | 4,6 s (−5 a 13 s) | 155 s |

Leitura:

- **Todas as 852 crises viraram episódio, com o gatilho certo**, nas três
  intensidades. A intensidade muda a latência: o alerta vem, em média, 4,6 s
  depois do início da alteração fisiológica na alta e 11,4 s na leve. Mesmo
  a leve (×0,3, perto do nível "leve" do dataset v4) chega a "alto_risco".
  Num teste à parte com ×0,2 (fora do sorteio), parte das crises ficou só em
  "atenção". Latência negativa
  quer dizer que o modelo alertou antes da fisiologia, empurrado pela luz (o
  viés do dataset descrito no `barulho_sem_crise`).
- **Os alertas falsos vêm dos eventos sem crise, como nos cenários
  isolados.** Todo `exercicio` gerou episódio (96/96, média de 43 s), e o
  `ambiente_sem_crise` gerou em 19/52 (média de 10 s).
- **Nenhum episódio começou nas pausas** nestes 1000 eventos (97 h
  simuladas). Em testes maiores apareceu um "atenção" isolado de 1 a 6 s no
  meio de leituras calmas: 1 vez nas seeds 1–200 com pausa de 120 s (387 h
  simuladas) e 1 vez nas seeds 1–50 com `--pausa 90` (85 h). É um falso
  positivo raro do modelo em repouso, sem relação com o loop.
- O `motora` tem episódios mais longos (208 s) porque a estereotipia dura mais
  (200 s de atividade).

### Por que 300 s depois do `ambiente_sem_crise`

Na primeira versão, a pausa depois do `ambiente_sem_crise` também era de
120–240 s, e o agregado deu **8 erros de gatilho em 852 crises**: 7 `sonora`
e 1 `sobrecarga_sensorial` identificadas como `nenhum_ambiental` ou
`luminosidade`. Todas vinham logo depois de um `ambiente_sem_crise`, com pausa
de 120–163 s.

Nesse evento a criança fica calma. O modelo fica em baixo risco, e as leituras
com 85 dB e 1200 lux **entram na linha de base de 5 min** do `trigger.js`
(mediana das leituras calmas). A linha de base ficou em 80–87 dB e
1100–1270 lux, e o ruído da crise seguinte (88 dB) não passava de +15 dB sobre
ela. A regra funcionou como foi projetada: um ambiente que já estava
barulhento passa a ser o normal. O que faltava era tempo para a linha de base
se restabelecer.

O ajuste foi no cenário, não no `trigger.js`: a pausa depois do
`barulho_sem_crise`/`ambiente_sem_crise` tem no mínimo 300 s, a janela da
linha de base (`BASELINE_WINDOW_S`, lida do `trigger.js`). Depois disso, os
erros de gatilho caíram para 0 nos 1000 eventos das seeds 1–50 e nos 4000 das
seeds 1–200.

Isso também mostra um limite real: na vida real não há pausa garantida. Se o
ambiente ficar barulhento por vários minutos com a criança calma e uma crise
vier logo depois, a regra compara com esse ambiente barulhento e pode não
indicar o ruído como gatilho.

### Repetir ao vivo e comparar com o gabarito

1. `frontend/.env` e `simulator/.env` configurados, com o mesmo `CHILD_ID`.
   Terminal 1: `cd frontend` e `npm run dev`. Abra o site, escolha
   **Pulseira (MQTT)** e confira "Broker: conectado".
2. No histórico do site, exporte o CSV anterior (se quiser guardar) e use
   **Limpar histórico**.
3. Terminal 2: `cd simulator` e
   `npm run eventos-aleatorios -- --ciclos 20 --seed 42`. O simulador imprime
   o caminho do gabarito (`logs/eventos_<data-hora>.csv`). Deixe o site
   aberto durante todo o teste: é ele que roda o modelo. O simulador para
   sozinho depois do 20º evento e de uma pausa final, para o último episódio
   fechar (cerca de 1 h 55 min).
4. No site, clique em **Exportar CSV** no histórico.
5. Abra os dois CSVs no Excel (os dois usam `;` e vírgula decimal). As datas
   estão no mesmo horário local. O gabarito usa ISO 8601
   (`2026-11-04T14:03:12-03:00`) e o site usa `2026-11-04 14:03:12`; para
   converter a coluna do gabarito, use
   `=VALOR(SUBSTITUIR(ESQUERDA(D2;19);"T";" "))`.
6. Para cada linha do gabarito, procure no histórico os episódios cujo
   `inicio` fica entre o `inicio` do evento e 60 s depois do `fim`:
   - `crise_real` = sim: precisa haver episódio, e o `gatilho_tipo` do site
     deve ser igual ao `gatilho_esperado`;
   - `crise_real` = não: um episódio ali é alerta falso;
   - tempo até o alerta = `inicio` do episódio − `fisiologia_inicio` do
     gabarito; a duração está em `duracao_s`.

Com a mesma seed, as leituras ao vivo são as mesmas da verificação offline,
então o esperado é a tabela da seed 42 acima, evento por evento. Pode haver
diferença se leituras se perderem no caminho (QoS 0, rede instável) ou se o
site for aberto depois de o simulador começar. Nesse caso, a linha de base
dos primeiros minutos fica mais curta. Outra seed (`--seed 7`) dá outra
sequência; a tabela esperada dela sai de
`node verificar.js --cenario eventos_aleatorios --seed 7 --agregado 0`.

## Roteiro de demonstração

> Com o app do cuidador no celular (notificação, "Estou ciente" e avaliação
> pelo app), siga o roteiro em 4 passos do
> [README](../README.md#roteiro-de-demonstração-site--app). Durante o `demo`
> abaixo, o app aberto recebe o mesmo estado, os alertas e o histórico.

O roteiro do cenário `demo` dura **10,5 minutos** (630 s), com o nome da fase
em cada linha do log. Com `--ciclos 1` ele roda uma vez, sem variação (o 1º
ciclo é sempre o nominal), e encerra depois de uma pausa calma final:

```
0 s calmo → 60 s exercício → 150 s calmo → 210 s crise com ruído
→ 330 s recuperação → 420 s crise sem gatilho → 540 s recuperação
→ 565 s pausa calma final → 685 s fim
```

### Antes de começar

1. `frontend/.env` e `simulator/.env` configurados, com o mesmo `CHILD_ID`.
2. Terminal 1: `cd frontend` e `npm run dev`. Abra o dashboard e escolha
   **Pulseira (MQTT)**. O status deve mostrar "Broker: conectado".
3. No histórico, exporte o CSV dos testes anteriores (se quiser guardar) e
   use **Limpar histórico**, para a plateia ver só os episódios da demo.
4. Terminal 2: `cd simulator` e `npm run demo -- --ciclos 1`. A pausa final
   de 2 min garante que o último episódio feche antes de o simulador parar
   (sem `--ciclos 1`, a demo recomeça em loop, já com variação). Ao parar, o
   simulador publica "offline", e o dashboard mostra "Pulseira: offline".

### Linha do tempo

Os tempos são contados desde o início do simulador e variam ±3 s com o ruído
dos sensores.

| Tempo | Fase no log | O que aparece no dashboard | O que mostrar ou dizer |
|---|---|---|---|
| 0:00–1:00 | `demo 1/7 · calmo` | "Sem sinais de crise"; o modelo começa a avaliar após 31 s de leituras | Os 7 sensores; o modelo roda no navegador |
| 1:00–2:30 | `demo 2/7 · exercício` | BPM, EDA e movimento sobem juntos. Na maior parte do tempo, "Sem sinais de crise", mas pode aparecer **"Atenção"** e, às vezes, "Possível crise" por alguns segundos | Limitação real do modelo: a EDA também sobe no exercício. É por isso que o sistema é apoio e o cuidador avalia |
| 2:30–3:30 | `demo 3/7 · calmo` | Volta ao normal; os alertas do exercício viram 1–2 episódios encerrados no histórico | Histerese: o episódio só fecha após 30 s calmos |
| 3:30 | `demo 4/7 · crise com ruído: ruído subindo` | O ruído sobe para ~88 dB; o modelo continua em baixo risco | O ambiente mudou, mas a criança ainda está bem |
| 3:47 | `… fisiologia subindo` | BPM e EDA sobem, HRV cai | — |
| ~3:51 | `demo 4/7 · crise com ruído` | **"Possível crise"** + *"Provável gatilho: ruído (45 → 89 dB, cerca de 12 s antes da alteração fisiológica)"*; episódio "em andamento" no histórico | Detectar a crise (modelo) × indicar o provável gatilho (regra explicável); "provável", nunca causa |
| 5:30 | `demo 5/7 · recuperação` | Sinais voltam ao normal; o alerta some por volta de 6:20 | — |
| ~6:50 | — | O episódio encerra no histórico (~2 min 30 s) | Clicar em **Confirmar gatilho** e escrever uma observação ("som alto na sala") |
| 7:00 | `demo 6/7 · crise sem gatilho` | Por volta de 7:05: **"Possível crise"** + *"Sem gatilho ambiental aparente: luz e ruído estáveis. A causa pode ser outra (social, rotina, desconforto físico)."* | O sistema não inventa uma causa quando o ambiente não mudou |
| 9:00 | `demo 7/7 · recuperação` | O alerta some por volta de 9:50; o episódio encerra por volta de 10:20 | — |
| 9:25–11:25 | `pausa calma final · encerra em … s` | Resumo de padrões, por exemplo "Ruído como provável gatilho: 1 de 4 episódios · 1 confirmado pelo cuidador" | Clicar em **Exportar CSV** (registro de testes do TCC); dados só no navegador (LGPD) |

O total do resumo costuma ser 3 ou 4 episódios: as duas crises mais 1 ou 2
alertas do exercício. Dá para clicar em **Descartar** nos do exercício
durante a fala sobre limitações e mostrar a avaliação do cuidador.

### Plano B (sem internet ou sem broker)

O modo **Simulador manual** não depende de rede. A mesma história em 1x:

1. Deixe calmo ~2 min (ou use 4x no aquecimento e volte para 1x).
2. Suba o ruído para ~88 dB; ~10–15 s depois, suba BPM (~120), EDA (~11) e
   baixe a HRV (~25). O alerta mostra "Provável gatilho: ruído".
3. Volte tudo ao normal. Uns 30 s depois de o alerta sumir, o episódio
   encerra; confirme o gatilho.
4. Repita o passo 2 sem mexer em luz e ruído: "Sem gatilho ambiental
   aparente".
5. Exporte o CSV.
