# Testes e roteiro de demonstração

Há dois conjuntos de testes automáticos, ambos rodados pelo terminal:

| Onde | Comando | O que testa |
|---|---|---|
| `frontend/` | `npm test` | Regra do gatilho (casos sintéticos), histórico de episódios, CSV e cenários de ponta a ponta com transições rápidas (38 testes, `node:test`). Detalhes em [gatilho.md](gatilho.md#resultado-dos-testes) |
| `simulator/` | `npm run verificar` | Os 11 cenários do simulador da pulseira, com o modelo real (tabela abaixo) |

## Como o `verificar.js` funciona

`simulator/verificar.js` roda cada cenário **offline**, sem conectar no
broker. Ele gera em memória as mesmas leituras que o simulador publicaria
(`generateReading` de `frontend/src/model/simulate.js`) e as passa pelo
mesmo caminho do dashboard:

1. buffer de 300 leituras, como no `App.jsx`;
2. `classifyAt` (`frontend/src/model/classify.js`), que chama
   `computeFeatures`, `predictCrisisProbability` e `riskTierFromProbability`
   do `predict.js`, nas mesmas 31 leituras que o dashboard usa;
3. episódios com histerese de 30 s (`episodes.js`, a mesma função
   `ingestReadings` usada pelo hook do dashboard);
4. gatilho provável (`trigger.js`) no início de cada episódio e na
   reavaliação durante o episódio.

Cada cenário roda com várias sementes de ruído dos sensores (o
`Math.random` ganha uma semente durante a simulação, então o resultado é
reprodutível). Os números abaixo são de `npm run verificar -- --sementes 50`
(`--markdown` imprime a tabela neste formato). O comando sai com código 1
enquanto houver cenário que não bate com o esperado. Hoje isso acontece em
três cenários (ver [Casos que não batem](#casos-que-não-batem)): o resultado
real é reportado, não escondido.

Linha do tempo dos cenários isolados: 0–120 s calmo (linha de base), ruído
sobe a partir de 120 s, luz a partir de 125 s, fisiologia (BPM, EDA, HRV)
a partir de 137 s. Assim, um "1º alerta" em t=140 s está ~3 s depois do
início da subida fisiológica.

## Cenários × resultado esperado × resultado obtido

50 sementes por cenário:

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

## Roteiro de demonstração

> Com o app do cuidador no celular (notificação, "Estou ciente" e avaliação
> pelo app), siga o roteiro em 4 passos do
> [README](../README.md#roteiro-de-demonstração-site--app). Durante o `demo`
> abaixo, o app aberto recebe o mesmo estado, os alertas e o histórico.

O cenário `demo` roda sozinho por **10,5 minutos** (630 s), com o nome da fase
em cada linha do log:

```
0 s calmo → 60 s exercício → 150 s calmo → 210 s crise com ruído
→ 330 s recuperação → 420 s crise sem gatilho → 540 s recuperação → 630 s fim
```

### Antes de começar

1. `frontend/.env` e `simulator/.env` configurados, com o mesmo `CHILD_ID`.
2. Terminal 1: `cd frontend` e `npm run dev`. Abra o dashboard e escolha
   **Pulseira (MQTT)**. O status deve mostrar "Broker: conectado".
3. No histórico, exporte o CSV dos testes anteriores (se quiser guardar) e
   use **Limpar histórico**, para a plateia ver só os episódios da demo.
4. Terminal 2: `cd simulator` e `npm run demo -- --duracao 660`. Os 30 s
   extras garantem que o último episódio feche antes de o simulador parar.
   Ao parar, o simulador publica "offline", e o dashboard mostra
   "Pulseira: offline".

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
| 10:30 | `demo encerrada (calmo)` | Resumo de padrões, por exemplo "Ruído como provável gatilho: 1 de 4 episódios · 1 confirmado pelo cuidador" | Clicar em **Exportar CSV** (registro de testes do TCC); dados só no navegador (LGPD) |

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
