#!/usr/bin/env bash
# ~/.claude/statusline.sh — v1.0 Visual Segment Bar
#
# Structure:  [FE:MODEL] [CONTEXT] [GIT] [STATE] [TIME]
#
# Modes:  CLAUDE_STATUSLINE_MODE=focus|ops|debug  (default: ops)
# Style:  CLAUDE_SL_STYLE=flat|powerline          (default: flat)
#
# --- Optional configuration (env vars) ---
#
# STATUSLINE_HOST_MAP     Space-separated "hostname=ALIAS" pairs.
#                         Any mapped host is shown in the context segment.
#                         Hosts with alias PROD or LIVE trigger the LIVE state indicator.
#                         Example: STATUSLINE_HOST_MAP="myserver=PROD devbox=DEV"
#
# STATUSLINE_PROJECT_PATTERN  Regex matched against CWD. When matched, shows project label.
#                              Example: STATUSLINE_PROJECT_PATTERN="myproject|~/work/acme"
#
# STATUSLINE_PROJECT_LABEL    Label shown when project detected. (default: PROJECT)
#
# STATUSLINE_ACCENT_COLOR     256-color number for project context bg. (default: 127)
#
# STATUSLINE_LIVE_PATTERN     Regex matched against CWD path or branch name to detect
#                              live/production context. (default: "live|prod(uction)?")
#
# STATUSLINE_FE_NAME          Override the frontend label (default: CLAUDE).
#                              Useful if you have multiple Claude sessions with different roles.
#
# STATUSLINE_COMPACT_RESERVE  Percentage points subtracted from remaining context to
#                              approximate the "% until auto-compact" badge. (default: 16)
#                              Set to 0 to show true free-context %. Approximation only —
#                              the real auto-compact threshold is internal to Claude Code.
#
# flat      — colored blocks with reset gap between segments
# blend     — segments fuse together using ▌ (U+258C) half-block transitions (default)
# powerline — colored blocks with ▶ (U+25B6) chained transitions
#             (no Nerd Font required for any style)
#
# 256-color with ANSI escape codes. No secrets in output.

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
STYLE="${CLAUDE_SL_STYLE:-blend}"

# ─── 256-COLOR PALETTE ────────────────────────────────────────────────────────
C_DARK=236      # segment default bg (dark gray)
C_DARKER=234    # time bg
C_GRAY=244      # neutral text
C_WHITE=255     # bright text
C_BLACK=16      # black text (for light bg)
C_ACCENT=127    # project context bg — configurable via STATUSLINE_ACCENT_COLOR
C_BLUE=25       # remote host bg
C_GREEN=28      # clean git / SAFE state bg
C_AMBER=136     # dirty git bg
C_RED=160       # LIVE / ERR bg
C_LOCAL=237     # LOCAL context bg
C_FE=24         # frontend label bg (dark steel-blue)

# ANSI helpers
cbg() { printf '\033[48;5;%dm' "$1"; }
cfg() { printf '\033[38;5;%dm' "$1"; }
RST=$'\033[0m'

# ─── HELPERS ──────────────────────────────────────────────────────────────────
model_short() {
    local m="${MODEL:-?}" is1m=""
    # detect 1M context (either [1m] in id or "1M" in display_name)
    printf '%s' "$m" | grep -qiE '\[1m\]|1M context' && is1m="+1M"
    # normalize to short family name
    m=$(printf '%s' "$m" | sed \
        -e 's/[Ss]onnet.*/SNT/' \
        -e 's/[Oo]pus.*/OPS/'   \
        -e 's/[Hh]aiku.*/HKU/'  \
        -e 's/claude-//g')
    # fallback: still a messy string → truncate to 6 chars
    printf '%s' "$m" | grep -qE '^(SNT|OPS|HKU)' || m=$(printf '%s' "$m" | cut -c1-6)
    printf '%s' "${m}${is1m}"
}

host_alias() {
    local h; h=$(hostname -s 2>/dev/null)
    # Check user-defined host map: STATUSLINE_HOST_MAP="server1=PROD devbox=DEV"
    if [ -n "${STATUSLINE_HOST_MAP:-}" ]; then
        local pair
        for pair in $STATUSLINE_HOST_MAP; do
            local key="${pair%%=*}" val="${pair#*=}"
            if [ "$h" = "$key" ]; then
                printf '%s' "$val"
                return
            fi
        done
    fi
    # Not in map → treat as LOCAL
    printf 'LOCAL'
}

frontend_context() {
    local f="$HOME/.claude/.launch_context"
    local src=""
    [ -f "$f" ] && src=$(tr -d '[:space:]' < "$f" 2>/dev/null)
    [ -z "$src" ] && src="${STATUSLINE_FE_NAME:-CLAUDE}"
    printf '%s' "$src" | tr '[:lower:]' '[:upper:]'
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

is_project() {
    [ -n "${STATUSLINE_PROJECT_PATTERN:-}" ] || return 1
    printf '%s' "$CWD" | grep -qiE "$STATUSLINE_PROJECT_PATTERN" 2>/dev/null
}

is_live() {
    local h; h=$(host_alias)
    # Host alias explicitly marks production
    printf '%s' "$h" | grep -qiE '^(PROD|LIVE)$' && return 0
    # CWD path or branch name matches live pattern
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

        if [ "$STYLE" = "blend" ] && [ $next -lt $count ]; then
            # ▌ left-half block: fg=current bg, bg=next bg → smooth color fusion
            local nbg_n="${SBGS[$next]}"
            out+="$(cbg "$cbg_n")$(cfg "$cfg_n") ${text}$(cbg "$nbg_n")$(cfg "$cbg_n")▌"
        elif [ "$STYLE" = "powerline" ] && [ $next -lt $count ]; then
            local nbg_n="${SBGS[$next]}"
            out+="$(cbg "$cbg_n")$(cfg "$cfg_n") ${text} $(cbg "$nbg_n")$(cfg "$cbg_n")▶"
        elif [ "$STYLE" = "powerline" ] || [ "$STYLE" = "blend" ]; then
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
add_seg "${FE}:${MNAME}" $C_FE $C_WHITE

# S2 — CONTEXT (mapped host > active path > LOCAL)
HOST=$(host_alias)
ACTIVE_PATH=""
[ -f "$HOME/.claude/.active_path" ] && ACTIVE_PATH=$(tr -d '[:space:]' < "$HOME/.claude/.active_path" 2>/dev/null)
if [ "$HOST" != "LOCAL" ]; then
    add_seg "$HOST" $C_BLUE $C_WHITE
elif [ -n "$ACTIVE_PATH" ]; then
    add_seg "$ACTIVE_PATH" $C_LOCAL $C_WHITE
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

# S4 — CONTEXT WINDOW (countdown to auto-compact, approx)
# Claude Code's "X% until auto-compact" badge is internal state and is NOT exposed
# in the statusline JSON. We approximate it: remaining_percentage minus a reserved
# buffer (output reservation + safety margin) that Claude Code keeps before firing
# auto-compact. Tune the buffer via STATUSLINE_COMPACT_RESERVE (percentage points,
# default 16 — matched against the observed badge). Caveat: it is an APPROXIMATION;
# the real threshold is internal and the buffer (in pp) shifts if context_window_size
# changes (200k vs 1M). Set STATUSLINE_COMPACT_RESERVE=0 to show true free context.
CTX_REM=$(printf '%s' "$INPUT" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)
COMPACT_RESERVE="${STATUSLINE_COMPACT_RESERVE:-16}"
if [ -n "$CTX_REM" ]; then
    CTX_LEFT=$(( CTX_REM - COMPACT_RESERVE ))
    [ "$CTX_LEFT" -lt 0 ] && CTX_LEFT=0
    if [ "$CTX_LEFT" -ge 25 ]; then
        add_seg "CTX→${CTX_LEFT}%" $C_GREEN $C_WHITE
    elif [ "$CTX_LEFT" -ge 10 ]; then
        add_seg "CTX→${CTX_LEFT}%" $C_AMBER $C_BLACK
    else
        add_seg "CTX→${CTX_LEFT}%" $C_RED $C_WHITE
    fi
fi

# S5 — EFFORT
EFFORT=$(printf '%s' "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null)
[ -z "$EFFORT" ] && EFFORT=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
if [ -n "$EFFORT" ]; then
    case "$EFFORT" in
        low)    add_seg "EFF:L"   $C_GREEN  $C_WHITE ;;
        medium) add_seg "EFF:M"   $C_GREEN  $C_WHITE ;;
        high)   add_seg "EFF:H"   $C_AMBER  $C_BLACK ;;
        xhigh)  add_seg "EFF:XH"  $C_RED    $C_WHITE ;;
        max)    add_seg "EFF:MAX" $C_RED    $C_WHITE ;;
        *)      add_seg "EFF:${EFFORT:0:3}" $C_DARK $C_GRAY ;;
    esac
fi

# S6 — TIME (ops/debug only)
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
