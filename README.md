# Claude Code statusline

A one-line status bar for Claude Code. It reads the session JSON on stdin and shows the model, directory, context use, rate limits, cost, and line changes.

Example:

```
✦ Opus 4.8 · 📁 my-project · 🧠 42% ████░░░░░░ 84k/200k · ⏱ 5h 30% ███░░░░░░░ · 🔄 2h 14m to reset · 💰 $1.23 · 📝 +120/-8
```

## Requirements

- `jq` (version 1.7 or later)
- macOS or Linux

## Install

1. Save `statusline.jq` to a fixed path, for example `~/.claude/statusline.jq`.
2. Open `~/.claude/settings.json`.
3. Add this block:

```json
{
  "statusLine": {
    "type": "command",
    "command": "jq -rf \"$HOME/.claude/statusline.jq\""
  }
}
```

4. Start a new Claude Code session. The status bar shows at the bottom.

## Test

Run the script with sample JSON:

```sh
echo '{"model":{"display_name":"Opus 4.8"},"workspace":{"current_dir":"/tmp/demo"},"cost":{"total_cost_usd":1.23}}' | jq -rf statusline.jq
```
