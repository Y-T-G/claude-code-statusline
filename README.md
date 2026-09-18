# claude-code-statusline

A status line for [Claude Code](https://code.claude.com) that shows how much context window
you have used and how much of your plan budget is left.

```
ctx 45.2k/1M 4% | 5h 66% left (2h29m)
```

Two modes:

| Mode | Fields |
|------|--------|
| `minimal` (default) | context window, 5 hour budget left, spend limit left when one applies |
| `full` | model, directory, context window, 5 hour budget left, 7 day budget left, spend limit left, session cost |

The percentages are colored: green below 70% used, orange to 90%, red above.

Session cost in USD is hidden when the account reports plan rate limits, because the
dollar figure means nothing on a subscription. It shows for API key and Bedrock or
Vertex usage. Override with `CC_STATUSLINE_COST=1` or `CC_STATUSLINE_COST=0`.

## Install

Needs `bash` and `jq`.

```bash
git clone https://github.com/Y-T-G/claude-code-statusline.git
cd claude-code-statusline
./install.sh            # minimal mode
./install.sh full       # full mode
```

The installer writes the `statusLine` entry in `~/.claude/settings.json` and keeps a
backup at `~/.claude/settings.json.bak`. To remove it:

```bash
./install.sh --uninstall
```

To wire it by hand instead:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/path/to/claude-code-statusline/statusline.sh\" minimal",
    "refreshInterval": 30
  }
}
```

`refreshInterval` keeps the reset countdown ticking. Claude Code also redraws the
status line whenever token usage changes.

## Where the numbers come from

Claude Code passes a JSON payload to the status line command on stdin. This script reads:

| Field | Used for |
|-------|----------|
| `context_window.total_input_tokens`, `.context_window_size`, `.used_percentage` | the `ctx` field |
| `rate_limits.five_hour` | 5 hour budget left and reset countdown |
| `rate_limits.seven_day` | 7 day budget left and reset countdown |
| `rate_limits.spend_limit` | spend limit left, present only on gateway overage |
| `cost.total_cost_usd` | session cost |

The rate limit numbers are the same ones `/usage` reports. Fields that the payload does
not carry are skipped, so an API key session shows context and cost only.

## Adding your own field

If `~/.claude/statusline-extra.sh` exists, it is run with the same JSON on stdin and its
output is appended. Example that adds a git branch:

```bash
#!/usr/bin/env bash
git branch --show-current 2>/dev/null
```

## License

MIT
