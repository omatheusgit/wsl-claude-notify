#!/usr/bin/env bash
# Instala os hooks no WSL e registra o protocolo claudefocus: no Windows.
#
#   ./install.sh                      # foca a janela do Windows Terminal
#   ./install.sh --hotkey Ctrl+Alt+F9 # dispara seu atalho (ex. botao do mouse)
#   ./install.sh --uninstall
#
# Idempotente: rodar de novo nao duplica hook no settings.json.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

HOTKEY=""
PROCESS="WindowsTerminal"
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hotkey)    HOTKEY="${2:?--hotkey precisa de um valor, ex. Ctrl+Alt+F9}"; shift 2 ;;
    --process)   PROCESS="${2:?--process precisa de um valor}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)           echo "opcao desconhecida: $1" >&2; exit 1 ;;
  esac
done

die() { echo "erro: $*" >&2; exit 1; }
ok()  { echo "  ok  $*"; }

grep -qi microsoft /proc/version 2>/dev/null || die "isto precisa rodar dentro do WSL."
command -v jq >/dev/null || die "instale o jq primeiro: sudo apt install jq"

PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || PS=/mnt/c/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe
[ -x "$PS" ] || die "nao achei o powershell.exe. O /mnt/c esta montado?"

# ---------------------------------------------------------------- desinstalar
if [ "$UNINSTALL" = 1 ]; then
  rm -f "$HOOKS_DIR"/notify-{common,windows,clear,aprovacao}.sh
  ok "hooks removidos"

  if [ -f "$SETTINGS" ]; then
    tmp=$(mktemp)
    jq '.hooks |= with_entries(
          .value |= map(select(
            [.hooks[]?.command] | map(test("notify-(aprovacao|clear)\\.sh")) | any | not
          ))
        ) | .hooks |= with_entries(select(.value | length > 0))' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    ok "hooks retirados do settings.json"
  fi

  echo
  echo "Falta tirar o protocolo do Windows. Rode como administrador:"
  echo "  powershell -ExecutionPolicy Bypass -File \"$(wslpath -w "$REPO/windows-setup.ps1")\" -Uninstall"
  exit 0
fi

# ------------------------------------------------------------------- hooks
mkdir -p "$HOOKS_DIR"
for f in notify-common.sh notify-windows.sh notify-clear.sh notify-aprovacao.sh; do
  install -m 755 "$REPO/hooks/$f" "$HOOKS_DIR/$f"
done
ok "hooks em $HOOKS_DIR"

# ------------------------------------------------------------- settings.json
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS nao e um JSON valido. Conserte antes de continuar."

cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp=$(mktemp)
jq --arg notify "bash $HOOKS_DIR/notify-aprovacao.sh" \
   --arg clear  "bash $HOOKS_DIR/notify-clear.sh" '
  def upsert($event; $cmd; $timeout):
    .hooks[$event] = (
      (.hooks[$event] // [])
      | if any(.[]; [.hooks[]?.command] | index($cmd)) then .
        else . + [{ hooks: [{ type: "command", command: $cmd, timeout: $timeout, async: true }] }]
        end
    );
  (.hooks //= {})
  | upsert("Notification";      $notify; 15)
  | upsert("PostToolUse";       $clear;  10)
  | upsert("UserPromptSubmit";  $clear;  10)
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
ok "settings.json atualizado (backup ao lado)"

# ---------------------------------------------------------- protocolo Windows
# O PowerShell elevado pode nao enxergar \\wsl.localhost; roda de uma copia no %TEMP%.
WIN_TEMP=$("$PS" -NoProfile -Command '[IO.Path]::GetTempPath()' | tr -d '\r')
WIN_PS1="${WIN_TEMP%\\}\\claudefocus-setup.ps1"
cp "$REPO/windows-setup.ps1" "$(wslpath -u "$WIN_PS1")" || die "nao consegui copiar o windows-setup.ps1 para $WIN_PS1"
ARGS="-ExecutionPolicy Bypass -File \`\"$WIN_PS1\`\""
[ -n "$HOTKEY" ] && ARGS="$ARGS -Hotkey \`\"$HOTKEY\`\"" || ARGS="$ARGS -ProcessName \`\"$PROCESS\`\""

echo
echo "Agora o Windows vai pedir elevacao (UAC) para registrar o protocolo claudefocus:."
echo "Sem admin o botao da notificacao nao funciona — o toast nao le HKCU."
read -r -p "Continuar? [S/n] " r
case "${r:-s}" in
  [Nn]*)
    echo
    echo "Sem problema. Rode isto depois, num PowerShell como administrador:"
    echo "  powershell -ExecutionPolicy Bypass -File \"$WIN_PS1\"${HOTKEY:+ -Hotkey \"$HOTKEY\"}"
    exit 0 ;;
esac

INICIO=$(date +%s)
"$PS" -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '$ARGS'" \
  || die "a elevacao falhou ou foi negada."

# Start-Process -Wait nao repassa o exit code do processo elevado: confere se o
# handler existe e se o script que ele chama acabou de ser escrito.
HANDLER=$(/mnt/c/Windows/System32/reg.exe query 'HKLM\Software\Classes\claudefocus\shell\open\command' /ve 2>/dev/null \
  | tr -d '\r' | sed -n 's/.*REG_SZ *//p')
SCRIPT_WIN=$(printf '%s' "$HANDLER" | sed -n 's/.*" "\(.*\)"$/\1/p')
SCRIPT=$([ -n "$SCRIPT_WIN" ] && wslpath -u "$SCRIPT_WIN" 2>/dev/null)
if [ -z "$SCRIPT" ] || [ ! -f "$SCRIPT" ] || [ "$(stat -c %Y "$SCRIPT")" -lt "$INICIO" ]; then
  die "o protocolo nao foi registrado. Rode num PowerShell como administrador:
  powershell -ExecutionPolicy Bypass -File \"$WIN_PS1\"${HOTKEY:+ -Hotkey \"$HOTKEY\"}"
fi
ok "protocolo claudefocus: registrado"
echo "      handler: $HANDLER"
case "$HANDLER" in
  *wscript.exe*) echo "      (wscript: se o botao do toast nao fizer nada, instale o AutoHotkey v2 e rode de novo)" ;;
esac

# ----------------------------------------------------------------- verificar
echo
echo "Instalado. Teste agora:"
echo "  $HOOKS_DIR/notify-windows.sh \"Teste\" \"Clique em Ir para o terminal\""
echo
echo "Reinicie o Claude Code para os hooks entrarem em vigor."
