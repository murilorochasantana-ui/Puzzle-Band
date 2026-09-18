# Avaliação do dataset sintético — alinhamento com a proposta do TCC

Scripts completos em `model/eda/` (Python), reprodutíveis a partir do
`dataset_pulseira_TEA_estresse.xlsx` original.

## O que foi avaliado

1. Qualidade básica: nulos, duplicatas, ranges dos sinais
2. Se o rótulo de estresse está "vazado" por outra coluna (ex.: atividade física)
3. Se cada criança tem um perfil fisiológico próprio (base para personalização,
   como o TCC exige — "não existe padrão único aplicável a toda população")
4. Se os episódios de estresse têm estrutura temporal realista (rampa
   gradual, não liga/desliga instantâneo)
5. Se o problema é **aprendível**: treinei um classificador RandomForest
   (Python/scikit-learn) com validação cruzada **por criança**
   (`GroupKFold`) — ou seja, o modelo nunca vê dados da criança que está
   sendo avaliada, simulando o uso real do sistema numa criança nova

## Resultados — dataset original

| Checagem | Resultado |
|---|---|
| Nulos / duplicatas | Nenhum |
| Ranges dos sinais | BPM 60–166, EDA 1.48–14.05 µS, giroscópio 0.09–904.88 dps — plausíveis |
| Estresse × atividade física | **Sem confusão** — prevalência de estresse é ~7–8% em `calmo`, `atividade_leve` e `brincadeira_ativa` (quase idêntico). Isso é importante: confirma que o dataset não deixa o modelo "trapacear" usando o nível de movimento como proxy de estresse — bate com o argumento do TCC de que o estresse pode ser interno e não visível |
| Perfil por criança | Baseline de BPM varia de 80,9 a 104,7 entre crianças; EDA de 2,75 a 5,12 µS — cada criança tem uma "linha de base" própria, o que sustenta a necessidade de limiares personalizados citada no TCC |
| Estrutura temporal | 55 episódios contínuos de estresse, duração 49–237s (mediana 154s) — sem "flicker" de 1 segundo, condizente com o curso real de uma resposta de estresse |
| **Desempenho do modelo baseline** (GroupKFold, 4 folds, 3 crianças de teste por fold) | **AUC médio 0.989**, F1 médio 0.82, recall 0.92, precisão 0.76 |

A alta separabilidade (AUC ~0.99) sem ser perfeita (1.0) é o resultado ideal:
mostra que existe um padrão real e aprendível nos sinais (justifica usar
Machine Learning), mas não é tão trivial a ponto de um limiar simples (ex.:
`if bpm > 120`) resolver sozinho — o que teria esvaziado a proposta.

A importância de features do modelo confirma a literatura citada no TCC: o
sinal de EDA/GSR (`nivel_suor_uS`) domina a decisão do modelo, seguido pelo
giroscópio; BPM tem peso menor.

## Problema encontrado

Ao cruzar `id_crianca` × `nivel_estresse`, **8 das 12 crianças não tinham
pelo menos um nível de severidade**:

| Criança | Nível ausente |
|---|---|
| C03, C07, C08, C10 | alto |
| C05, C09, C11 | leve |
| C06 | moderado |

Isso é um problema para a validação cruzada por criança: ao testar num fold
que isola, por exemplo, C03/C07/C11, o modelo nunca teria visto (nem teria
como ser avaliado em) casos de "alto" vindos dessas crianças — o que
enfraquece a demonstração de generalização por severidade, um ponto que a
banca provavelmente vai perguntar.

## Correção aplicada — dataset v2

Script `model/eda/06_augment_dataset.py`: para cada combinação
criança×nível ausente, insere **um episódio sintético adicional** (150s)
dentro de um trecho `calmo` já existente daquela criança (com folga de 60s
de qualquer outro episódio, para não sobrepor rótulos).

O episódio segue a mesma "forma" dos episódios reais do dataset (rampa
suave de subida/plateau/descida, via envelope cosseno), com o pico do sinal
calibrado a partir:
- da média global daquele nível de severidade no dataset original, e
- do desvio (offset) da própria criança em relação à média geral — preserva
  o perfil individual em vez de "achatar" todo mundo no mesmo valor

`giroscopio_x/y/z` são reescalados proporcionalmente para que a magnitude
resultante bata com o alvo, mantendo o padrão de ruído/direção já presente
nos dados originais.

**Arquivo gerado:** `data/raw/dataset_pulseira_TEA_estresse_v2.xlsx`

## Resultado pós-correção

- Todas as 12 crianças agora têm registros em `nenhum`, `leve`, `moderado`
  **e** `alto`
- Ranges dos sinais permanecem idênticos aos originais (nada fora da faixa
  fisiológica já validada)
- Reavaliação do mesmo modelo baseline: **AUC 0.989, F1 0.82, recall 0.93,
  precisão 0.75** — estatisticamente equivalente ao dataset original, ou
  seja, a correção fechou a lacuna de cobertura **sem** artificializar o
  problema (não ficou mais fácil nem mais difícil de aprender)

## Conclusão

O dataset já vinha bem alinhado com a proposta do TCC antes de qualquer
alteração — sem viés óbvio, com personalização por criança e um problema de
classificação genuinamente aprendível via ML (não trivial, não impossível).
A única lacuna real era de cobertura de severidade por criança, corrigida no
`dataset_pulseira_TEA_estresse_v2.xlsx`, que é a versão recomendada para
treinar o modelo preditivo.
