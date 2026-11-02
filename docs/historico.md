# Histórico de episódios

Código: `frontend/src/model/episodes.js` (lógica pura),
`frontend/src/hooks/useEpisodeMonitor.js` (ligação com o dashboard) e
`frontend/src/components/EpisodeHistory.jsx` (tela).
Testes: `frontend/src/model/episodes.test.js`.

O histórico aparece no dashboard logo abaixo do gráfico, nos dois modos
(Simulador manual e Pulseira MQTT).

## O que é um episódio

- **Começa** na primeira leitura em que o nível do modelo sai de
  `baixo_risco` (vai para `atencao` ou `alto_risco`). Nesse instante é
  calculado o provável gatilho ([gatilho.md](gatilho.md)).
- **Termina** quando o nível volta para `baixo_risco` e **permanece** assim
  por pelo menos 30 s seguidos (histerese). Uma queda curta, como 10 s em
  baixo risco seguidos de outra subida, continua sendo o mesmo episódio, para
  não partir uma crise em vários pedaços. O `fim` registrado é o instante em
  que o nível voltou ao normal, não o fim dos 30 s de confirmação.
- **Interrompido**: se o monitoramento para no meio (botão "Reiniciar buffer",
  troca da fonte de dados, página fechada ou recarregada), o episódio é
  fechado com o que se sabe até ali e marcado como `interrompido`.

Enquanto não termina, o episódio aparece como "em andamento" e a duração
parcial é mostrada. O tempo é contado em leituras, 1 por segundo (mesma
premissa do modelo). Nas velocidades 2x e 4x do simulador manual, a duração
é a do sinal simulado.

## Campos guardados

| Campo | Conteúdo |
|---|---|
| `id` | Identificador do episódio |
| `crianca` | `childId` da pulseira (ex.: `C01`) ou `simulada` no simulador manual |
| `fonte` | `manual` ou `mqtt` |
| `inicio` / `fim` | Data e hora (ISO 8601); `fim` vazio enquanto está em andamento |
| `duracao_s` | Duração em segundos |
| `encerramento` | `normalizou`, `interrompido` ou vazio (em andamento) |
| `nivel_maximo` | `atencao` ou `alto_risco` |
| `probabilidade_maxima` | Maior probabilidade estimada pelo modelo no episódio (0–1) |
| `gatilho` | Objeto completo da regra de gatilho (tipo, texto, linha de base, detalhes por sinal) |
| `avaliacao_cuidador` | `pendente`, `confirmado` ou `descartado` |
| `observacao` | Texto livre opcional (até 200 caracteres) |

## Avaliação do cuidador

Cada episódio tem os botões **Confirmar gatilho** e **Descartar**, além de
um campo curto de observação (ex.: "sirene da escola tocou antes").

- Clicar no botão já ativo desfaz a escolha e volta para `pendente`.
- O estado aparece em texto e ícone ("✓ confirmado pelo cuidador",
  "✕ descartado pelo cuidador", "○ pendente"), não só pela cor. Os botões
  usam `aria-pressed`.
- O cuidador pode avaliar um episódio ainda em andamento; a avaliação é
  preservada enquanto o episódio continua sendo atualizado.

A avaliação não altera o modelo nem a regra: é um registro para o cuidador
(e para o TCC) de quantas indicações fizeram sentido na prática. É a base
para recalibrar os limites da regra com dados reais no futuro.

## Resumo de padrões

No topo do histórico há um resumo **por criança**:

- total de episódios e duração média (só dos episódios encerrados
  normalmente; os interrompidos têm duração parcial);
- distribuição dos gatilhos, por exemplo "Ruído como provável gatilho:
  7 de 10 episódios · 3 confirmados pelo cuidador". Um episódio com
  `ruido_e_luminosidade` conta nas duas linhas;
- contagem das avaliações: confirmados, descartados e pendentes.

## Exportar CSV

O botão **Exportar CSV** baixa `puzzleband_historico_AAAAMMDD_HHMMSS.csv`
com todos os episódios. O formato segue o padrão do Excel em português:

- separador `;` e vírgula decimal (`0,873`);
- UTF-8 com BOM (os acentos abrem corretamente no Excel);
- datas no horário local, `AAAA-MM-DD HH:MM:SS`;
- textos começando com `=`, `+`, `-` ou `@` recebem um `'` na frente, para
  o Excel não interpretar como fórmula.

Colunas: `id`, `crianca`, `fonte`, `inicio`, `fim`, `duracao_s`,
`encerramento`, `nivel_maximo`, `probabilidade_maxima`, `gatilho_tipo`,
`gatilho_texto`, `baseline_confiavel`, `fisiologia_sinal`, `ruido_status`,
`ruido_linha_base_db`, `ruido_pico_db`, `ruido_antecedencia_s`,
`luz_status`, `luz_linha_base_lux`, `luz_pico_lux`, `luz_variacao_pct`,
`luz_antecedencia_s`, `avaliacao_cuidador`, `observacao`.

Para abrir no Python: `pd.read_csv(arquivo, sep=';', decimal=',')`.

## Limpar histórico

O botão **Limpar histórico** abre uma confirmação na própria tela (sem
janela do navegador): "Sim, apagar histórico" ou "Cancelar" (ou a tecla Esc).
Apagar remove todos os episódios deste navegador, inclusive o que estiver em
andamento, e não pode ser desfeito. Exporte o CSV antes se quiser guardar.

## Persistência

- Guardado no `localStorage` do navegador, na chave `puzzleband_historico`.
- Limite de 200 episódios: ao passar disso, os mais antigos saem.
- Leitura e escrita ficam dentro de `try/catch`. Se o navegador bloquear o
  armazenamento (modo privado, cota cheia, cookies bloqueados), o histórico
  continua funcionando só em memória e a tela mostra um aviso. Dados salvos
  corrompidos são ignorados.

## Privacidade (LGPD)

- **Os dados ficam só no navegador.** O histórico não é enviado a nenhum
  servidor. Ele existe apenas no `localStorage` do computador ou celular
  em que o dashboard foi aberto.
- **Minimização** (LGPD, art. 6º, III – princípio da necessidade): o
  histórico guarda só o resumo de cada episódio (horários, nível,
  probabilidade, gatilho e avaliação), não as leituras brutas dos sensores.
  A criança é identificada por um código (`C01`), não pelo nome.
- **Dados sensíveis e de crianças.** Informações de saúde são dados pessoais
  sensíveis (art. 5º, II) e o tratamento de dados de crianças exige
  consentimento específico de um dos pais ou responsável (art. 14). Num uso
  real, isso deve ser coletado antes do monitoramento.
- **Eliminação**: o próprio cuidador apaga tudo com "Limpar histórico".
- **Cuidados**: o `localStorage` não é criptografado. Qualquer pessoa com
  acesso ao mesmo navegador e usuário do sistema operacional consegue ver os
  dados, então evite computadores compartilhados. O CSV exportado vira um
  arquivo comum e deve ser guardado com o mesmo cuidado.
- **Alertas MQTT**: no modo Pulseira, cada alerta publicado no broker (como
  já acontecia antes) passa a levar também o objeto do gatilho. É o mesmo
  canal dos alertas existentes; o histórico em si continua só no navegador.
