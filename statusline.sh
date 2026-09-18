#!/usr/bin/env bash
# Status line for Claude Code: context window used and plan budget left.
#
# Usage: statusline.sh [minimal|full] [usage-api]
#   minimal (default)  ctx | 5h left | spend left
#   full               model | dir | ctx | 5h left | 7d left | spend left | cost
#   usage-api          also show the per-model weekly windows (Fable, Opus,
#                      Sonnet) that the status line payload does not carry
#
# Mode can also be set with CC_STATUSLINE_MODE, the API fetch with
# CC_STATUSLINE_USAGE_API=1. Arguments win over the variables.
#
# Session cost in USD is shown only when the account reports no plan rate
# limits, since the dollar figure means nothing on a subscription. Force it with
# CC_STATUSLINE_COST=1, hide it with CC_STATUSLINE_COST=0.
#
# Optional extras: if ~/.claude/statusline-extra.sh exists it is run with the
# same JSON on stdin and its output appended.
set -u

MODE="${CC_STATUSLINE_MODE:-minimal}"
USAGE_API="${CC_STATUSLINE_USAGE_API:-0}"
for arg in "$@"; do
  case "$arg" in
    minimal|full) MODE="$arg" ;;
    usage-api) USAGE_API=1 ;;
  esac
done
COST="${CC_STATUSLINE_COST:-auto}"
IN=$(cat)

command -v jq >/dev/null || { printf 'statusline: jq not installed'; exit 0; }

# Per-model weekly windows come from the endpoint /usage reads, not from the
# status line payload. The cache is served right away and refreshed in the
# background, so drawing the status line never waits on the network.
EXTRA_WINDOWS='[]'
if [ "$USAGE_API" = "1" ]; then
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code-statusline"
  CACHE="$CACHE_DIR/usage.json"
  CREDS="$HOME/.claude/.credentials.json"
  TTL=120

  if [ -f "$CREDS" ] && command -v curl >/dev/null; then
    if [ ! -f "$CACHE" ] || [ "$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))" -gt "$TTL" ]; then
      mkdir -p "$CACHE_DIR"
      (
        TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)
        [ -n "$TOKEN" ] || exit 0
        curl -sS --max-time 5 \
          -H "Authorization: Bearer $TOKEN" \
          -H "Content-Type: application/json" \
          -H "anthropic-beta: oauth-2025-04-20" \
          https://api.anthropic.com/api/oauth/usage \
          -o "$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
      ) >/dev/null 2>&1 &
      disown 2>/dev/null
    fi
  fi

  if [ -f "$CACHE" ]; then
    EXTRA_WINDOWS=$(jq -c '
      def iso: if . == null then null
               else (sub("\\.[0-9]+"; "") | sub("([+-][0-9]{2}:[0-9]{2})$"; "Z") | fromdateiso8601) end;
      [ ((.limits // [])[]
          | select(.kind == "weekly_scoped" and (.scope | type == "string"))
          | {name: .scope, used: .percent, resets_at: (.resets_at | iso)}),
        (if (.seven_day_overage_included | type) == "object" and .seven_day_overage_included.utilization != null
         then {name: "fable", used: .seven_day_overage_included.utilization,
               resets_at: (.seven_day_overage_included.resets_at | iso)}
         else empty end) ]' "$CACHE" 2>/dev/null) || EXTRA_WINDOWS='[]'
    [ -n "$EXTRA_WINDOWS" ] || EXTRA_WINDOWS='[]'
  fi
fi

printf '%s' "$(jq -r --arg mode "$MODE" --arg cost "$COST" --argjson extra "$EXTRA_WINDOWS" '
  def c(n;s): "\u001b[38;5;" + (n|tostring) + "m" + s + "\u001b[0m";
  def dim(s): c(240; s);
  def k(t): if t >= 1000000 then ((t/1000000*10|floor)/10|tostring) + "M"
            elif t >= 1000 then ((t/1000*10|floor)/10|tostring) + "k"
            else (t|tostring) end;
  def pct(p): (p|floor|tostring) + "%";
  # green below 70% used, orange to 90%, red above
  def hue(p): if p >= 90 then 196 elif p >= 70 then 214 else 108 end;
  def clock($s): if $s >= 172800 then (($s/86400)|floor|tostring) + "d"
                 elif $s >= 3600 then (($s/3600)|floor|tostring) + "h" + ((($s%3600)/60)|floor|tostring) + "m"
                 else ((($s%3600)/60)|floor|tostring) + "m" end;
  def resets($at): if $at == null then ""
    else ($at - now) as $s | if $s <= 0 then "" else " " + dim("(" + clock($s) + ")") end end;
  def budget(txt; used; at): dim(txt + " ") + c(hue(used); pct(100 - used) + " left") + resets(at);
  def usd(v): (v * 100 | round) as $c
    | "$" + (($c / 100) | floor | tostring) + "."
          + (($c % 100) | tostring | if length == 1 then "0" + . else . end);

  ($mode == "full") as $full |
  # on a subscription the plan windows are the real budget, the USD figure is not
  (if $cost == "1" then true elif $cost == "0" then false
   else .rate_limits.five_hour == null end) as $showcost |

  [ (if $full then c(75; .model.display_name) else empty end),

    (if $full then c(244; (.workspace.current_dir | sub("^" + env.HOME; "~"))) else empty end),

    (.context_window as $w
      | dim("ctx ") + c(hue($w.used_percentage);
          k($w.total_input_tokens) + "/" + k($w.context_window_size) + " " + pct($w.used_percentage))),

    (if .rate_limits.five_hour
     then budget("5h"; .rate_limits.five_hour.used_percentage; .rate_limits.five_hour.resets_at)
     else empty end),

    (if $full and .rate_limits.seven_day
     then budget("7d"; .rate_limits.seven_day.used_percentage; .rate_limits.seven_day.resets_at)
     else empty end),

    ($extra[] | budget(.name; .used; .resets_at)),

    (if .rate_limits.spend_limit
     then budget("spend"; .rate_limits.spend_limit.used_percentage; .rate_limits.spend_limit.resets_at)
     else empty end),

    (if $showcost then dim(usd(.cost.total_cost_usd // 0)) else empty end)
  ] | join(c(238; " | "))
' <<<"$IN")"

EXTRA="$HOME/.claude/statusline-extra.sh"
if [ -f "$EXTRA" ]; then
  OUT=$(bash "$EXTRA" <<<"$IN" 2>/dev/null)
  [ -n "$OUT" ] && printf ' %s' "$OUT"
fi
