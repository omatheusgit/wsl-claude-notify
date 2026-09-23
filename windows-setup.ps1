<#
.SYNOPSIS
    Registra o protocolo claudefocus: no Windows, usado pelo botao da notificacao.

.DESCRIPTION
    Precisa de admin. O contexto de ativacao de um toast nao le HKCU nem resolve
    app execution aliases (wt.exe tem 0 byte e e um ReparsePoint), por isso o
    handler vive em HKLM e aponta para wscript.exe, que e um binario real e roda
    o VBScript sem abrir janela nenhuma.

.PARAMETER Hotkey
    Atalho que traz seu terminal de volta, ex. "Ctrl+Alt+F9". Se voce omitir,
    o script ativa a janela do processo em -ProcessName direto.

.PARAMETER ProcessName
    Processo a focar quando nao houver -Hotkey. Padrao: WindowsTerminal.

.EXAMPLE
    .\windows-setup.ps1 -Hotkey "Ctrl+Alt+F9"
    .\windows-setup.ps1
    .\windows-setup.ps1 -Uninstall
#>
param(
    [string]$Hotkey = "",
    [string]$ProcessName = "WindowsTerminal",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Error "Rode como administrador. O handler precisa ir para HKLM: o toast nao le HKCU."
}

$vbsPath = Join-Path $env:LOCALAPPDATA 'claudefocus.vbs'
$regRoot = 'HKLM:\Software\Classes\claudefocus'

if ($Uninstall) {
    Remove-Item $regRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
    Write-Host "Removido." -ForegroundColor Green
    return
}

# "Ctrl+Alt+F9" -> "^%{F9}", o formato do SendKeys.
function ConvertTo-SendKeys([string]$combo) {
    $out = ''
    $key = ''
    foreach ($part in $combo -split '\+') {
        switch ($part.Trim().ToLower()) {
            'ctrl'    { $out += '^' }
            'control' { $out += '^' }
            'alt'     { $out += '%' }
            'shift'   { $out += '+' }
            'win'     { Write-Error "SendKeys nao consegue enviar a tecla Windows. Use outro atalho ou omita -Hotkey." }
            default   { $key = $part.Trim() }
        }
    }
    if (-not $key) { Write-Error "Nao achei a tecla final em '$combo'." }
    if ($key.Length -gt 1) { $out += '{' + $key.ToUpper() + '}' } else { $out += $key.ToLower() }
    return $out
}

if ($Hotkey) {
    $sk = ConvertTo-SendKeys $Hotkey
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

$cmd = '"C:\Windows\System32\wscript.exe" "' + $vbsPath + '"'
New-Item -Path "$regRoot\shell\open\command" -Force | Out-Null
Set-ItemProperty $regRoot -Name '(default)' -Value 'URL:Claude Focus Protocol'
New-ItemProperty $regRoot -Name 'URL Protocol' -Value '' -Force | Out-Null
Set-ItemProperty "$regRoot\shell\open\command" -Name '(default)' -Value $cmd

Write-Host "claudefocus: registrado." -ForegroundColor Green
Write-Host "  modo:    $modo"
Write-Host "  script:  $vbsPath"
Write-Host "  handler: $cmd"
