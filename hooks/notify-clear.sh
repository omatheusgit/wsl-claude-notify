#!/usr/bin/env bash
# Remove o toast do Claude Code da tela e da central de notificacoes.
#
# Chamado pelo hook PostToolUse: se voce aprovou a permissao, a notificacao
# nao tem mais razao de existir. O marcador evita subir um PowerShell
# (~300ms) a cada tool call quando nao ha toast nenhum.
set -uo pipefail

source "$HOME/.claude/hooks/notify-common.sh"

[ -f "$TOAST_MARKER" ] || exit 0
rm -f "$TOAST_MARKER"

PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || PS=/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || exit 0

"$PS" -NoProfile -NonInteractive -Command "
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > \$null
[Windows.UI.Notifications.ToastNotificationManager]::History.Remove('$TOAST_TAG','$TOAST_GROUP','$TOAST_APPID')
" >/dev/null 2>&1

exit 0
