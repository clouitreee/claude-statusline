#!/usr/bin/env bash
# track-active-path.sh — PreToolUse hook
#
# Writes the directory a session is currently working in to
# ~/.claude/.active_path-<session_id>, which statusline.sh reads for the
# "active path" label in the context segment (see README § Active path).
#
# IMPORTANT: namespaced by session_id, not a single shared file. Claude Code
# can have several sessions open at once (multiple terminal tabs/panes), and
# a PreToolUse hook fires per session — a single shared ~/.claude/.active_path
# would let any session's tool call silently overwrite what every other open
# session's statusline displays. session_id is stable and unique for the
# lifetime of a session (Claude Code hook input schema), so it's the correct
# isolation key.
#
# Install: add as a PreToolUse hook in your Claude Code settings, matching
# whichever tools you want to track (Read/Edit/Write/Grep/LS below).

INPUT=$(cat 2>/dev/null || true)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Opportunistic cleanup: drop per-session files older than 14 days (sessions
# long since closed). Narrow scope on purpose — exact filename pattern only,
# no recursion.
find "$HOME/.claude" -maxdepth 1 -name '.active_path-*' -mtime +14 -delete 2>/dev/null

FILE=""
case "$TOOL" in
    Read|Edit|Write)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
        ;;
    Grep)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
        ;;
    LS)
        FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
        ;;
esac

[ -z "$FILE" ] && exit 0

DIR=$(dirname "$FILE" 2>/dev/null)
[ "$DIR" = "." ] && DIR="$FILE"

# Relative to the project's cwd when possible
if [ -n "$CWD" ]; then
    REL="${DIR#"$CWD"/}"
    [ "$REL" = "$DIR" ] && REL=$(basename "$DIR")
else
    REL=$(basename "$DIR")
fi

[ -z "$REL" ] || [ "$REL" = "." ] && exit 0

# Cap at 2 path segments so the statusline segment stays short
SHORT=$(printf '%s' "$REL" | rev | cut -d'/' -f1-2 | rev)

if [ -n "$SESSION_ID" ]; then
    printf '%s' "$SHORT" > "$HOME/.claude/.active_path-$SESSION_ID"
else
    printf '%s' "$SHORT" > "$HOME/.claude/.active_path"
fi
exit 0
