#!/usr/bin/env bash
# examples/msp.sh — MSP / Multi-Server Advanced Customization Example
#
# Use this as a starting point if you:
#   - Manage multiple servers (core, edge, prod, staging...)
#   - Keep an Obsidian vault or markdown-based ops wiki
#   - Want to track a "goal counter" from a live markdown file (e.g. sprint progress)
#   - Have a secondary user/role context (e.g. an ops user separate from your dev user)
#
# To use this instead of the generic version:
#   cp examples/msp.sh ~/.claude/statusline.sh
#   chmod +x ~/.claude/statusline.sh
#
# ─── Structure:  [FE:MODEL] [CONTEXT] [GIT] [STATE] [TIME] ───────────────────
# Modes:  CLAUDE_STATUSLINE_MODE=focus|ops|debug  (default: ops)
# Style:  CLAUDE_SL_STYLE=flat|powerline          (default: flat)
#
# ─── Extra env vars used by this example ─────────────────────────────────────
#
# ORG_NAME            Short label for your org shown in the context segment.
#                     (default: ORG)
#
# ORG_VAULT_ROOT      Path to your ops vault / wiki root directory.
#                     Used for area detection and goal tracking.
#                     (default: ~/vault)
#
# ORG_GOALS_FILE      Path to a markdown file containing a progress counter
#                     matching the pattern "N/TOTAL" (e.g. "7/21").
#                     Leave unset to disable goal tracking.
#
# ORG_GOALS_LABEL     Label shown before the counter (default: G)
#                     Example: ORG_GOALS_LABEL=SPRINT → shows "SPRINT 7/21"
#
# ORG_GOALS_TOTAL     Denominator to match in the file (default: 21)
#
# ORG_OPS_USER        If whoami matches this, shows the alt frontend label.
#                     (default: ops)
#
# OPS_FRONTEND        Override frontend label manually (e.g. OPS_FRONTEND=ops).

# ─── INPUT ────────────────────────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT"   | jq -r '.cwd   // empty' 2>/dev/null)
MODEL=$(printf '%s' "$INPUT" | jq -r '
    if (.model | type) == "object"
    then (.model.display_name // .model.id // "?")
    else (.model // "?")
    end' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# ─── CONFIG ───────────────────────────────────────────────────────────────────
MODE="${CLAUDE_STATUSLINE_MODE:-ops}"
STYLE="${CLAUDE_SL_STYLE:-flat}"

ORG_NAME="${ORG_NAME:-ORG}"
ORG_VAULT_ROOT="${ORG_VAULT_ROOT:-$HOME/vault}"
ORG_GOALS_FILE="${ORG_GOALS_FILE:-}"
ORG_GOALS_LABEL="${ORG_GOALS_LABEL:-G}"
ORG_GOALS_TOTAL="${ORG_GOALS_TOTAL:-21}"
ORG_OPS_USER="${ORG_OPS_USER:-ops}"

# ─── 256-COLOR PALETTE ────────────────────────────────────────────────────────
C_DARK=236
C_DARKER=234
C_GRAY=244
C_WHITE=255
C_BLACK=16
C_ACCENT=127    # org context bg — change to taste
C_PURPLE=55     # goal progress bg
C_BLUE=25       # remote server bg
C_GREEN=28      # clean git / SAFE bg
C_AMBER=136     # dirty git bg
C_RED=160       # LIVE bg
C_LOCAL=237     # LOCAL bg
C_FE=24         # default frontend bg (dark steel-blue)
C_FE_OPS=27     # ops user frontend bg (brighter blue)

cbg() { printf '\033[48;5;%dm' "$1"; }
cfg() { printf '\033[38;5;%dm' "$1"; }
RST=$'\033[0m'

# ─── HELPERS ──────────────────────────────────────────────────────────────────
model_short() {
    local m="${MODEL:-?}" is1m=""
    printf '%s' "$m" | grep -qiE '\[1m\]|1M context' && is1m="+1M"
    m=$(printf '%s' "$m" | sed \
        -e 's/[Ss]onnet.*/SNT/' \
        -e 's/[Oo]pus.*/OPS/'   \
        -e 's/[Hh]aiku.*/HKU/'  \
        -e 's/claude-//g')
    printf '%s' "$m" | grep -qE '^(SNT|OPS|HKU)' || m=$(printf '%s' "$m" | cut -c1-6)
    printf '%s' "${m}${is1m}"
}

host_alias() {
    local h; h=$(hostname -s 2>/dev/null)
    if [ -n "${STATUSLINE_HOST_MAP:-}" ]; then
        local pair
        for pair in $STATUSLINE_HOST_MAP; do
            local key="${pair%%=*}" val="${pair#*=}"
            [ "$h" = "$key" ] && { printf '%s' "$val"; return; }
        done
    fi
    printf 'LOCAL'
}

frontend_context() {
    if [ -n "${OPS_FRONTEND:-}" ]; then
        printf '%s' "${OPS_FRONTEND}" | tr '[:lower:]' '[:upper:]'
    elif [ "$(whoami 2>/dev/null)" = "$ORG_OPS_USER" ]; then
        printf '%s' "$ORG_OPS_USER" | tr '[:lower:]' '[:upper:]'
    else
        printf 'CLAUDE'
    fi
}

git_branch() {
    git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$CWD" rev-parse --short HEAD 2>/dev/null \
        || true
}

git_dirty() {
    local n; n=$(git -C "$CWD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "${n:-0}" -gt 0 ] && printf '1' || printf '0'
}

git_ahead_behind() {
    git -C "$CWD" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || return
    local a b
    a=$(git -C "$CWD" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    b=$(git -C "$CWD" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    [ "${a:-0}" -gt 0 ] && printf '^%s' "$a"
    [ "${b:-0}" -gt 0 ] && printf 'v%s' "$b"
}

# ─── ORG-SPECIFIC ─────────────────────────────────────────────────────────────
GOALS_CACHE="/tmp/.org_goals_cache"
GOALS_TTL=45

is_org_vault() {
    [ -n "$ORG_VAULT_ROOT" ] || return 1
    printf '%s' "$CWD" | grep -qF "$ORG_VAULT_ROOT" 2>/dev/null
}

vault_area() {
    # Customize these patterns to match your vault's folder structure
    case "$CWD" in
        */ssot*|*/SSOT*)         printf 'SSOT'  ;;
        */runbooks*|*/RUNBOOKS*) printf 'RB'    ;;
        */gates*|*/GATES*)       printf 'GATES' ;;
        */legal*|*/LEGAL*)       printf 'LEGAL' ;;
        */sales*|*/SALES*)       printf 'SALES' ;;
        */memory*|*/MEMORY*)     printf 'MEM'   ;;
        *)                       printf ''      ;;
    esac
}

goals_status() {
    [ -n "$ORG_GOALS_FILE" ] || return
    if [ -f "$GOALS_CACHE" ]; then
        local mtime age
        mtime=$(stat -f %m "$GOALS_CACHE" 2>/dev/null || echo 0)
        age=$(( $(date +%s) - mtime ))
        [ "${age:-9999}" -lt "$GOALS_TTL" ] && { cat "$GOALS_CACHE"; return; }
    fi
    local r=""
    if [ -f "$ORG_GOALS_FILE" ]; then
        r=$(grep -oE "[0-9]+/${ORG_GOALS_TOTAL}" "$ORG_GOALS_FILE" 2>/dev/null | head -1)
    fi
    printf '%s' "${r:-}" > "$GOALS_CACHE"
    printf '%s' "${r:-}"
}

is_live() {
    local h; h=$(host_alias)
    printf '%s' "$h" | grep -qiE '^(PROD|LIVE)$' && return 0
    local pat="${STATUSLINE_LIVE_PATTERN:-live|prod(uction)?}"
    printf '%s' "$CWD" | grep -qiE "/(${pat})(/|$)" && return 0
    git_branch 2>/dev/null | grep -qiE "^(${pat})$" && return 0
    return 1
}

# ─── SEGMENT ARRAYS ───────────────────────────────────────────────────────────
declare -a SEGS=() SBGS=() SFGS=()
add_seg() { SEGS+=("$1"); SBGS+=("$2"); SFGS+=("$3"); }

# ─── RENDER ───────────────────────────────────────────────────────────────────
render_bar() {
    local out="" i count=${#SEGS[@]}
    for i in "${!SEGS[@]}"; do
        local text="${SEGS[$i]}" cbg_n="${SBGS[$i]}" cfg_n="${SFGS[$i]}"
        local next=$(( i + 1 ))
        if [ "$STYLE" = "powerline" ] && [ $next -lt $count ]; then
            local nbg_n="${SBGS[$next]}"
            out+="$(cbg "$cbg_n")$(cfg "$cfg_n") ${text} $(cbg "$nbg_n")$(cfg "$cbg_n")▶"
        elif [ "$STYLE" = "powerline" ]; then
            out+="$(cbg "$cbg_n")$(cfg "$cfg_n") ${text} ${RST}"
        else
            out+="$(cbg "$cbg_n")$(cfg "$cfg_n") ${text} ${RST} "
        fi
    done
    printf '%s\n' "$out"
}

# ─── COMPUTE SEGMENTS ─────────────────────────────────────────────────────────

# S1 — FE:MODEL
MNAME=$(model_short)
FE=$(frontend_context)
if [ "$FE" != "CLAUDE" ]; then
    add_seg "${FE}:${MNAME}" $C_FE_OPS $C_WHITE
else
    add_seg "CLAUDE:${MNAME}" $C_FE $C_WHITE
fi

# S2 — CONTEXT (mapped host > vault area > org label > LOCAL)
HOST=$(host_alias)
if [ "$HOST" != "LOCAL" ]; then
    add_seg "$HOST" $C_BLUE $C_WHITE
elif is_org_vault 2>/dev/null; then
    AREA=$(vault_area)
    if [ -n "$AREA" ]; then
        add_seg "${ORG_NAME}:${AREA}" $C_ACCENT $C_WHITE
    else
        add_seg "$ORG_NAME" $C_ACCENT $C_WHITE
    fi
else
    add_seg "LOCAL" $C_LOCAL $C_GRAY
fi

# S3 — GIT
BRANCH=$(git_branch)
IS_DIRTY=$(git_dirty)
if [ -n "$BRANCH" ]; then
    BR_SHORT=$(printf '%s' "$BRANCH" | cut -c1-12)
    [ "$MODE" = "debug" ] && BR_SHORT="${BR_SHORT}$(git_ahead_behind 2>/dev/null)"
    if [ "$IS_DIRTY" = "1" ]; then
        add_seg "${BR_SHORT}*" $C_AMBER $C_BLACK
    else
        add_seg "$BR_SHORT" $C_GREEN $C_WHITE
    fi
else
    add_seg "no-git" $C_DARK $C_GRAY
fi

# S4 — STATE (LIVE > goal progress > SAFE)
if is_live 2>/dev/null; then
    add_seg "LIVE" $C_RED $C_WHITE
elif is_org_vault 2>/dev/null; then
    GOALS=$(goals_status 2>/dev/null)
    if [ -n "$GOALS" ]; then
        add_seg "${ORG_GOALS_LABEL} ${GOALS}" $C_PURPLE $C_WHITE
    else
        add_seg "SAFE" $C_GREEN $C_WHITE
    fi
else
    add_seg "SAFE" $C_GREEN $C_WHITE
fi

# S5 — TIME (ops/debug only)
if [ "$MODE" = "ops" ] || [ "$MODE" = "debug" ]; then
    add_seg "$(date +%H:%M)" $C_DARKER $C_GRAY
fi

# S6 — CWD (debug only)
if [ "$MODE" = "debug" ]; then
    CWD_SHORT=$(printf '%s' "$CWD" | rev | cut -d'/' -f1-2 | rev)
    [ -n "$CWD_SHORT" ] && add_seg "$CWD_SHORT" $C_DARK $C_GRAY
fi

# ─── OUTPUT ───────────────────────────────────────────────────────────────────
render_bar
