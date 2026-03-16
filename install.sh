#!/usr/bin/env bash
# install.sh — Claude Statusline installer
#
# Usage: bash install.sh
#
# What this does:
#   1. Copies statusline.sh to ~/.claude/statusline.sh
#   2. Patches ~/.claude/settings.json to enable the statusline
#
# Requirements: jq (for JSON patching)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

# ─── COLORS ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RST='\033[0m'

ok()   { printf "${GREEN}✓${RST} %s\n" "$1"; }
warn() { printf "${YELLOW}!${RST} %s\n" "$1"; }
err()  { printf "${RED}✗${RST} %s\n" "$1" >&2; }
step() { printf "\n${BOLD}%s${RST}\n" "$1"; }

# ─── CHECKS ───────────────────────────────────────────────────────────────────
step "Checking requirements..."

if ! command -v jq >/dev/null 2>&1; then
    err "jq is required but not found."
    printf "  Install it with:  brew install jq  (macOS) or  apt install jq  (Linux)\n"
    exit 1
fi
ok "jq found: $(jq --version)"

if [ ! -d "$HOME/.claude" ]; then
    err "~/.claude directory not found. Is Claude Code installed?"
    printf "  Install Claude Code: https://claude.ai/code\n"
    exit 1
fi
ok "~/.claude directory found"

# ─── COPY SCRIPT ──────────────────────────────────────────────────────────────
step "Installing statusline script..."

if [ -f "$TARGET" ]; then
    BACKUP="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$TARGET" "$BACKUP"
    warn "Existing statusline backed up to: $BACKUP"
fi

cp "$SCRIPT_DIR/statusline.sh" "$TARGET"
chmod +x "$TARGET"
ok "Installed: $TARGET"

# ─── PATCH SETTINGS.JSON ──────────────────────────────────────────────────────
step "Configuring settings.json..."

if [ ! -f "$SETTINGS" ]; then
    warn "settings.json not found — creating minimal one."
    printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "bash ~/.claude/statusline.sh"\n  }\n}\n' > "$SETTINGS"
    ok "Created: $SETTINGS"
else
    # Backup settings
    SETTINGS_BAK="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$SETTINGS_BAK"

    # Merge statusLine key (preserves all other settings)
    PATCHED=$(jq '. + {
        "statusLine": {
            "type": "command",
            "command": "bash ~/.claude/statusline.sh"
        }
    }' "$SETTINGS")

    printf '%s\n' "$PATCHED" > "$SETTINGS"
    ok "Patched: $SETTINGS (backup: $SETTINGS_BAK)"
fi

# ─── SMOKE TEST ───────────────────────────────────────────────────────────────
step "Running smoke test..."

if bash "$TARGET" </dev/null >/dev/null 2>&1; then
    ok "statusline.sh executes without errors"
else
    warn "statusline.sh returned a non-zero exit code."
    warn "This may be harmless (e.g. no git repo in current dir)."
    warn "Run manually to check: bash ~/.claude/statusline.sh </dev/null"
fi

# ─── DONE ─────────────────────────────────────────────────────────────────────
printf "\n${GREEN}${BOLD}Installation complete!${RST}\n\n"
printf "The statusline will appear at the bottom of Claude Code sessions.\n\n"
printf "${BOLD}Optional configuration (add to your shell profile):${RST}\n\n"
printf "  # Show project context when working in a specific directory:\n"
printf "  export STATUSLINE_PROJECT_PATTERN=\"myproject|~/work/acme\"\n"
printf "  export STATUSLINE_PROJECT_LABEL=\"ACME\"\n\n"
printf "  # Map server hostnames to aliases (PROD/LIVE triggers red LIVE indicator):\n"
printf "  export STATUSLINE_HOST_MAP=\"myserver=PROD devbox=DEV\"\n\n"
printf "  # Switch style:\n"
printf "  export CLAUDE_SL_STYLE=powerline   # or: flat (default)\n\n"
printf "  # Switch mode:\n"
printf "  export CLAUDE_STATUSLINE_MODE=focus   # hides time segment\n\n"
printf "See README.md for full configuration reference and examples.\n"
