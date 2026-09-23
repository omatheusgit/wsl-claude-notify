#!/usr/bin/env bash
# Dispara um toast PERSISTENTE no Windows a partir do WSL.
#
#   notify-windows.sh "titulo" "mensagem"
#
# Usa scenario="reminder": o toast fica na tela ate ser clicado ou dispensado,
# em vez de sumir em 5s. Nao precisa do BurntToast — XML puro via
# Windows.UI.Notifications.
#
# O toast leva tag/group fixos para que notify-clear.sh consiga remove-lo
# depois. Um watcher em background remove sozinho quando o Windows Terminal
# volta ao foco.
set -uo pipefail

TITULO="${1:-Claude Code}"
MENSAGEM="${2:-Aguardando sua aprovacao}"

PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || PS=/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || exit 0

source "$HOME/.claude/hooks/notify-common.sh"

# Segundos antes de o watcher comecar a olhar o foco. Sem isso, se voce ja
# estiver no terminal o toast sumiria antes de voce ouvir o som.
GRACE=${CLAUDE_TOAST_GRACE:-4}
# Depois disso o watcher desiste e o toast fica ate voce clicar.
TIMEOUT_MIN=${CLAUDE_TOAST_TIMEOUT_MIN:-20}

# Escapa o que quebraria o XML.
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
T=$(esc "$TITULO")
M=$(esc "$MENSAGEM")

"$PS" -NoProfile -NonInteractive -Command "
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > \$null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime] > \$null
\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
\$xml.LoadXml(@'
<toast scenario=\"reminder\" launch=\"claudefocus:\" activationType=\"protocol\">
  <visual>
    <binding template=\"ToastGeneric\">
      <text>$T</text>
      <text>$M</text>
    </binding>
  </visual>
  <audio src=\"ms-winsoundevent:Notification.Looping.Alarm2\" loop=\"false\"/>
  <actions>
    <action content=\"Ir para o terminal\" arguments=\"claudefocus:\" activationType=\"protocol\"/>
    <action content=\"Dispensar\" arguments=\"dismiss\" activationType=\"system\"/>
  </actions>
</toast>
'@)
\$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml
\$toast.Tag = '$TOAST_TAG'
\$toast.Group = '$TOAST_GROUP'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$TOAST_APPID').Show(\$toast)
" >/dev/null 2>&1

touch "$TOAST_MARKER"

# Watcher: remove o toast quando o Windows Terminal ganhar foco. Desacoplado do
# processo do hook (setsid) para sobreviver ao timeout do hook.
setsid bash -c '
"$1" -NoProfile -NonInteractive -Command "$2" >/dev/null 2>&1
rm -f "$3"
' _ "$PS" "
Add-Type -Namespace ClaudeW -Name Fg -MemberDefinition @'
[DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
[DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr h, out int p);
'@
Start-Sleep -Seconds $GRACE
\$deadline = (Get-Date).AddMinutes($TIMEOUT_MIN)
while ((Get-Date) -lt \$deadline) {
  \$h = [ClaudeW.Fg]::GetForegroundWindow()
  \$owner = 0
  [void][ClaudeW.Fg]::GetWindowThreadProcessId(\$h, [ref]\$owner)
  \$p = Get-Process -Id \$owner -ErrorAction SilentlyContinue
  if (\$p -and \$p.ProcessName -eq 'WindowsTerminal') {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > \$null
    [Windows.UI.Notifications.ToastNotificationManager]::History.Remove('$TOAST_TAG','$TOAST_GROUP','$TOAST_APPID')
    break
  }
  Start-Sleep -Milliseconds 700
}
" "$TOAST_MARKER" >/dev/null 2>&1 &

exit 0
