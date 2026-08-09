#!/usr/bin/env bash
# install.sh — Agent Statusline installer for Claude Code, Codex, and OpenCode.
#
# Usage:
#   bash install.sh             # backward-compatible: Claude Code only
#   bash install.sh claude
#   bash install.sh codex
#   bash install.sh opencode
#   bash install.sh all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_TARGET="${1:-claude}"
STAMP="$(date +%Y%m%d%H%M%S).$$"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RST='\033[0m'

ok()   { printf "${GREEN}✓${RST} %s\n" "$1"; }
warn() { printf "${YELLOW}!${RST} %s\n" "$1"; }
err()  { printf "${RED}✗${RST} %s\n" "$1" >&2; }
step() { printf "\n${BOLD}%s${RST}\n" "$1"; }

usage() {
    printf 'Usage: bash install.sh [claude|codex|opencode|all]\n'
}

backup_file() {
    local source_file="$1"
    if [ -f "$source_file" ]; then
        local backup="${source_file}.bak.${STAMP}"
        cp "$source_file" "$backup"
        warn "Backup created: $backup"
    fi
}

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        err "jq is required for this target but was not found."
        printf '  macOS: brew install jq\n  Debian/Ubuntu: apt install jq\n'
        exit 1
    fi
}

install_claude() {
    local claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    local target="$claude_dir/statusline.sh"
    local settings="$claude_dir/settings.json"
    local patched target_quoted
    printf -v target_quoted '%q' "$target"

    step "Installing Claude Code statusline"
    require_jq
    mkdir -p "$claude_dir"

    backup_file "$target"
    cp "$SCRIPT_DIR/statusline.sh" "$target"
    chmod +x "$target"
    ok "Installed renderer: $target"

    if [ -f "$settings" ]; then
        backup_file "$settings"
        patched=$(jq --arg command "bash $target_quoted" '.statusLine = {
            "type": "command",
            "command": $command
        }' "$settings")
        printf '%s\n' "$patched" > "$settings"
        ok "Updated: $settings"
    else
        jq -n --arg command "bash $target_quoted" '{
            "statusLine": {
                "type": "command",
                "command": $command
            }
        }' > "$settings"
        ok "Created: $settings"
    fi

    if bash "$target" </dev/null >/dev/null 2>&1; then
        ok "Claude renderer smoke test passed"
    else
        warn "Claude renderer smoke test returned a non-zero status"
    fi
}

patch_codex_config() {
    local config_file="$1"
    local patched

    patched=$(awk '
        function emit_statusline() {
            print "status_line = [\"model-with-reasoning\", \"current-dir\", \"git-branch\", \"context-remaining\", \"five-hour-limit\", \"weekly-limit\", \"codex-version\"]"
            print "status_line_use_colors = true"
            inserted = 1
        }
        BEGIN {
            in_tui = 0
            found_tui = 0
            inserted = 0
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
            if (in_tui && !inserted) emit_statusline()
            if ($0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/) {
                in_tui = 1
                found_tui = 1
            } else {
                in_tui = 0
            }
            print
            next
        }
        in_tui && /^[[:space:]]*(status_line|status_line_use_colors)[[:space:]]*=/ { next }
        !in_tui && /^[[:space:]]*tui\.(status_line|status_line_use_colors)[[:space:]]*=/ { next }
        { print }
        END {
            if (in_tui && !inserted) emit_statusline()
            if (!found_tui) {
                if (NR > 0) print ""
                print "[tui]"
                emit_statusline()
            }
        }
    ' "$config_file")

    printf '%s\n' "$patched" > "$config_file"
}

install_codex() {
    local codex_dir="${CODEX_HOME:-$HOME/.codex}"
    local config="$codex_dir/config.toml"

    step "Installing Codex native statusline"
    mkdir -p "$codex_dir"

    if [ -f "$config" ]; then
        backup_file "$config"
        patch_codex_config "$config"
        ok "Merged native TUI statusline into: $config"
    else
        cp "$SCRIPT_DIR/codex/statusline.toml" "$config"
        ok "Created: $config"
    fi

    if command -v codex >/dev/null 2>&1; then
        if codex --strict-config --version >/dev/null 2>&1; then
            ok "Codex strict-config smoke test passed"
        else
            warn "Codex could not validate the resulting config; backup is available"
        fi
    else
        warn "Codex CLI is not installed; configuration was written but not runtime-tested"
    fi
}

install_opencode() {
    local config_root="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
    local plugin_dir="$config_root/plugins"
    local plugin_target="$plugin_dir/agent-statusline.tsx"
    local tui_config="$config_root/tui.json"

    step "Installing OpenCode TUI statusline"
    if ! command -v python3 >/dev/null 2>&1; then
        err "python3 is required to patch tui.json/JSONC without losing comments."
        exit 1
    fi

    mkdir -p "$plugin_dir"
    backup_file "$plugin_target"
    cp "$SCRIPT_DIR/opencode/statusline.tsx" "$plugin_target"
    ok "Installed plugin: $plugin_target"

    backup_file "$tui_config"
    python3 "$SCRIPT_DIR/scripts/patch-tui-config.py" "$tui_config" "$plugin_target"
    ok "Registered plugin in: $tui_config"

    if command -v opencode >/dev/null 2>&1; then
        ok "OpenCode found: restart its TUI to load the plugin"
    else
        warn "OpenCode is not installed; plugin was configured but not runtime-tested"
    fi
}

case "$INSTALL_TARGET" in
    claude)
        install_claude
        ;;
    codex)
        install_codex
        ;;
    opencode)
        install_opencode
        ;;
    all)
        install_claude
        install_codex
        install_opencode
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        err "Unknown target: $INSTALL_TARGET"
        usage >&2
        exit 2
        ;;
esac

printf '\n%bInstallation complete.%b\n' "${GREEN}${BOLD}" "$RST"
printf 'Restart the selected agent TUI to see the new statusline.\n'
