# agent-statusline

One visual statusline for **Claude Code**, **Codex CLI**, and **OpenCode**. It keeps the original Claude segmented bar, maps the same information to Codex's native TUI, and provides a real OpenCode `app_bottom` plugin.

![Agent Statusline preview](assets/statusline.svg)

## Compatibility

| Agent | Integration | Segments |
|---|---|---|
| Claude Code | Custom `statusLine` command | frontend/model, host, git, context, effort, time |
| Codex CLI | Native `[tui].status_line` | model/reasoning, directory, git, context, limits, version |
| OpenCode | Public TUI plugin in `app_bottom` | frontend/model, host, git, context, effort, time |

Codex intentionally uses native status items: its public configuration accepts an ordered list of built-in items, not an arbitrary renderer command. The result carries the same information but follows Codex's own terminal styling.

The OpenCode plugin targets the public TUI plugin API in OpenCode 1.18.14 or newer.

## Install

```bash
git clone https://github.com/bugroo/claude-statusline.git
cd claude-statusline
```

Install one target:

```bash
bash install.sh claude
bash install.sh codex
bash install.sh opencode
```

Or install all three:

```bash
bash install.sh all
```

For backward compatibility, `bash install.sh` still installs Claude Code only. Every existing file changed by the installer is copied to a timestamped `*.bak.*` file first, and rerunning the installer does not duplicate configuration.

### Requirements

- Claude Code: Bash and `jq`.
- Codex: no extra runtime dependency; the installer edits `~/.codex/config.toml`.
- OpenCode: OpenCode 1.18.14+ and Python 3.9+ for comment-preserving `tui.json`/JSONC patching.
- A terminal with color and standard Unicode support. No Nerd Font is required.

## What gets installed

### Claude Code

- Renderer: `~/.claude/statusline.sh`
- Configuration: `~/.claude/settings.json`

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /home/you/.claude/statusline.sh"
  }
}
```

### Codex CLI

The installer merges these keys into the existing `[tui]` section in `~/.codex/config.toml` and preserves unrelated settings:

```toml
[tui]
status_line = ["model-with-reasoning", "current-dir", "git-branch", "context-remaining", "five-hour-limit", "weekly-limit", "codex-version"]
status_line_use_colors = true
```

The standalone snippet is available at [`codex/statusline.toml`](codex/statusline.toml).

### OpenCode

- Plugin: `~/.config/opencode/plugins/agent-statusline.tsx`
- Registration: the plugin path is added once to `~/.config/opencode/tui.json`

OpenCode installs its own config-scoped plugin SDK when it sees the local file entry. The installer itself never invokes npm, npx, yarn, or a package lifecycle script.

If `XDG_CONFIG_HOME` or `OPENCODE_CONFIG_DIR` is set, the installer respects it. Existing JSONC comments and trailing commas are preserved.

## Configuration

The shared variables work across the custom renderers:

```bash
# focus hides time; ops is the default; debug adds the short path
export AGENT_STATUSLINE_MODE=focus   # focus | ops | debug

# Claude rendering only
export AGENT_STATUSLINE_STYLE=flat  # blend | flat | powerline

# host aliases; PROD or LIVE also activate Claude's live-context detection
export STATUSLINE_HOST_MAP="web-01=PROD devbox=DEV"
```

The historical Claude names remain compatible:

```bash
export CLAUDE_STATUSLINE_MODE=focus
export CLAUDE_SL_STYLE=powerline
```

Claude-only options:

| Variable | Purpose | Default |
|---|---|---|
| `STATUSLINE_FE_NAME` | Frontend label | `CLAUDE` |
| `CLAUDE_LAUNCH_ALIAS` | Per-process frontend label | unset |
| `STATUSLINE_PROJECT_PATTERN` | Regex for project detection | unset |
| `STATUSLINE_PROJECT_LABEL` | Project label | `PROJECT` |
| `STATUSLINE_ACCENT_COLOR` | 256-color project accent | `127` |
| `STATUSLINE_LIVE_PATTERN` | Production path/branch regex | `live|prod(uction)?` |
| `STATUSLINE_COMPACT_RESERVE` | Context points reserved in the Claude estimate | `16` |

Claude's `CTX` value is an approximation because its internal auto-compact threshold is not exposed in the statusline payload. OpenCode reports remaining context directly from the active model limit and the latest assistant token totals.

## Accessibility and safety

- Every state has a text label; meaning never depends on color alone.
- Dirty git state uses `*`, context uses `CTX`, and effort uses `EFF`.
- Dynamic model, branch, host, and path text is stripped of control characters and bounded before OpenCode renders it.
- Standard Unicode separators are used; no private-use glyphs or patched font is needed.
- The repository pins pnpm, blocks lifecycle scripts by default, rejects trust downgrades, blocks exotic subdependencies, and enforces a 24-hour release age.

## Development

Use pnpm only:

```bash
pnpm install
pnpm run check
pnpm run audit
```

`pnpm run check` runs ShellCheck, TypeScript validation, renderer tests, installer isolation tests, JSONC preservation tests, and idempotence checks.

## Troubleshooting

If the line does not appear, restart the corresponding TUI after installation.

- Claude: verify `~/.claude/settings.json` contains `statusLine`, then run `bash ~/.claude/statusline.sh </dev/null`.
- Codex: run `/statusline` to inspect or change the native item order.
- OpenCode: verify the absolute plugin path occurs once in `~/.config/opencode/tui.json`; OpenCode 1.18.14+ is required.
- Colors: ensure the terminal exposes color support, such as `xterm-256color`.

## License

MIT
