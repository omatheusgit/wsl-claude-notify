#!/usr/bin/env bash
# Hook de Notification do Claude Code -> toast persistente no Windows.
#
# Recebe o payload do hook em stdin. Monta uma mensagem que diz ONDE a
# aprovacao esta parada, porque com varios agentes rodando "Claude precisa de
# permissao" sozinho nao ajuda.
set -uo pipefail

payload=$(cat 2>/dev/null || echo '{}')

msg=$(printf '%s' "$payload" | jq -r '.message // "Aguardando sua aprovacao"' 2>/dev/null)
[ -z "$msg" ] || [ "$msg" = "null" ] && msg="Aguardando sua aprovacao"

dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir="$PWD"
proj=$(basename "$dir")

# Terminais do herdr (app desktop ou TUI) recebem esse contexto injetado.
onde="$proj"
if [ -n "${HC_TERMINAL_ID:-}" ]; then
  where=""
  command -v hc >/dev/null 2>&1 \
    && where=$(hc get "$HC_TERMINAL_ID" 2>/dev/null | jq -r '.labels.where // .name // empty' 2>/dev/null)
  [ -n "$where" ] && onde="$where" || onde="$proj · $HC_TERMINAL_ID"
elif [ -n "${HERDR_PANE_ID:-}" ]; then
  ws=""
  if command -v herdr >/dev/null 2>&1 && [ -n "${HERDR_WORKSPACE_ID:-}" ]; then
    ws=$(herdr workspace get "$HERDR_WORKSPACE_ID" 2>/dev/null \
         | jq -r '.result.workspace.label // empty' 2>/dev/null)
  fi
  [ -n "$ws" ] && onde="$ws · $HERDR_PANE_ID" || onde="$proj · $HERDR_PANE_ID"
elif [ -n "${TMUX:-}" ]; then
  sess=$(tmux display-message -p '#S' 2>/dev/null)
  [ -n "$sess" ] && onde="$proj · tmux:$sess"
fi

exec "$HOME/.claude/hooks/notify-windows.sh" "Claude Code — $onde" "$msg"
