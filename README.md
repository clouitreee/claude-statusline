# claude-statusline

A configurable status bar for [Claude Code](https://claude.ai/code) that shows model, context, git state, and time in a persistent visual segment bar.

```
 CLAUDE:SNT   LOCAL   main   SAFE   14:32
```

```
 CLAUDE:SNT   PROD   feature/auth*   LIVE   14:32
```

---

## Features

- **Model segment** — shows active model short name (SNT/OPS/HKU) + 1M context flag
- **Context segment** — host alias (if mapped) or project pattern match, falls back to LOCAL
- **Git segment** — branch name (truncated), dirty indicator `*`, ahead/behind in debug mode
- **State segment** — `LIVE` (red) when on production host or production branch, `SAFE` otherwise
- **Time segment** — current `HH:MM` in ops/debug modes
- **Two styles** — `flat` (default) or `powerline` (▶ transitions, no Nerd Font needed)
- **Three modes** — `focus` (minimal), `ops` (default), `debug` (+ CWD + ahead/behind)

---

## Requirements

- Bash 4+ (macOS ships Bash 3 — install via `brew install bash` or use the system `sh`)
- `jq` — for parsing Claude Code's JSON input
- `git` — for branch/dirty detection
- Claude Code with statusLine support

---

## Installation

```bash
git clone https://github.com/yourusername/claude-statusline.git
cd claude-statusline
bash install.sh
```

The installer:
1. Copies `statusline.sh` to `~/.claude/statusline.sh`
2. Patches `~/.claude/settings.json` with the statusLine command
3. Backs up any existing files before overwriting

### Manual installation

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

---

## Configuration

All configuration is done via environment variables — no config files, no edits to the script.

Add these to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

### Style and mode

```bash
export CLAUDE_SL_STYLE=powerline         # flat (default) or powerline
export CLAUDE_STATUSLINE_MODE=focus      # focus | ops (default) | debug
```

| Mode | Segments shown |
|------|---------------|
| `focus` | FE:MODEL, CONTEXT, GIT |
| `ops` | FE:MODEL, CONTEXT, GIT, STATE, TIME |
| `debug` | FE:MODEL, CONTEXT, GIT, STATE, TIME, CWD, ahead/behind |

### Server host mapping

Map your server hostnames to short aliases. Hosts mapped to `PROD` or `LIVE` automatically trigger the red `LIVE` state indicator.

```bash
# Single server
export STATUSLINE_HOST_MAP="myserver=PROD"

# Multiple servers
export STATUSLINE_HOST_MAP="web-01=PROD db-01=PROD devbox=DEV staging=STAGE"
```

Without any mapping, all hosts show as `LOCAL`.

### Project context detection

Show a custom label when Claude Code is working inside a specific directory tree.

```bash
# Match by path pattern (regex)
export STATUSLINE_PROJECT_PATTERN="acme|~/work/acme"
export STATUSLINE_PROJECT_LABEL="ACME"         # shown in context segment
export STATUSLINE_ACCENT_COLOR=127             # 256-color number for segment bg
```

When the current working directory matches `STATUSLINE_PROJECT_PATTERN`, the context segment shows your custom label instead of `LOCAL`.

### Production/live detection

Controls when the `LIVE` (red) indicator appears. Checked against CWD path and branch name.

```bash
export STATUSLINE_LIVE_PATTERN="live|prod(uction)?|release"   # default
```

### Frontend label

Override the frontend identifier shown before the model name.

```bash
export STATUSLINE_FE_NAME="ACME"    # shows as: ACME:SNT
```

---

## Examples

### DevOps / multi-server setup

```bash
# ~/.zshrc
export STATUSLINE_HOST_MAP="web-01=PROD web-02=PROD db-primary=DB staging=STAGE"
export STATUSLINE_LIVE_PATTERN="live|prod|main|release"
export CLAUDE_SL_STYLE=powerline
```

Result on web-01: ` CLAUDE:SNT  PROD  main  LIVE  09:15 `

### Project-scoped development

```bash
# ~/.zshrc
export STATUSLINE_PROJECT_PATTERN="acme-corp|~/projects/acme"
export STATUSLINE_PROJECT_LABEL="ACME"
export STATUSLINE_ACCENT_COLOR=25   # dark blue
```

Result inside ~/projects/acme: ` CLAUDE:SNT  ACME  feature/payments*  SAFE  14:47 `

### Focus mode (minimal)

```bash
export CLAUDE_STATUSLINE_MODE=focus
```

Result: ` CLAUDE:SNT  LOCAL  main `

---

## Advanced customization

The `examples/` directory contains a full production customization example:

| File | Description |
|------|-------------|
| `examples/werixo.sh` | Full MSP example: server aliases, Obsidian vault area detection, live gate progress tracking from a markdown file |

To use an example as your statusline:

```bash
cp examples/werixo.sh ~/.claude/statusline.sh
```

### Writing your own extension

The script is designed to be easy to fork. Key extension points:

**Add a custom context label:**
```bash
# After the generic is_project() function, add your own:
is_myproject() {
    printf '%s' "$CWD" | grep -q "myproject" && return 0
    return 1
}
```

**Add a custom state segment:**
```bash
# Replace or supplement the S4 state block:
if my_critical_condition; then
    add_seg "CRIT" $C_RED $C_WHITE
elif is_live; then
    add_seg "LIVE" $C_RED $C_WHITE
else
    add_seg "SAFE" $C_GREEN $C_WHITE
fi
```

**Add a custom segment:**
```bash
# Any point after the segment arrays are initialized:
add_seg "MYDATA" $C_BLUE $C_WHITE
```

`add_seg TEXT BG_COLOR_256 FG_COLOR_256`

---

## Troubleshooting

**Statusline not appearing:**
- Check `~/.claude/settings.json` contains the `statusLine` key
- Run `bash ~/.claude/statusline.sh </dev/null` manually — should output a colored line
- Verify `jq` is installed: `jq --version`

**Colors look wrong:**
- Your terminal must support 256 colors: `echo $TERM` should show `xterm-256color` or similar
- If using tmux, add `set -g default-terminal "screen-256color"` to `~/.tmux.conf`

**Powerline arrows look broken:**
- The `▶` character (U+25B6) is a standard Unicode block — no Nerd Font needed
- If it renders as a box, your terminal font may lack this codepoint; switch to `flat` style

**Slow statusline:**
- The git operations (`git status`, `git branch`) run on every render
- For large repos, consider setting `CLAUDE_STATUSLINE_MODE=focus` to skip non-essential segments
- The `examples/werixo.sh` uses a TTL cache for expensive file reads

---

## License

MIT
