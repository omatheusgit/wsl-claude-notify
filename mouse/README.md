# 🖱️ MouseToggle — botões extras do mouse como ícones da taskbar

Mapeia os botões adicionais de um **Redragon Storm Pro (M808-KS)** para alternar
aplicativos igual a um ícone fixado na barra de tarefas:

| Estado do app | O que o botão faz |
|---|---|
| Aberto e em foco | Minimiza |
| Aberto atrás de outra janela | Traz para frente |
| Processo vivo, sem janela (bandeja) | Reexibe a janela escondida |
| Fechado de verdade | Abre o aplicativo |

Mapeamento atual:

| Combinação | Aplicativo |
|---|---|
| `Ctrl+Alt+F9` | Windows Terminal (WSL2 / Ubuntu) |
| `Ctrl+Alt+F10` | Microsoft Teams |
| `Ctrl+Alt+F11` | Claude Desktop |
| `Ctrl+Alt+F8` | Windows Terminal — **só foca, nunca minimiza** (ver abaixo) |

> Este é o atalho que o botão da notificação em [`../README.md`](../README.md) usa
> para devolver o foco ao terminal.

## Por que dois componentes

O software da Redragon **só envia teclas** — ele não sabe quais aplicativos estão
abertos, então sozinho não consegue alternar nada. A solução tem duas metades:

1. **Redragon** → cada botão envia uma combinação de teclas improvável.
2. **AutoHotkey** → um script em segundo plano intercepta essa combinação e
   executa a lógica de janela.

Use a função **"Key combination"** do software, **não "Macro"**.

## Instalação

```powershell
.\install-mouse.ps1
```

Não precisa de admin. O script instala o AutoHotkey v2 pelo winget se faltar,
copia o `.ahk` para `Documents\scripts`, cria o atalho na pasta Startup e sobe
o script na hora.

Depois, no software da Redragon: cada botão → dropdown **Key combination** →
gravar `Ctrl+Alt+F9`, `Ctrl+Alt+F10` e `Ctrl+Alt+F11`.

Para remover: `.\install-mouse.ps1 -Uninstall`

<details>
<summary>Passo a passo manual, se preferir</summary>

```powershell
# 1. AutoHotkey v2 (validado na 2.0.28)
winget install --id AutoHotkey.AutoHotkey --source winget `
  --accept-package-agreements --accept-source-agreements --silent

# 2. Script no lugar
$dest = Join-Path $env:USERPROFILE 'Documents\scripts'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item .\MouseToggle.ahk $dest

# 3. Atalho de inicialização automática
$script = Join-Path $dest 'MouseToggle.ahk'
$ahk    = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
$lnk    = Join-Path ([Environment]::GetFolderPath('Startup')) 'MouseToggle.lnk'

$w = New-Object -ComObject WScript.Shell
$s = $w.CreateShortcut($lnk)
$s.TargetPath       = $ahk
$s.Arguments        = '"' + $script + '"'   # aspas obrigatórias: o caminho tem espaço
$s.WorkingDirectory = $dest
$s.Save()

# 4. Subir sem reiniciar
Start-Process $ahk -ArgumentList ('"' + $script + '"') -WorkingDirectory $dest
```

O script exige v2 (`#Requires AutoHotkey v2.0`) — a sintaxe do v1 é incompatível.

</details>

## `Toggle()` e `Focus()`

O script tem duas funções. `Toggle()` é o comportamento de ícone da taskbar, que
**minimiza se a janela já estiver em foco**. É o que você quer num botão do mouse.

`Focus()` nunca minimiza. Existe por causa da notificação: ali "alternar" seria
errado — na borda em que o toast não rouba o foco do terminal, o `Toggle()`
minimizaria exatamente a janela que você pediu para ver. O `Ctrl+Alt+F8` está
mapeado nele e não precisa de botão no mouse.

## Como descobrir os identificadores de um app novo

Duas informações por aplicativo: o **nome do processo** e o **comando de abertura**.

Nome do processo (com o app aberto):

```powershell
Get-Process | Where-Object { $_.MainWindowTitle -ne '' } |
  Select-Object ProcessName, MainWindowTitle, Path | Format-Table -AutoSize
```

Comando de abertura — apps da Microsoft Store não abrem por caminho de `.exe`,
precisam do AppUserModelID:

```powershell
Get-StartApps | Where-Object { $_.Name -match 'Teams|Claude|Terminal' }
```

O resultado vira `shell:AppsFolder\<AppID>`. Valores validados:

| App | Processo | Comando de abertura |
|---|---|---|
| Windows Terminal | `WindowsTerminal.exe` | `shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App` |
| Microsoft Teams | `ms-teams.exe` | `shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams` |
| Claude Desktop | `claude.exe` | `shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude` |

Para adicionar um quarto app, copie uma linha de hotkey e troque os dois campos.

## Armadilhas encontradas (e por que o script é assim)

### Limite de teclas do software da Redragon

`Ctrl+Alt+Shift+F9` é rejeitado com *"The number of key has reached its maximum"*.
O software aceita no máximo **3 teclas** (2 modificadores + 1). Por isso a escolha
foi `Ctrl+Alt` + tecla de função.

### Segunda instância de app Electron

Teams e Claude são Electron e continuam vivos em segundo plano depois que a janela
fecha — nesse estado `WinExist()` retorna zero. A primeira versão do script chamava
`Run()` nesse caso e tentava subir uma **segunda instância**, o que o Electron
recusa com erro de "outro aplicativo está usando".

Por isso o `Toggle()` testa `ProcessExist()` **antes** de considerar `Run()`, e no
caso "processo vivo sem janela" usa `DetectHiddenWindows` + `WinShow` em vez de
relançar.

### Ordem de execução no AutoHotkey

A seção de auto-execução termina na **primeira definição de hotkey**. Qualquer
código de inicialização precisa estar acima das linhas `^!F9::`, senão nunca roda.

### Caminhos com espaço

`C:\Users\Seu Nome\...` tem espaço. `Start-Process -ArgumentList` **não** adiciona
aspas sozinho — sem elas o AutoHotkey reclama *"Script file not found"* com o
caminho truncado em `C:\Users\Seu`. Sempre passe o caminho entre aspas.

### `/validate` não existe no v2.0.28

Essa flag retorna exit code 2 independentemente do conteúdo do script, então não
serve para checar sintaxe. Para diagnosticar, rode o script de verdade e capture a
saída com `/ErrorStdOut`.

## Diagnóstico

| Sintoma | Causa provável |
|---|---|
| Nada acontece, nem pelo teclado | Script não está rodando, ou outro app captura a combinação |
| Funciona no teclado, não no mouse | Mapeamento errado no software da Redragon |
| Funciona, mas o app errado responde | `ahk_exe` desatualizado — o executável mudou de nome |
| Erro ao abrir o app | Lógica de segunda instância (ver armadilhas acima) |

Verificar se o script está no ar:

```powershell
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Select-Object Id, ProcessName
```

Logging temporário, se um botão parar de funcionar:

```autohotkey
Log(msg) {
    FileAppend(FormatTime(, "HH:mm:ss") " | " msg "`n", A_ScriptDir "\MouseToggle.log")
}
```

Chame `Log(...)` dentro de `Toggle()` e acompanhe o arquivo em
`Documents\scripts\MouseToggle.log`.

## Manutenção

**Depois de editar o script**, é preciso recarregar: ícone do AutoHotkey na bandeja
→ botão direito → *Reload Script*. Editar o arquivo não tem efeito sozinho.

**Janelas em modo administrador não recebem os atalhos.** O AutoHotkey roda sem
elevação, então quando o foco está num app elevado o comando não passa. Se isso
incomodar, marque o atalho da inicialização para rodar como administrador.

**Apps da Store podem trocar de identificador** numa atualização grande. Se um
botão parar de responder depois de uma atualização do Teams ou do Claude, rode de
novo os comandos da seção "Como descobrir os identificadores".

## Nota sobre o botão "polling rate switch"

Por padrão o botão 8 do Storm Pro vem com a função *polling rate switch*, que cicla
a taxa de reporte do mouse (125 / 250 / 500 / 1000 Hz). É seguro reaproveitar o
botão: o valor fixo se define no campo **USB Polling** do próprio software da
Redragon. Recomendado deixar em **1000 Hz**.
