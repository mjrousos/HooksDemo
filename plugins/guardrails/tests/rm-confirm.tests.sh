#!/usr/bin/env bash
# Tests for plugins/guardrails/scripts/rm-confirm.sh.
#
# Covers:
#   - All non-interactive paths (early exits, false-positive guards, etc.)
#   - The "no GUI tools available -> deny" fail-closed path
#   - The "GUI tool says yes" path (mocked zenity that exits 0)
#   - The "GUI tool says no" path (mocked zenity that exits 1)
#
# Run directly:  bash plugins/guardrails/tests/rm-confirm.tests.sh
# Or via:        bash plugins/guardrails/tests/run.sh

set -u
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./_helpers.sh
. "$TEST_DIR/_helpers.sh"

HOOK="$TEST_DIR/../scripts/rm-confirm.sh"

# Build a minimal $bindir containing only the coreutils the hook needs, so
# `command -v zenity / kdialog / powershell.exe` returns false unless we
# explicitly add them.
make_isolated_bindir() {
    local bindir
    bindir=$(mktemp -d)
    local tool src
    for tool in jq grep cat tr tail sed base64 bash mktemp printf chmod; do
        src=$(command -v "$tool" 2>/dev/null) || continue
        ln -sf "$src" "$bindir/$tool"
    done
    printf '%s' "$bindir"
}

# Run hook with no GUI tools available at all (no zenity, kdialog, or
# powershell.exe on PATH and no DISPLAY).
run_hook_no_gui() {
    local payload=$1
    local bindir
    bindir=$(make_isolated_bindir)
    HOOK_OUT=$(printf '%s' "$payload" | env -i HOME="${HOME:-/tmp}" PATH="$bindir" bash "$HOOK" 2>/dev/null)
    HOOK_EC=$?
    rm -rf "$bindir"
}

# Run hook with a mocked zenity that always returns the given exit code
# (0 = yes, 1 = no). DISPLAY is set so prompt_zenity does not skip the tool.
run_hook_with_mock_zenity() {
    local payload=$1 zenity_ec=$2
    local bindir
    bindir=$(make_isolated_bindir)
    cat > "$bindir/zenity" <<EOF
#!/usr/bin/env bash
exit $zenity_ec
EOF
    chmod +x "$bindir/zenity"
    HOOK_OUT=$(printf '%s' "$payload" | env -i HOME="${HOME:-/tmp}" PATH="$bindir" DISPLAY=:0 bash "$HOOK" 2>/dev/null)
    HOOK_EC=$?
    rm -rf "$bindir"
}

# ---- non-interactive (early exit / pass-through) paths ----------------------

test_empty_input_passes_through() {
    run_hook "$HOOK" ''
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_unknown_tool_passes_through() {
    run_hook "$HOOK" '{"toolName":"view","toolArgs":"{\"path\":\"/x\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_shell_no_deletion_passes_through() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"ls -la /tmp\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_word_boundary_warm_not_rm() {
    # 'warm' contains 'rm' but should not match the rm token.
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"echo warm\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_word_boundary_deleted_not_del() {
    # 'deleted' contains 'del' but should not match the del token.
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"echo deleted\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_empty_command_passes_through() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

# ---- prompt paths (mocked) --------------------------------------------------

test_no_gui_tools_fails_closed() {
    # Deletion command + no zenity/kdialog/powershell.exe -> deny with install hint.
    run_hook_no_gui '{"toolName":"bash","toolArgs":"{\"command\":\"rm -rf /tmp/xyz\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
    assert_contains "$HOOK_OUT" 'sudo apt install zenity'     "install hint"
}

test_zenity_yes_allows() {
    run_hook_with_mock_zenity '{"toolName":"bash","toolArgs":"{\"command\":\"rm -rf /tmp/xyz\"}"}' 0
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_zenity_no_denies() {
    run_hook_with_mock_zenity '{"toolName":"bash","toolArgs":"{\"command\":\"rm -rf /tmp/xyz\"}"}' 1
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
    assert_contains "$HOOK_OUT" 'User declined'                "user-declined reason"
}

# Verify each deletion token actually triggers the prompt by mocking zenity to
# say "no" so we get back a deterministic deny without a real dialog or hang.

test_token_rm_triggers_prompt() {
    run_hook_with_mock_zenity '{"toolName":"bash","toolArgs":"{\"command\":\"rm /tmp/x\"}"}' 1
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

test_token_rmdir_triggers_prompt() {
    run_hook_with_mock_zenity '{"toolName":"bash","toolArgs":"{\"command\":\"rmdir /tmp/x\"}"}' 1
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

test_token_remove_item_triggers_prompt() {
    run_hook_with_mock_zenity '{"toolName":"powershell","toolArgs":"{\"command\":\"Remove-Item C:\\\\temp\\\\x\"}"}' 1
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

test_token_remove_itemproperty_triggers_prompt() {
    run_hook_with_mock_zenity '{"toolName":"powershell","toolArgs":"{\"command\":\"Remove-ItemProperty -Path HKCU:\\\\X -Name Y\"}"}' 1
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

# ---- run --------------------------------------------------------------------

printf '%srm-confirm.sh%s\n' "$BOLD" "$RESET"

run_test test_empty_input_passes_through
run_test test_unknown_tool_passes_through
run_test test_shell_no_deletion_passes_through
run_test test_word_boundary_warm_not_rm
run_test test_word_boundary_deleted_not_del
run_test test_empty_command_passes_through

run_test test_no_gui_tools_fails_closed
run_test test_zenity_yes_allows
run_test test_zenity_no_denies

run_test test_token_rm_triggers_prompt
run_test test_token_rmdir_triggers_prompt
run_test test_token_remove_item_triggers_prompt
run_test test_token_remove_itemproperty_triggers_prompt

finish
