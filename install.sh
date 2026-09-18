#!/usr/bin/env bash
# Wire statusline.sh into Claude Code settings.
#
# Usage:
#   ./install.sh [minimal|full]   install (default: minimal)
#   ./install.sh --uninstall      remove the statusLine entry
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/statusline.sh"
ARG="${1:-minimal}"

command -v jq >/dev/null || { echo "install: jq is required" >&2; exit 1; }
[ -f "$SETTINGS" ] || { mkdir -p "$(dirname "$SETTINGS")"; echo '{}' > "$SETTINGS"; }
cp "$SETTINGS" "$SETTINGS.bak"

case "$ARG" in
  --uninstall)
    jq 'del(.statusLine)' "$SETTINGS" > "$SETTINGS.tmp"
    mv "$SETTINGS.tmp" "$SETTINGS"
    echo "removed statusLine from $SETTINGS (backup: $SETTINGS.bak)"
    exit 0
    ;;
  minimal|full) ;;
  *) echo "install: mode must be minimal or full" >&2; exit 1 ;;
esac

chmod +x "$SCRIPT"
jq --arg cmd "bash \"$SCRIPT\" $ARG" \
   '.statusLine = {type: "command", command: $cmd, refreshInterval: 30}' \
   "$SETTINGS" > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"

echo "installed $ARG mode in $SETTINGS (backup: $SETTINGS.bak)"
echo -n "preview: "
printf '%s' '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$HOME"'"},"cost":{"total_cost_usd":1.23},"context_window":{"total_input_tokens":45231,"context_window_size":1000000,"used_percentage":4.5},"rate_limits":{"five_hour":{"used_percentage":34,"resets_at":'"$(( $(date +%s) + 9000 ))"'},"seven_day":{"used_percentage":12,"resets_at":'"$(( $(date +%s) + 400000 ))"'}}}' \
  | bash "$SCRIPT" "$ARG"
echo
