# Desbostificar

Script de otimização do Windows 11 feito para **este PC**:
Ryzen 5 5500, RTX 3060, 16 GB, Gigabyte A520M DS3H, Windows 11 Home 25H2.

## Como usar

1. Coloque `Desbostificar.ps1` e `EXECUTAR-Desbostificar.bat` na mesma pasta.
2. Abra o `Desbostificar.ps1` no Bloco de Notas e revise a seção **1. CONFIGURAÇÃO**
   (Xbox, OneDrive, Teams, Copilot, Widgets e impressora).
3. Dê dois cliques em `EXECUTAR-Desbostificar.bat` e aceite o aviso de administrador.
4. O script **abre em modo SIMULAÇÃO**. Escolha `1` (Leve) e leia o que ele faria.
5. Se estiver tudo certo, tecle `S` para mudar para APLICAR e escolha o nível de novo.
6. Reinicie o PC no final.

Comece pelo **Leve**, use uns dias e depois passe para o **Médio**. O **Agressivo** é opcional.

## Níveis

| Nível | O que faz |
|---|---|
| **1 Leve** | Telemetria e propagandas desligadas, Copilot/Widgets fora, apps-lixo removidos (Notícias, Clima, Paciência, Clipchamp, "Microsoft 365"...). Edge, Chrome, µTorrent, Roblox, Epic, EA e Riot Client param de abrir no boot. Game DVR desligado, Modo de Jogo ligado, plano de energia ajustado. Limpa temporários e o lixo do Windows Update. |
| **2 Médio** | Tudo do Leve, mais: Steam/Discord/Notion/Figma Agent/Teams fora do boot, serviços inúteis em Manual, tarefas de telemetria desligadas, Bing fora do Iniciar e mais apps removidos (To Do, novo Outlook, Dev Home, Vincular ao Celular...). Também limpa cache de Chrome/Edge/Discord/Steam e roda o DISM nos componentes. Passa para o plano Alto desempenho. |
| **3 Agressivo** | Tudo do Médio, mais: Desempenho Máximo, apps removidos também da imagem do Windows, todos os apps da Microsoft sem segundo plano, `DISM /ResetBase` e caches do npm/pip/NuGet. |
| **4 Só limpeza** | Só a limpeza de arquivos. |
| **5 Desfazer tudo** | Volta cada alteração ao valor que tinha antes. |
| **6 Relatório** | Só leitura: discos, inicialização e pontos de atenção. |

## O que o script NUNCA toca

Windows Update, Microsoft Defender/Firewall/SmartScreen, drivers (NVIDIA, AMD, Realtek,
Wacom, Corsair, Logitech), Microsoft Store, Riot Vanguard, WSL, Gaming Services/Xbox Identity
(o Minecraft e o Game Pass precisam deles), iCUE e G HUB na inicialização.

Também não limpa de propósito o **Prefetch** (apagar deixa o boot mais lento) nem o **cache de
shaders** da NVIDIA/Steam (apagar causa travadas nas primeiras partidas).

## Onde ficam os registros

- `C:\Desbostificar\desfazer.jsonl` guarda cada alteração com o valor antigo, e o "Desfazer" usa este arquivo.
- `C:\Desbostificar\logs\` tem um log por execução (as simulações também ficam registradas).
- Antes de aplicar, o script cria um ponto de restauração ("Desbostificar: ...").
  Para usar: Win+R, digite `rstrui`.

## Sem o menu

```powershell
.\Desbostificar.ps1 -Nivel Medio            # simula
.\Desbostificar.ps1 -Nivel Medio -Aplicar   # aplica
.\Desbostificar.ps1 -Nivel Desfazer -Aplicar
```
