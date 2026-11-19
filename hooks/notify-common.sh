#!/usr/bin/env bash
# Constantes compartilhadas entre notify-windows.sh e notify-clear.sh.
# O tag/group identificam o toast no historico do Windows; sem eles nao ha
# como remove-lo programaticamente.

TOAST_TAG='claudecode'
TOAST_GROUP='claudecode'

# AppID do PowerShell: existe em qualquer Windows, evita registrar um app novo.
TOAST_APPID='{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

# Marcador de "ha um toast na tela". Evita que o PostToolUse suba um PowerShell
# a cada tool call quando nao ha nada para limpar.
TOAST_MARKER="${XDG_RUNTIME_DIR:-/tmp}/claude-toast.active"

# Processo cuja janela, ao ganhar foco, limpa o toast. O install.sh grava o
# --process escolhido em notify.conf.
TOAST_FOCUS_PROCESS='WindowsTerminal'
[ -f "$HOME/.claude/hooks/notify.conf" ] && . "$HOME/.claude/hooks/notify.conf"
