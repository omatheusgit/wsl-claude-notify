<#
.SYNOPSIS
    Instala o AutoHotkey v2 e coloca o MouseToggle.ahk para subir com o Windows.

.DESCRIPTION
    Nao precisa de admin: o AutoHotkey instala em modo usuario e o atalho vai
    para a pasta Startup do proprio perfil.

.PARAMETER Source
    Caminho do MouseToggle.ahk. Padrao: o arquivo ao lado deste script.

.EXAMPLE
    .\install-mouse.ps1
    .\install-mouse.ps1 -Uninstall
#>
param(
    [string]$Source = "",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$destDir = Join-Path $env:USERPROFILE 'Documents\scripts'
$destAhk = Join-Path $destDir 'MouseToggle.ahk'
$lnk     = Join-Path ([Environment]::GetFolderPath('Startup')) 'MouseToggle.lnk'
$ahkExe  = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'

function Stop-MouseToggle {
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*MouseToggle.ahk*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($Uninstall) {
    Stop-MouseToggle
    Remove-Item $lnk, $destAhk -Force -ErrorAction SilentlyContinue
    Write-Host "MouseToggle removido. O AutoHotkey continua instalado." -ForegroundColor Green
    Write-Host "Para tirar tambem: winget uninstall AutoHotkey.AutoHotkey"
    return
}

if (-not $Source) { $Source = Join-Path $PSScriptRoot 'MouseToggle.ahk' }
if (-not (Test-Path $Source)) { Write-Error "Nao achei o script em: $Source" }

# --------------------------------------------------------------- AutoHotkey v2
if (Test-Path $ahkExe) {
    Write-Host "  ok  AutoHotkey v2 ja instalado"
} else {
    Write-Host "  ..  instalando AutoHotkey v2 pelo winget"
    winget install --id AutoHotkey.AutoHotkey --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    if (-not (Test-Path $ahkExe)) {
        Write-Error "O winget terminou mas nao achei $ahkExe. Instale manualmente: https://www.autohotkey.com/"
    }
    Write-Host "  ok  AutoHotkey v2 instalado"
}

# -------------------------------------------------------------------- o script
New-Item -ItemType Directory -Path $destDir -Force | Out-Null
Copy-Item $Source $destAhk -Force
Write-Host "  ok  script em $destAhk"

# ---------------------------------------------------------- atalho de startup
# As aspas em Arguments sao obrigatorias: o caminho do perfil costuma ter espaco
# e o AutoHotkey reclamaria de "Script file not found" com o caminho truncado.
$w = New-Object -ComObject WScript.Shell
$s = $w.CreateShortcut($lnk)
$s.TargetPath       = $ahkExe
$s.Arguments        = '"' + $destAhk + '"'
$s.WorkingDirectory = $destDir
$s.Save()
Write-Host "  ok  sobe junto com o Windows"

# ------------------------------------------------------------- subir agora
Stop-MouseToggle
Start-Process $ahkExe -ArgumentList ('"' + $destAhk + '"') -WorkingDirectory $destDir
Start-Sleep -Milliseconds 700

$vivo = Get-Process AutoHotkey64 -ErrorAction SilentlyContinue
if ($vivo) {
    Write-Host "  ok  rodando (PID $($vivo[0].Id))" -ForegroundColor Green
} else {
    Write-Warning "O script nao subiu. Rode manualmente para ver o erro:"
    Write-Warning "  & '$ahkExe' /ErrorStdOut '$destAhk'"
}

Write-Host ""
Write-Host "Falta configurar o mouse:" -ForegroundColor Yellow
Write-Host "  No software da Redragon, cada botao -> dropdown 'Key combination'"
Write-Host "  (NAO 'Macro') -> gravar Ctrl+Alt+F9, Ctrl+Alt+F10 e Ctrl+Alt+F11."
