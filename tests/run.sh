#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /private/tmp/agent-statusline-tests.XXXXXX)"
PASS_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok %d - %s\n' "$PASS_COUNT" "$1"
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'not ok - %s\nexpected to contain: %s\nactual: %s\n' "$label" "$needle" "$haystack" >&2
        exit 1
    fi
    pass "$label"
}

for script in "$ROOT"/install.sh "$ROOT"/statusline.sh "$ROOT"/examples/*.sh "$ROOT"/tests/*.sh; do
    bash -n "$script"
done
pass "all Bash files parse"

python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text())' \
    "$ROOT/scripts/patch-tui-config.py"
pass "OpenCode JSONC patcher parses"

mkdir -p "$TEST_ROOT/render-home/.claude"
printf '{"effortLevel":"high"}\n' > "$TEST_ROOT/render-home/.claude/settings.json"
payload=$(jq -n --arg cwd "$ROOT" '{
    cwd: $cwd,
    session_id: "test-session",
    model: {display_name: "Claude Opus 4.6"},
    context_window: {remaining_percentage: 80},
    effort: {level: "high"}
}')
rendered=$(printf '%s' "$payload" | HOME="$TEST_ROOT/render-home" AGENT_STATUSLINE_MODE=focus bash "$ROOT/statusline.sh")
plain=$(printf '%s' "$rendered" | perl -pe 's/\e\[[0-9;]*m//g')
assert_contains "$plain" "CLAUDE:OPS" "Claude renderer shows shortened model"
assert_contains "$plain" "CTX→64%" "Claude renderer computes context reserve"
assert_contains "$plain" "EFF:H" "Claude renderer shows effort"

mkdir -p "$TEST_ROOT/claude home/.claude"
printf '{"permissions":{"allow":["Read"]}}\n' > "$TEST_ROOT/claude home/.claude/settings.json"
HOME="$TEST_ROOT/claude home" bash "$ROOT/install.sh" claude >/dev/null
jq -e '.permissions.allow == ["Read"] and .statusLine.type == "command"' \
    "$TEST_ROOT/claude home/.claude/settings.json" >/dev/null
test -x "$TEST_ROOT/claude home/.claude/statusline.sh"
claude_command=$(jq -r '.statusLine.command' "$TEST_ROOT/claude home/.claude/settings.json")
HOME="$TEST_ROOT/claude home" bash -c "$claude_command" </dev/null >/dev/null
pass "Claude installer preserves settings and safely handles spaces"

mkdir -p "$TEST_ROOT/codex-home/.codex"
printf '%s\n' \
    'model = "gpt-5.6-codex"' \
    '' \
    '[tui]' \
    'status_line = ["old"]' \
    'status_line_use_colors = false' \
    'animations = false' \
    '' \
    '[features]' \
    'shell_snapshot = true' \
    > "$TEST_ROOT/codex-home/.codex/config.toml"
HOME="$TEST_ROOT/codex-home" CODEX_HOME="$TEST_ROOT/codex-home/.codex" bash "$ROOT/install.sh" codex >/dev/null
HOME="$TEST_ROOT/codex-home" CODEX_HOME="$TEST_ROOT/codex-home/.codex" bash "$ROOT/install.sh" codex >/dev/null
codex_config=$(<"$TEST_ROOT/codex-home/.codex/config.toml")
assert_contains "$codex_config" 'status_line = ["model-with-reasoning"' "Codex installer writes native status items"
assert_contains "$codex_config" 'animations = false' "Codex installer preserves unrelated TUI keys"
test "$(rg -c '^status_line = ' "$TEST_ROOT/codex-home/.codex/config.toml")" -eq 1
test "$(rg -c '^status_line_use_colors = ' "$TEST_ROOT/codex-home/.codex/config.toml")" -eq 1
pass "Codex installer is idempotent"

mkdir -p "$TEST_ROOT/opencode-home/.config/opencode"
# "$schema" below is a literal JSON property.
# shellcheck disable=SC2016
printf '%s\n' \
    '{' \
    '  // preserve this JSONC comment' \
    '  "$schema": "https://opencode.ai/tui.json",' \
    '  "theme": "system",' \
    '  "plugin": ["existing.plugin",],' \
    '}' \
    > "$TEST_ROOT/opencode-home/.config/opencode/tui.json"
HOME="$TEST_ROOT/opencode-home" bash "$ROOT/install.sh" opencode >/dev/null
HOME="$TEST_ROOT/opencode-home" bash "$ROOT/install.sh" opencode >/dev/null
opencode_config=$(<"$TEST_ROOT/opencode-home/.config/opencode/tui.json")
assert_contains "$opencode_config" "preserve this JSONC comment" "OpenCode installer preserves JSONC comments"
test "$(rg -o 'agent-statusline\.tsx' "$TEST_ROOT/opencode-home/.config/opencode/tui.json" | wc -l | tr -d ' ')" -eq 1
test -f "$TEST_ROOT/opencode-home/.config/opencode/plugins/agent-statusline.tsx"
pass "OpenCode installer registers one local plugin idempotently"

mkdir -p "$TEST_ROOT/opencode-comment-tail"
printf '%s\n' \
    '{' \
    '  "plugin": [' \
    '    "existing.plugin", // keep the item comment' \
    '  ],' \
    '}' \
    > "$TEST_ROOT/opencode-comment-tail/tui.json"
python3 "$ROOT/scripts/patch-tui-config.py" \
    "$TEST_ROOT/opencode-comment-tail/tui.json" \
    "$TEST_ROOT/opencode-comment-tail/statusline.tsx"
python3 -c 'import json, runpy, sys; m=runpy.run_path(sys.argv[1]); json.loads(m["jsonc_to_json"](open(sys.argv[2]).read()))' \
    "$ROOT/scripts/patch-tui-config.py" \
    "$TEST_ROOT/opencode-comment-tail/tui.json"
rg -F 'keep the item comment' "$TEST_ROOT/opencode-comment-tail/tui.json" >/dev/null
pass "OpenCode patcher handles comments after a trailing comma"

mkdir -p "$TEST_ROOT/opencode-empty"
python3 "$ROOT/scripts/patch-tui-config.py" \
    "$TEST_ROOT/opencode-empty/tui.json" \
    "$TEST_ROOT/opencode-empty/statusline.tsx"
jq -e '.plugin | length == 1' "$TEST_ROOT/opencode-empty/tui.json" >/dev/null
pass "OpenCode patcher creates a valid initial config"

for key in \
    'minimumReleaseAge: 1440' \
    'trustPolicy: no-downgrade' \
    'trustPolicyIgnoreAfter: 129600' \
    'blockExoticSubdeps: true' \
    'dangerouslyAllowAllBuilds: false' \
    'allowBuilds: {}'; do
    rg -F "$key" "$ROOT/pnpm-workspace.yaml" >/dev/null
done
pass "pnpm supply-chain hardening is complete"

printf '1..%d\n' "$PASS_COUNT"
printf '# temporary test artifacts: %s\n' "$TEST_ROOT"
