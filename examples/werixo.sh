#!/usr/bin/env bash
# examples/werixo.sh — WERIXO MSP Advanced Customization Example
#
# This is the production statusline used by WERIXO, a managed service provider
# operating on Hetzner RS servers (core + edge) with an Obsidian-based ops vault.
#
# It extends the generic statusline.sh with:
#   - WERIXO vault area detection (SSOT, GATES, RUNBOOKS, etc.)
#   - Gate 6 progress tracking (reads live from GATES_MASTER.md with TTL cache)
#   - CLOBS frontend context (server operations user)
#   - CORE/EDGE server aliases for wx-core-01 / wx-edge-01
#
# To use this instead of the generic version:
#   cp examples/werixo.sh ~/.claude/statusline.sh
#   chmod +x ~/.claude/statusline.sh
#
# Then set in settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }
#
# ─── Structure:  [FE:MODEL] [CONTEXT] [GIT] [STATE] [TIME] ───────────────────
# Modes:  CLAUDE_STATUSLINE_MODE=focus|ops|debug  (default: ops)
# Style:  CLAUDE_SL_STYLE=flat|powerline          (default: flat)
# FE:     WERIXO_FRONTEND=clobs                   (when running as clobs user)

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

# ─── 256-COLOR PALETTE ────────────────────────────────────────────────────────
C_DARK=236
C_DARKER=234
C_GRAY=244
C_WHITE=255
C_BLACK=16
C_MAGENTA=127   # WERIXO vault context bg (deep purple-magenta)
C_PURPLE=55     # Gate 6 progress bg
C_BLUE=25       # CORE/EDGE/REMOTE server bg
C_GREEN=28      # clean git / SAFE state bg
C_AMBER=136     # dirty git bg
C_RED=160       # LIVE / ERR bg
C_LOCAL=237     # LOCAL context bg
C_TEAL=30       # model bg (calm, distinct from other segments)
C_FE_CL=24      # CLAUDE frontend bg (dark steel-blue)
C_FE_CLB=27     # CLOBS  frontend bg (bright blue — higher visual weight)

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
    case "$h" in
        wx-core-01|core)             printf 'CORE'   ;;
        wx-edge-01|edge)             printf 'EDGE'   ;;
        Laptop01|MacBook*|localhost) printf 'LOCAL'  ;;
        "")                          printf 'LOCAL'  ;;
        *)                           printf 'REMOTE' ;;
    esac
}

frontend_context() {
    # Set WERIXO_FRONTEND=clobs in your shell when operating as the clobs user
    if [ -n "${WERIXO_FRONTEND:-}" ]; then
        printf '%s' "${WERIXO_FRONTEND}" | tr '[:lower:]' '[:upper:]'
    elif [ "$(whoami 2>/dev/null)" = "clobs" ]; then
        printf 'CLOBS'
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

# ─── WERIXO-SPECIFIC ──────────────────────────────────────────────────────────
VAULT_ROOT="${WERIXO_VAULT_ROOT:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian Vault}"
GATES_FILE="${VAULT_ROOT}/WERIXO/01_SSOT/GATES_MASTER.md"
GATE_CACHE="/tmp/.werixo_g6_cache"
GATE_TTL=45

is_werixo() {
    printf '%s' "$CWD" | grep -qiE 'Obsidian.Vault|WERIXO' 2>/dev/null
}

werixo_area() {
    case "$CWD" in
        */01_SSOT*)          printf 'SSOT'  ;;
        */02_GATES*)         printf 'GATES' ;;
        */03_RUNBOOKS*)      printf 'RB'    ;;
        */00_ADMIN/LEGAL*)   printf 'LEGAL' ;;
        */06_SALES*)         printf 'SALES' ;;
        */08_AUTOM*)         printf 'AUTO'  ;;
        */memory*|*/MEMORY*) printf 'MEM'   ;;
        *)                   printf 'WX'    ;;
    esac
}

gate6_status() {
    if [ -f "$GATE_CACHE" ]; then
        local age mtime
        mtime=$(stat -f %m "$GATE_CACHE" 2>/dev/null || echo 0)
        age=$(( $(date +%s) - mtime ))
        [ "${age:-9999}" -lt "$GATE_TTL" ] && { cat "$GATE_CACHE"; return; }
    fi
    local r=""
    if [ -f "$GATES_FILE" ]; then
        r=$(grep -E 'Entry Criteria [0-9]+/21' "$GATES_FILE" 2>/dev/null \
            | grep -oE '[0-9]+/21' | head -1)
        [ -z "$r" ] && r=$(grep '\*\*6\*\*' "$GATES_FILE" 2>/dev/null \
            | grep -oE '[0-9]+/21' | head -1)
    fi
    printf '%s' "${r:-}" > "$GATE_CACHE"
    printf '%s' "${r:-}"
}

is_live() {
    local h; h=$(host_alias)
    [ "$h" = "CORE" ] || [ "$h" = "EDGE" ] && return 0
    printf '%s' "$CWD" | grep -qiE '/(live|prod(uction)?)(/|$)' && return 0
    git_branch 2>/dev/null | grep -qiE '^(live|prod|production)$' && return 0
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

# S1 — FE:MODEL (CLAUDE or CLOBS with distinct colors)
MNAME=$(model_short)
FE=$(frontend_context)
if [ "$FE" = "CLOBS" ]; then
    add_seg "CLOBS:${MNAME}" $C_FE_CLB $C_WHITE
else
    add_seg "CLAUDE:${MNAME}" $C_FE_CL $C_WHITE
fi

# S2 — CONTEXT (one: CORE/EDGE/REMOTE > WERIXO:AREA > LOCAL)
HOST=$(host_alias)
if [ "$HOST" = "CORE" ] || [ "$HOST" = "EDGE" ] || [ "$HOST" = "REMOTE" ]; then
    add_seg "$HOST" $C_BLUE $C_WHITE
elif is_werixo 2>/dev/null; then
    AREA=$(werixo_area)
    if [ "$AREA" = "WX" ]; then
        add_seg "WERIXO" $C_MAGENTA $C_WHITE
    else
        add_seg "WX:${AREA}" $C_MAGENTA $C_WHITE
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

# S4 — STATE (LIVE > G6 progress > SAFE)
if is_live 2>/dev/null; then
    add_seg "LIVE" $C_RED $C_WHITE
elif is_werixo 2>/dev/null; then
    G6=$(gate6_status 2>/dev/null)
    if [ -n "$G6" ]; then
        add_seg "G6 ${G6}" $C_PURPLE $C_WHITE
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
    CWD_SHORT=$(printf '%s' "$CWD" \
        | sed 's|.*Obsidian Vault/||' \
        | rev | cut -d'/' -f1-2 | rev)
    [ -n "$CWD_SHORT" ] && add_seg "$CWD_SHORT" $C_DARK $C_GRAY
fi

# ─── OUTPUT ───────────────────────────────────────────────────────────────────
render_bar
