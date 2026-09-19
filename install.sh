#!/usr/bin/env bash
# Wire statusline.sh into Claude Code settings.
#
# Usage:
#   ./install.sh [minimal|full] [usage-api]   install (default: minimal)
#   ./install.sh --uninstall                  remove the statusLine entry
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/statusline.sh" ]; then
  SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh"
  DOWNLOAD=0
else
  SCRIPT="$CLAUDE_DIR/statusline.sh"
  DOWNLOAD=1
fi

MODE="minimal"
USAGE_API=""

command -v jq >/dev/null || { echo "install: jq is required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }

for arg in "$@"; do
  case "$arg" in
    --uninstall)
      cp "$SETTINGS" "$SETTINGS.bak"
      jq 'del(.statusLine)' "$SETTINGS" > "$SETTINGS.tmp"
      mv "$SETTINGS.tmp" "$SETTINGS"
      echo "removed statusLine from $SETTINGS (backup: $SETTINGS.bak)"
      exit 0
      ;;
    minimal|full) MODE="$arg" ;;
    usage-api) USAGE_API=" usage-api" ;;
    *) echo "install: unknown argument $arg" >&2; exit 1 ;;
  esac
done

if [ "$DOWNLOAD" = 1 ]; then
  echo "Downloading statusline.sh to $SCRIPT..."
  curl -fsSL "https://raw.githubusercontent.com/Y-T-G/claude-code-statusline/main/statusline.sh" -o "$SCRIPT"
fi

cp "$SETTINGS" "$SETTINGS.bak"
chmod +x "$SCRIPT"
jq --arg cmd "bash \"$SCRIPT\" $MODE$USAGE_API" \
   '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' \
   "$SETTINGS" > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"

echo "installed $MODE mode${USAGE_API:+ with usage-api} in $SETTINGS (backup: $SETTINGS.bak)"
echo -n "preview: "
printf '%s' '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$HOME"'"},"cost":{"total_cost_usd":1.23},"context_window":{"total_input_tokens":45231,"context_window_size":1000000,"used_percentage":4.5},"rate_limits":{"five_hour":{"used_percentage":22,"resets_at":'"$(( $(date +%s) + 9000 ))"'},"seven_day":{"used_percentage":7,"resets_at":'"$(( $(date +%s) + 400000 ))"'}}}' \
  | bash "$SCRIPT" "$MODE" ${USAGE_API:+usage-api}
echo
