# Design do app do cuidador (UX/UI)

Este documento descreve o redesenho visual do app do cuidador (`mobile/`): a
direção visual, a paleta com os contrastes medidos, a tipografia, as decisões
de acessibilidade pensadas para o público do TEA e o antes e depois de cada
tela. A lógica do app (MQTT, notificações, formatos de mensagem) não mudou; o
funcionamento está em [app.md](app.md).

## 1. Público e tarefa principal

Quem usa o app são pais, cuidadores e profissionais de crianças com TEA.
Muitas vezes estão cansados, sob estresse, com a atenção dividida e olham o
celular por poucos segundos. A pergunta que o app precisa responder nesse
tempo é uma só: **"preciso agir agora?"**. Disso saem três requisitos:

1. O estado da criança (Calmo / Atenção / Possível crise) tem que ser
   entendido em menos de 2 segundos, sem depender de ler texto pequeno nem de
   distinguir cores.
2. Quando há um episódio, a ação ("Estou ciente") e a pista de causa (o
   provável gatilho) ficam juntas do estado, em linguagem simples.
3. A interface não pode aumentar a carga do cuidador: nada piscando, nada
   pulsando, nenhuma cor alarmante quando está tudo bem.

## 2. Direção visual: "Sala calma"

A referência vem dos **ambientes de baixa estimulação** usados no TEA (salas
de regulação sensorial): cores pouco saturadas, superfícies foscas, sem
brilhos nem sombras, e cor apenas onde ela carrega significado. A interface
fica quieta quando está tudo bem e é inconfundível quando não está.

Três princípios guiam todas as telas:

- **Um elemento principal.** A *faixa de estado* da tela Início é um bloco
  largo, de cantos bem arredondados (28 dp), que lembra a própria pulseira e é
  tingido pela cor do nível. Todo o resto do app é discreto.
- **Vermelho e amarelo são reservados para o risco.** A fita do logo é
  vermelha, amarela e azul, e o vermelho e o amarelo são justamente as cores
  de Atenção e Possível crise. Por isso o logo mantém as suas cores, mas a
  interface nunca usa vermelho ou amarelo como decoração, nem em botões como
  "Descartar" ou "Sair" (no visual anterior os dois eram vermelhos). A cor de
  ação vem do azul da fita, dessaturado.
- **Cada texto faz um trabalho.** Títulos em caixa normal (a única caixa alta
  é o logotipo "PUZZLE BAND", que é identidade), frases curtas em voz ativa e
  mensagens de erro que dizem o que aconteceu e o que fazer.

O primeiro rascunho seguia o padrão de app de saúde (um BPM grande com um
coração e uma pilha de cartões brancos com sombra). Ele foi trocado porque a
decisão do cuidador depende do **nível**, não do número: na faixa, a manchete
é o nome do nível, e o BPM vem logo abaixo.

## 3. Paleta

Todos os pares de texto foram medidos com a fórmula de contraste do WCAG 2.1
(critério 1.4.3, mínimo de 4,5:1 para texto normal). Contornos de campos e
marcas de gráfico seguem o critério 1.4.11 (mínimo de 3:1).

### Base

| Papel | Claro | Escuro | Contraste (claro / escuro) |
|---|---|---|---|
| Fundo ("névoa") | `#F0F3F5` | `#11181D` | — |
| Superfície (cartões) | `#FFFFFF` | `#1A232A` | — |
| Superfície de destaque neutro | `#E4E9ED` | `#26313A` | — |
| Texto principal | `#1B2A35` | `#E8EEF2` | 14,7 / 13,6 sobre a superfície |
| Texto secundário | `#4B5B67` | `#AEBBC5` | 7,0 / 8,1 sobre a superfície; 5,7 / 6,8 sobre o destaque |
| Ação (azul ardósia da fita) | `#2D5B86` | `#9DC2E6` | texto do botão 7,1 / 7,9 |
| Contorno (campos, controles) | `#7A8994` | `#6B7A86` | 3,6 / 3,6 (mínimo de 3:1) |
| Divisórias e grade (decorativas) | `#D6DDE2` | `#2E3A44` | — |

### Níveis de risco

| Nível | Texto e ícone | Fundo tingido | Gráfico | Texto sobre o fundo tingido | Gráfico sobre a superfície |
|---|---|---|---|---|---|
| Calmo | `#2B6A4E` | `#E2F1E9` | `#2B9066` | 5,5 | 4,0 |
| Atenção | `#8A5200` | `#FCEFD6` | `#C08A00` | 5,6 | 3,1 |
| Possível crise | `#A3304F` | `#FBE6EC` | `#C73E66` | 5,7 | 4,3 |
| Sem dados | `#56636D` | `#E6EBEE` | — | 5,1 | — |

No tema escuro, os níveis usam `#8FD3AE`, `#F3C46B`, `#F5A3B6` e `#A7B3BC`
sobre fundos tingidos escuros (`#16352A`, `#3A2B10`, `#44192A`, `#263038`),
com contrastes entre 6,3 e 8,4. O texto principal sobre qualquer fundo
tingido fica acima de 11:1 nos dois temas.

- **O vermelho de "Possível crise"** é um framboesa profundo (`#A3304F`)
  sobre um rosado claro, no lugar do vermelho de alarme (`#E53935`). Ele chama
  atenção pela área tingida, pelo tamanho e pelo ícone, não pela saturação.
- **As cores dos gráficos** foram validadas para daltonismo (protanopia,
  deuteranopia e tritanopia) com o validador da skill de visualização de
  dados: separação mínima entre cores vizinhas ΔE ≥ 8 nos dois temas, todas
  com contraste ≥ 3:1 contra a superfície. A primeira tentativa (verde-sálvia,
  âmbar e vermelho mais próximos) falhou nessa checagem e foi ajustada.

## 4. Tipografia

- **Fonte: Atkinson Hyperlegible Next** (Braille Institute of America,
  licença SIL OFL 1.1), desenhada para leitores com baixa visão. Ela
  diferencia bem os caracteres que se confundem (1/l/I, 0/O, 8/B), o que
  importa para BPM e horários lidos às pressas. O zero cortado (0 com barra) é
  um recurso dela para não confundir 0 com O. Os pesos 400, 500, 600 e 700
  estão empacotados em `mobile/assets/fonts/`, com a licença: o app não
  depende de internet para a fonte.
- **Escala** (a escala clássica de *The Elements of Typographic Style*, em
  sp):

  | Tamanho | Peso | Uso |
  |---|---|---|
  | 48 | 600 | BPM ao vivo |
  | 36 | 700 | Nome do nível na faixa |
  | 24 | 700 | Título de tela |
  | 18 | 600 | Título de seção |
  | 16 | 400 | Corpo (maior que os 14 sp padrão do Material 3) |
  | 14 | 400 | Texto secundário, o menor tamanho de leitura |
  | 12 | 500 | Só nos eixos dos gráficos |

- **Glifos ausentes.** A fonte não tem a seta "→" que aparece no texto do
  gatilho enviado pelo site ("45 → 88 dB"). O tema declara a fonte do sistema
  como fallback; no Android a seta vem da fonte de símbolos do sistema.

## 5. Forma, espaçamento e movimento

- **Raios em hierarquia**, em vez de um raio único em tudo: 28 dp na faixa de
  estado, 16 dp nas seções e cartões, 12 dp em botões e campos, e formato de
  pílula nos selos de nível.
- **Sem sombras.** As superfícies se separam pelo tom; a barra de navegação
  tem uma linha de 1 dp.
- **Espaçamento** em múltiplos de 4 dp (4, 8, 12, 16, 24, 32), com margem de
  tela de 20 dp e largura máxima de conteúdo de 560 dp (tablet ou celular
  deitado).
- **Movimento só como resposta a uma mudança**, sempre curto (200 a 400 ms):
  - a cor da faixa transita quando o nível muda;
  - o bloco do episódio entra com transição de tamanho;
  - "Estou ciente", "Confirmar gatilho" e "Descartar" viram uma linha de
    confirmação com fade;
  - um único fade na abertura do Login.
- **Sem movimento:** nada se move sozinho. O coração e o ponto de estado que
  pulsavam sem parar no visual anterior (900 ms, escala de 0,95 a 1,2) foram
  removidos. O BPM troca de valor sem animar, e o gráfico ao vivo não anima a
  cada ponto.
- **Reduzir movimento.** Com "Remover animações" ligado no Android
  (`MediaQuery.disableAnimations`), todas as durações viram zero, inclusive a
  transição entre telas.

## 6. Decisões de acessibilidade para o público do TEA

| Decisão | Por quê | Como foi verificado |
|---|---|---|
| Nível sempre com ícone + palavra + cor; ícones de formatos diferentes (círculo com ✓, triângulo, círculo cheio com !) | Cor nunca sozinha (WCAG 1.4.1), daltonismo, leitura rápida sob estresse | Teste de widget confere ícone e texto de cada nível |
| Contraste AA em todo texto, nos dois temas | Cansaço, sol no celular, baixa visão | `textContrastGuideline` do Flutter em todas as telas, claro e escuro |
| Alvos de toque ≥ 48 × 48 dp; "Estou ciente" com 56 dp e largura total | Mão ocupada, pressa, tremor (WCAG 2.5.5) | `androidTapTargetGuideline` em todas as telas; teste da altura do botão |
| Funciona com a fonte do sistema ampliada até 1,3× | Leitores com baixa visão aumentam a fonte do sistema (WCAG 1.4.4) | Todas as telas em 8 estados com fonte 1,3×: nenhum texto cortado ou sobreposto |
| Leitor de tela: estado, BPM, gatilho e botões com rótulo; **só o nível é anunciado automaticamente**, e só quando muda | O BPM muda 1×/s: se fosse anunciado a cada mudança, o TalkBack falaria um número por segundo | Teste confere os rótulos e que o BPM não é região ao vivo; `labeledTapTargetGuideline` |
| Nada pisca nem pulsa; animações curtas e só como resposta | Sensibilidade sensorial e carga de atenção (WCAG 2.3.3) | Teste: a tela Início "assenta" sem animação em loop; com "reduzir movimento", as durações são zero |
| Vermelho de crise firme, mas não agressivo; vermelho e amarelo só para risco | Alarme visual aumenta o estresse; cor com significado único é aprendida mais rápido | Paleta acima |
| Gatilho em linguagem simples ("Provável gatilho: barulho"), com o texto técnico do site logo abaixo | O cuidador decide rápido ("baixar o som"); o texto técnico continua disponível. A manchete sempre diz "provável": a regra não afirma causa | Teste das manchetes para cada `tipo` de gatilho |
| Cada falha diz o que aconteceu e o que fazer (conectando, sem conexão, painel parado, pulseira desconectada, configuração incompleta) | Estado ambíguo ("—" sem explicação) gera ansiedade | Testes e imagens de cada estado |
| Tema escuro seguindo o sistema | O cuidador olha o celular à noite, muitas vezes no quarto da criança: menos brilho e menos luz no ambiente | Imagens no tema escuro; contraste AA verificado |
| Navegação com rótulos sempre visíveis; nome da aba igual ao título da tela | Ícone sozinho exige memorização | Teste confere "Ajustes" na aba e no título |

## 7. Antes e depois, tela a tela

As imagens do "antes" foram geradas a partir da versão anterior do app (commit
`3dce2b0`), com os mesmos dados de exemplo e o mesmo tamanho de tela
(393 × 852 dp). As do "depois" são as imagens dos testes golden em
`mobile/test/goldens/`.

### Início

| Antes | Depois |
|---|---|
| <img src="imagens/app-antes/inicio_possivel_crise.png" width="280"> | <img src="../mobile/test/goldens/inicio_possivel_crise.png" width="280"> |

- **Antes:**
  - o título "TELA INICIAL" não acrescentava informação;
  - três chips técnicos ficavam sempre visíveis ("Broker: conectado");
  - o nível aparecia duas vezes (no card de alerta e no "Estado Atual"), e o BPM ficava num terceiro card, mais abaixo;
  - o botão "Estou ciente" era vermelho, e o ponto e o coração pulsavam sem parar;
  - textos cinza em 2,7:1.
- **Depois:**
  - uma faixa única com o nível (ícone + palavra), o BPM, o provável gatilho em linguagem simples e o "Estou ciente" em azul, com 56 dp;
  - a linha de conexão só aparece quando há algo a dizer;
  - probabilidade e fonte ficam numa frase discreta abaixo da faixa.

Estados da tela Início:

| Calmo | Atenção | "Estou ciente" enviado |
|---|---|---|
| <img src="../mobile/test/goldens/inicio_calmo.png" width="220"> | <img src="../mobile/test/goldens/inicio_atencao.png" width="220"> | <img src="../mobile/test/goldens/inicio_possivel_crise_ciente.png" width="220"> |

| Sem conexão | Painel (site) e pulseira offline | Configuração incompleta (`env.json`) |
|---|---|---|
| <img src="../mobile/test/goldens/inicio_sem_conexao.png" width="220"> | <img src="../mobile/test/goldens/inicio_painel_e_pulseira_offline.png" width="220"> | <img src="../mobile/test/goldens/inicio_erro_configuracao.png" width="220"> |

No visual anterior, sem conexão o card mostrava "Sem dados" e perguntava "O
painel (site) está aberto?", mesmo quando o problema era a conexão do
celular; o motivo real ficava num chip ("Broker: desconectado"), em termo
técnico (imagem `imagens/app-antes/inicio_sem_conexao.png`).

### Login

| Antes | Depois |
|---|---|
| <img src="imagens/app-antes/login.png" width="280"> | <img src="../mobile/test/goldens/login.png" width="280"> |

- **Antes:**
  - o botão "Entrar" era cinza com texto branco (1,9:1) e parecia desativado;
  - os campos só tinham texto de exemplo, que some ao digitar.
- **Depois:**
  - o botão "Entrar" é azul (7,1:1) e tem 56 dp;
  - os campos têm rótulo fixo;
  - o aviso diz o que acontece: "qualquer usuário e senha entram";
  - o logo aparece num selo, com a fita maior.

### Gráficos

| Antes | Depois |
|---|---|
| <img src="imagens/app-antes/graficos.png" width="280"> | <img src="../mobile/test/goldens/graficos.png" width="280"> |

- **Antes:**
  - duas caixas com número grande e rótulos em caixa alta;
  - grade tracejada;
  - barra amarela de Atenção com 1,7:1 sobre o fundo;
  - legenda com "Calmo", que nunca aparece numa barra, porque todo episódio começa em Atenção.
- **Depois:**
  - o BPM ao vivo vem primeiro, com eixo rotulado em "bpm", marcas a cada minuto e o valor mais recente no fim da linha;
  - o gráfico de 7 dias tem barras finas nas cores validadas, o valor na ponta de cada barra, "Hoje" no último dia, e só Atenção e Possível crise na legenda;
  - uma frase-resumo substitui as caixas ("4 episódios nos últimos 7 dias, 2 de possível crise. Em novembro: 4 episódios.");
  - cada gráfico tem uma descrição completa para leitor de tela.

### Histórico

| Antes | Depois |
|---|---|
| <img src="imagens/app-antes/historico.png" width="280"> | <img src="../mobile/test/goldens/historico.png" width="280"> |

- **Antes:**
  - os detalhes vinham numa linha cinza com pontos ("Duração · Prob. · Pulseira");
  - a avaliação aparecia em cinza claro;
  - o campo de observação ficava sempre aberto em todo cartão;
  - "Descartar" era vermelho;
  - com a fonte em 1,3×, "Confirmar gatilho" ficava espremido contra a borda do botão (imagem `imagens/app-antes/fonte_130_historico.png`).
- **Depois:**
  - cada cartão mostra o selo do nível, a data relativa ("Hoje, 14:32", "Ontem, 18:05"), a duração em destaque e o gatilho em linguagem simples;
  - a avaliação fica numa linha destacada ("Gatilho confirmado por você às 09:20.");
  - a observação fica atrás de "Adicionar observação";
  - os botões têm o mesmo peso visual e ficam um embaixo do outro quando os rótulos não cabem inteiros lado a lado;
  - depois de enviar, o botão escolhido fica cheio com ✓, a linha de avaliação muda com um fade e aparece um aviso com o mesmo verbo do botão ("Gatilho confirmado e enviado ao painel.").

| Lista inteira | Depois de confirmar | Vazio |
|---|---|---|
| <img src="../mobile/test/goldens/historico_completo.png" width="220"> | <img src="../mobile/test/goldens/historico_confirmado.png" width="220"> | <img src="../mobile/test/goldens/historico_vazio.png" width="220"> |

### Ajustes (antes "Configurações", aba "Perfil")

| Antes | Depois |
|---|---|
| <img src="imagens/app-antes/configuracoes.png" width="280"> | <img src="../mobile/test/goldens/ajustes.png" width="280"> |

- **Antes:**
  - uma foto de perfil com ícone de câmera sugeria uma função que não existia;
  - "Privacidade" e "Ajuda e Suporte" tinham seta, mas não abriam nada;
  - "ALERTAS SONOROS" vinha em caixa alta;
  - "Sair da Conta" era vermelho.
- **Depois:**
  - o nome é o mesmo na aba e no título;
  - os grupos são Criança monitorada, Conexões, Alertas e Sobre;
  - cada conexão diz o que significa e mostra o erro, quando houver;
  - "Alertas sonoros" ocupa a linha inteira como área de toque;
  - "Licenças de software" abre as licenças, incluindo a da fonte;
  - "Sair" é neutro.

### Tema escuro e fonte ampliada

| Escuro: Início | Escuro: Histórico | Fonte 1,3×: Início | Fonte 1,3×: Histórico |
|---|---|---|---|
| <img src="../mobile/test/goldens/escuro_inicio_possivel_crise.png" width="170"> | <img src="../mobile/test/goldens/escuro_historico.png" width="170"> | <img src="../mobile/test/goldens/fonte_130_inicio_possivel_crise.png" width="170"> | <img src="../mobile/test/goldens/fonte_130_historico.png" width="170"> |

## 8. Como foi verificado

- `flutter analyze` sem avisos.
- `flutter test` roda os testes que já existiam (parse das mensagens, resumos
  e regras de notificação) e mais dois arquivos:
  - **`test/telas_test.dart`**: comportamento e acessibilidade. Cobre:
    - os rótulos para leitor de tela e qual nó é anunciado;
    - "Estou ciente" e a avaliação enviados, e os avisos quando não há conexão;
    - todos os estados de conexão;
    - contraste AA, alvos de toque e rótulos em todas as telas, nos dois temas;
    - fonte 1,3× em todas as telas e estados;
    - "reduzir movimento";
    - as manchetes do gatilho.
  - **`test/goldens_test.dart`**: 29 imagens das telas em `mobile/test/goldens/`.
    Uma mudança visual não intencional faz o teste falhar. Depois de uma
    mudança intencional, gere as imagens de novo com
    `flutter test --update-goldens test/goldens_test.dart`.
- **Como os testes rodam:** com as fontes reais e um `MqttService` de teste
  (subclasse que só troca os dados lidos pelas telas). Nenhum arquivo de
  `lib/services/`, `lib/models/` ou `lib/config/` foi alterado.

## 9. Limitações e ressalvas

- **Símbolo do quebra-cabeça.** O logo (fita de quebra-cabeça) foi mantido
  como identidade do projeto. Vale registrar que parte da comunidade autista
  critica esse símbolo, por associar o autismo a algo "incompleto" ou a um
  "enigma a resolver", e prefere outros, como o infinito arco-íris
  (neurodiversidade). Um estudo com adultos não autistas encontrou
  associações negativas ligadas a peças de quebra-cabeça (Gernsbacher et al.,
  2018). Numa versão de produto, a escolha do símbolo deveria ser feita junto
  com pessoas autistas e famílias.
- **Sem teste com usuários reais.** As decisões seguem diretrizes (WCAG 2.1,
  Material 3) e o perfil do público, mas não houve teste de usabilidade com
  cuidadores. É o próximo passo natural (por exemplo, medir o tempo para
  identificar o nível e o número de erros no "Estou ciente").
- **Eixos dos gráficos.** O Syncfusion não amplia o texto dos eixos com a
  fonte do sistema. Os valores importantes (último BPM, contagem de cada
  barra, frase-resumo) são widgets de texto e ampliam normalmente.
- **Rótulos de dados do Syncfusion 28.2 no Flutter 3.47.** Os
  `dataLabelSettings` geram um erro ao sair da tela ("disposed RenderObject
  was mutated"). Os valores sobre as barras e no fim da linha são desenhados
  como anotações (`CartesianChartAnnotation`), que não têm o problema.
- **Imagens golden dependem do sistema.** A renderização de fontes muda entre
  Windows, Linux e macOS. As imagens foram geradas no Windows; em outro
  sistema, gere de novo antes de comparar.

## Referências

- W3C. *Web Content Accessibility Guidelines (WCAG) 2.1*. 2018. Critérios
  1.4.1, 1.4.3, 1.4.4, 1.4.11, 2.3.3 e 2.5.5.
- Braille Institute of America. *Atkinson Hyperlegible Next*. Licença SIL Open
  Font License 1.1.
- Bringhurst, R. *The Elements of Typographic Style*. Hartley & Marks.
- Google. *Material Design 3*. m3.material.io.
- Gernsbacher, M. A.; Raimond, A. R.; Stevenson, J. L.; Boston, J. S.; Harp,
  B. Do puzzle pieces and autism puzzle piece logos evoke negative
  associations? *Autism*, v. 22, n. 2, p. 118–125, 2018.
