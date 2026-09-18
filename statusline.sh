#!/usr/bin/env bash
# Status line for Claude Code: context window usage and rate-limit budget left.
#
# Usage: statusline.sh [minimal|full]
#   minimal (default)  ctx | 5h left | spend left
#   full               model | dir | ctx | 5h left | 7d left | spend left | cost
#
# Mode can also be set with CC_STATUSLINE_MODE. The argument wins.
# Session cost in USD is shown only when the account has no subscription rate
# limits, since it means nothing on a plan. Force it with CC_STATUSLINE_COST=1,
# hide it with CC_STATUSLINE_COST=0.
# Optional extras: if ~/.claude/statusline-extra.sh exists it is run and its
# output appended (used for badges from other plugins).
set -u

MODE="${1:-${CC_STATUSLINE_MODE:-minimal}}"
COST="${CC_STATUSLINE_COST:-auto}"
IN=$(cat)

command -v jq >/dev/null || { printf 'statusline: jq not installed'; exit 0; }

printf '%s' "$(jq -r --arg mode "$MODE" --arg cost "$COST" '
  def c(n;s): "\u001b[38;5;" + (n|tostring) + "m" + s + "\u001b[0m";
  def dim(s): c(240; s);
  def k(t): if t >= 1000000 then ((t/1000000*10|floor)/10|tostring) + "M"
            elif t >= 1000 then ((t/1000*10|floor)/10|tostring) + "k"
            else (t|tostring) end;
  def pct(p): (p|floor|tostring) + "%";
  # green under 70% used, orange to 90%, red above
  def hue(p): if p >= 90 then 196 elif p >= 70 then 214 else 108 end;
  def resets(r): (r.resets_at - now) as $s
    | if $s <= 0 then ""
      else " " + dim("(" + (if $s >= 3600 then (($s/3600)|floor|tostring) + "h" else "" end)
                         + ((($s%3600)/60)|floor|tostring) + "m)") end;
  def usd(v): (v * 100 | round) as $c
    | "$" + (($c / 100) | floor | tostring) + "."
          + (($c % 100) | tostring | if length == 1 then "0" + . else . end);
  def budget(txt; r): dim(txt + " ") + c(hue(r.used_percentage); pct(100 - r.used_percentage) + " left");

  ($mode == "full") as $full |
  # on a subscription the plan windows are the real budget, the USD figure is not
  (if $cost == "1" then true elif $cost == "0" then false
   else .rate_limits.five_hour == null end) as $showcost |

  [ (if $full then c(75; .model.display_name) else empty end),

    (if $full then c(244; (.workspace.current_dir | sub("^" + env.HOME; "~"))) else empty end),

    (.context_window as $w
      | dim("ctx ") + c(hue($w.used_percentage);
          k($w.total_input_tokens) + "/" + k($w.context_window_size) + " " + pct($w.used_percentage))),

    (if .rate_limits.five_hour then budget("5h"; .rate_limits.five_hour) + resets(.rate_limits.five_hour) else empty end),

    (if $full and .rate_limits.seven_day then budget("7d"; .rate_limits.seven_day) + resets(.rate_limits.seven_day) else empty end),

    (if .rate_limits.spend_limit then budget("spend"; .rate_limits.spend_limit) else empty end),

    (if $showcost then dim(usd(.cost.total_cost_usd // 0)) else empty end)
  ] | join(c(238; " | "))
' <<<"$IN")"

EXTRA="$HOME/.claude/statusline-extra.sh"
if [ -f "$EXTRA" ]; then
  OUT=$(bash "$EXTRA" <<<"$IN" 2>/dev/null)
  [ -n "$OUT" ] && printf ' %s' "$OUT"
fi
