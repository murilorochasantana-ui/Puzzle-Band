# Modelo da tela Início (Figma)

- Arquivo: `GSSDR2ow8EqTZ6y77TmUNr` ("App Puzzle Bando"), frame `1:2`
  ("iPhone 18 Pro Max - 1").
- Lido em 06/11/2026 com **uma** chamada `get_design_context` (que já devolve
  a captura). A captura está em [home.png](home.png), em 440 × 956 px (1×).
- O código de referência do Figma (React + Tailwind) **não** foi copiado: as
  medidas abaixo servem de referência para reescrever a tela em Flutter com o
  tema de `mobile/lib/theme/`.
- Os ícones do modelo vêm como SVGs temporários (expiram em 7 dias) e não
  foram baixados: o app usa os ícones do Material equivalentes.

## Frame

| Item | Valor |
|---|---|
| Tamanho | 440 × 956 (iPhone 18 Pro Max) |
| Fundo | `#EEF3FC` |
| Margem lateral | 17 a 22 px (os blocos vão de x = 17–21 até x = 422) |
| Fonte | Inter (Regular, Medium, Semi Bold, Bold), `line-height: normal` |

## Blocos, em ordem (de cima para baixo)

Posições em px, relativas ao frame (ou ao bloco, quando indentado).

### 1. Cabeçalho: logo + nome da criança (y 37–76)

- Logo: 35 × 34 em (22, 37), raio 5, sombra `0 5 9 rgba(77,120,173,0.15)`.
- Texto "NOME DA CRIANÇA": Inter Semi Bold 20, `#000000`, em (68, 42).
  É um texto de exemplo (caixa alta só no modelo).

### 2. Linha de conexão (y 85–103)

- Ícone de nuvem com ✓ (20 × 18) em (20, 85).
- "Tudo conectado": Inter Regular 12,5, `#596C7A`, em (47, 86).

### 3. Faixa de estado "Alerta de atenção" (y 114–253)

- Caixa 405 × 139 em (17, 114), fundo `#FCF0D6`, raio 15, sombra
  `0 4 4 rgba(0,0,0,0.25)`.
- Linha do nível: triângulo de atenção 32 × 29 em (19, 12); "Atenção" Inter
  Bold 32, `#955700`, em (65, 7).
- Coluna esquerda (BPM): coração **vermelho** 39 × 36 em (13, 80); "90" Inter
  Semi Bold 64, `#20313D`, em (55, 55); "bpm" Inter Semi Bold 16, `#596C7A`,
  em (143, 100).
- Divisória vertical: x = 203, de y = 63 a 124 (61 px), 1 px.
- Coluna direita (ao vivo), x = 238:
  - ícone de pulso (linha de ECG) 20,5 × 18,5 em (238, 57);
  - "Ao vivo" Inter Semi Bold 16, `#20313D`, em (263, 59);
  - ponto **verde** de 8 px em (326, 66);
  - "Média de 5 mim:" (erro de digitação: "min") Inter Regular 16, `#4D6070`,
    em (238, 80);
  - "85 bpm" Inter Semi Bold 16, `#20313D`, em (238, 102).

### 4. Cartão do episódio (y 275–531)

- Caixa 402 × 256 em (20, 275), fundo `#FFFFFF`, raio 15, sombra
  `drop-shadow 0 4 2 rgba(0,0,0,0.25)`.
- Ícone de relógio 33 × 33 em (21, 28).
- "Episódio em andamento desde 02:21": Inter Semi Bold 14, `#20313D`, em
  (60, 27).
- "Nível mais alto: Possível crise.": Inter Regular 12,5, `#596C7A`, em
  (60, 49).
- Ícone de alto-falante 20 × 20 em (24, 88).
- "Provável gatilho: barulho": Inter Semi Bold 14, `#20313D`, em (57, 88).
- Texto técnico ("Provável gatilho: ruído (45 → 89 dB, cerca de 16 s antes da
  alteração fisiológica).") Inter Regular 12,5, `#596C7A`, entrelinha 19,
  largura 280, em (57, 109).
- Botão "Estou ciente": 362 × 53 em (16, 171), fundo `#305D88`, raio 12,
  ícone ✓ 15 px + texto Inter Semi Bold 14 branco, espaço de 8 entre eles,
  centralizado.
- O modelo **não** tem a frase "Indicação de apoio ao cuidador, sem valor
  diagnóstico."

### 5. Linha da probabilidade (y 553–609)

- Caixa 402 × 56 em (21, 553), fundo `#EDF6FF`, borda 1 px `#ABBFD2`, raio 20.
- Ícone de barras 28 × 27 em (19, 13): duas barras `#305E8B` (8 px de
  largura, raio superior 3) sobre uma base `#8BB1D6` (28 × 3).
- "Probabilidade estimada: 59%": Inter Semi Bold 15, `#1D2944`, em (65, 9).
- "Fonte: pulseira": Inter Regular 15, `#476282`, em (65, 28).

### 6. Botão "Hoje: 7 episódios" (y 620–676)

- Caixa 402 × 56 em (20, 620), fundo `#FFFFFF`, borda 1 px `#D0D0D0`, raio 20.
- Ícone de calendário 31 × 31 em (19, 12), azul escuro.
- "Hoje: 7 episódios": Inter Semi Bold 16, `#20313D`, em (68, 21).
- Seta ">" (6 × 14) em (374, 22): indica que o botão abre algo.

### 7. Navegação inferior (y 858–956)

- Faixa branca 440 × 98, sem borda visível.
- Indicador da aba ativa: 60 × 30, raio 18, `#DCE7F4`.
- Rótulos 12 px: ativo Inter Semi Bold `#20313D`, os outros Inter Medium
  `#4D6070`. Ícones 20 × 20.
- Indicador de gesto do sistema (barra `#666666`, 101 × 3,5).

## Espaços verticais entre blocos

| Entre | Espaço |
|---|---|
| Topo do frame e o logo | 37 |
| Logo e linha de conexão | 14 |
| Linha de conexão e faixa | 10 |
| Faixa e cartão do episódio | 22 |
| Cartão do episódio e probabilidade | 22 |
| Probabilidade e "Hoje" | 11 |
| "Hoje" e a navegação | 182 (área vazia no modelo) |

## Raios e sombras

| Peça | Raio | Sombra |
|---|---|---|
| Logo | 5 | `0 5 9 rgba(77,120,173,0.15)` |
| Faixa de estado | 15 | `0 4 4 rgba(0,0,0,0.25)` |
| Cartão do episódio | 15 | `0 4 2 rgba(0,0,0,0.25)` |
| Botão "Estou ciente" | 12 | — |
| Linhas de probabilidade e "Hoje" | 20 | — (só borda de 1 px) |
| Indicador da aba ativa | 18 | — |

## Cores do modelo e o tema do app

Quase todas as cores do modelo são versões muito próximas das cores do tema
atual (o modelo parece ter sido desenhado sobre a tela atual). Contrastes
medidos com a fórmula do WCAG 2.1.

| Cor no modelo | Uso | Token mais próximo no tema | Contraste no modelo |
|---|---|---|---|
| `#EEF3FC` | Fundo | `fundo` `#F0F3F5` | — |
| `#FCF0D6` / `#955700` | Faixa de Atenção / texto | `atencao.fundo` `#FCEFD6` / `atencao.texto` `#8A5200` | 5,1:1 |
| `#20313D` | Texto principal | `tinta` `#1B2A35` | — |
| `#596C7A` / `#4D6070` | Texto secundário | `tintaSuave` `#4B5B67` | 5,5:1 no branco; 4,9:1 no fundo |
| `#305D88` | Botão "Estou ciente" | `primaria` `#2D5B86` | 6,9:1 (texto branco) |
| `#DCE7F4` | Indicador da aba | `primariaSuave` `#DCE7F2` | — |
| `#EDF6FF` + borda `#ABBFD2` | Linha da probabilidade | **nova** (superfície informativa azulada) | texto 13,2:1 e 5,8:1; borda 1,7:1 (decorativa) |
| `#FFFFFF` + borda `#D0D0D0` | Botão "Hoje" | `superficie` + **borda 1,4:1** | borda abaixo de 3:1 |
| verde (ponto "Ao vivo") | Indicador ao vivo | — (verde é a cor de "Calmo") | 2,0:1 sobre a faixa |
| vermelho (coração) | Ícone do BPM | — (vermelho é reservado ao risco) | — |
| `#305E8B` / `#8BB1D6` | Ícone de barras | `primaria` / `primariaSuave` | — |

## Textos do modelo

- "NOME DA CRIANÇA"
- "Tudo conectado"
- "Atenção"
- "90" "bpm"
- "Ao vivo"
- "Média de 5 mim:" (corrigir para "min") "85 bpm"
- "Episódio em andamento desde 02:21"
- "Nível mais alto: Possível crise."
- "Provável gatilho: barulho"
- "Provável gatilho: ruído (45 → 89 dB, cerca de 16 s antes da alteração
  fisiológica)."
- "Estou ciente"
- "Probabilidade estimada: 59%" "Fonte: pulseira"
- "Hoje: 7 episódios"
- Abas: "Início", "Gráficos", "Histórico", "Ajustes"

Os números (02:21, 7, 59%, 90, 85) são exemplos: no app vêm do estado ao vivo
e do histórico.

## Estados que o modelo não mostra

O frame mostra só um caso: Atenção, com um episódio em andamento que já chegou
a Possível crise. Não há modelo para Calmo (sem episódio), sem conexão,
pulseira parada, configuração incompleta, o painel "Hoje" aberto, a confirmação
do "Estou ciente" nem o tema escuro. Esses estados seguem a mesma estrutura,
com as regras do tema.
