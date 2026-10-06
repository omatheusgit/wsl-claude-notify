<#
.SYNOPSIS
    Registra o protocolo claudefocus: no Windows, usado pelo botao da notificacao.

.DESCRIPTION
    Precisa de admin. O contexto de ativacao de um toast nao le HKCU nem resolve
    app execution aliases (wt.exe tem 0 byte e e um ReparsePoint), por isso o
    handler vive em HKLM e aponta para um binario real.

    Se o AutoHotkey v2 estiver instalado, o handler e o AutoHotkey64.exe com um
    .ahk. Senao, cai para wscript.exe com um .vbs. Alguns builds do Windows 11
    recusam, no clique do toast, handlers que ficam em System32 (wscript, cmd,
    notepad...) sem mostrar erro nenhum; o AutoHotkey fica fora de System32 e passa.

.PARAMETER Hotkey
    Atalho que traz seu terminal de volta, ex. "Ctrl+Alt+F9". Se voce omitir,
    o script ativa a janela do processo em -ProcessName direto.

.PARAMETER ProcessName
    Processo a focar quando nao houver -Hotkey. Padrao: WindowsTerminal.

.PARAMETER Handler
    auto (padrao): AutoHotkey se achar, senao wscript. ahk ou wscript forcam um deles.

.EXAMPLE
    .\windows-setup.ps1 -Hotkey "Ctrl+Alt+F9"
    .\windows-setup.ps1
    .\windows-setup.ps1 -Handler wscript
    .\windows-setup.ps1 -Uninstall
#>
param(
    [string]$Hotkey = "",
    [string]$ProcessName = "WindowsTerminal",
    [ValidateSet('auto', 'ahk', 'wscript')]
    [string]$Handler = 'auto',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Error "Rode como administrador. O handler precisa ir para HKLM: o toast nao le HKCU."
}

$vbsPath = Join-Path $env:LOCALAPPDATA 'claudefocus.vbs'
$ahkPath = Join-Path $env:LOCALAPPDATA 'claudefocus.ahk'
$regRoot = 'HKLM:\Software\Classes\claudefocus'

if ($Uninstall) {
    Remove-Item $regRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $vbsPath, $ahkPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removido." -ForegroundColor Green
    return
}

function Find-AutoHotkey {
    $candidatos = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
    )
    $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# "Ctrl+Alt+F9" -> modificadores + tecla, no formato pedido ($mods mapeia cada modificador).
function ConvertTo-Combo([string]$combo, [hashtable]$mods) {
    $out = ''
    $key = ''
    foreach ($part in $combo -split '\+') {
        $p = $part.Trim().ToLower()
        if ($p -eq 'control') { $p = 'ctrl' }
        if ($mods.ContainsKey($p)) {
            if ($null -eq $mods[$p]) { Write-Error "Esse handler nao consegue enviar a tecla '$part'. Use outro atalho ou omita -Hotkey." }
            $out += $mods[$p]
        } else {
            $key = $part.Trim()
        }
    }
    if (-not $key) { Write-Error "Nao achei a tecla final em '$combo'." }
    if ($key.Length -gt 1) { $out += '{' + $key.ToUpper() + '}' } else { $out += $key.ToLower() }
    return $out
}

$ahkExe = $null
if ($Handler -ne 'wscript') {
    $ahkExe = Find-AutoHotkey
    if (-not $ahkExe -and $Handler -eq 'ahk') {
        Write-Error "AutoHotkey v2 nao encontrado. Instale (mouse\install-mouse.ps1 instala) ou use -Handler wscript."
    }
}

if ($ahkExe) {
    if ($Hotkey) {
        $send = ConvertTo-Combo $Hotkey @{ ctrl = '^'; alt = '!'; shift = '+'; win = '#' }
        # SendLevel 1: sem isso, hotkeys de outros scripts AutoHotkey ignoram a tecla enviada.
        $ahk = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
SendLevel 1
Send "$send"
"@
        $modo = "atalho $Hotkey (AutoHotkey Send: $send)"
    } else {
        $ahk = @"
#Requires AutoHotkey v2.0
#NoTrayIcon
win := "ahk_exe $ProcessName.exe"
if WinExist(win) {
    if (WinGetMinMax(win) = -1)
        WinRestore(win)
    WinActivate(win)
}
"@
        $modo = "WinActivate no processo $ProcessName (AutoHotkey)"
    }
    [System.IO.File]::WriteAllText($ahkPath, $ahk, (New-Object System.Text.UTF8Encoding $false))
    Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
    $script = $ahkPath
    $cmd = '"' + $ahkExe + '" "' + $ahkPath + '"'
} else {
    if ($Hotkey) {
        $sk = ConvertTo-Combo $Hotkey @{ ctrl = '^'; alt = '%'; shift = '+'; win = $null }
        $vbs = @"
Set wshell = CreateObject("WScript.Shell")
wshell.SendKeys "$sk"
"@
        $modo = "atalho $Hotkey (SendKeys: $sk)"
    } else {
        $vbs = @"
Set wshell = CreateObject("WScript.Shell")
Set oProcs = GetObject("winmgmts:").ExecQuery("SELECT * FROM Win32_Process WHERE Name='$ProcessName.exe'")
For Each oProc In oProcs
    wshell.AppActivate oProc.ProcessId
    Exit For
Next
"@
        $modo = "AppActivate no processo $ProcessName"
    }
    # WriteAllText com UTF8 sem BOM: o VBScript quebra com "caractere invalido" se o BOM entrar.
    [System.IO.File]::WriteAllText($vbsPath, $vbs, (New-Object System.Text.UTF8Encoding $false))
    Remove-Item $ahkPath -Force -ErrorAction SilentlyContinue
    $script = $vbsPath
    $cmd = '"C:\Windows\System32\wscript.exe" "' + $vbsPath + '"'
    Write-Warning "Usando wscript.exe. Se o botao do toast nao fizer nada, instale o AutoHotkey v2 e rode de novo."
}

New-Item -Path "$regRoot\shell\open\command" -Force | Out-Null
Set-ItemProperty $regRoot -Name '(default)' -Value 'URL:Claude Focus Protocol'
New-ItemProperty $regRoot -Name 'URL Protocol' -Value '' -Force | Out-Null
Set-ItemProperty "$regRoot\shell\open\command" -Name '(default)' -Value $cmd

Write-Host "claudefocus: registrado." -ForegroundColor Green
Write-Host "  modo:    $modo"
Write-Host "  script:  $script"
Write-Host "  handler: $cmd"
