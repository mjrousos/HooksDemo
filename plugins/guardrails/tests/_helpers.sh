#!/usr/bin/env bash
# Test helpers for the guardrails hook script tests (bash side).
# Sourced by *.tests.sh files. Provides:
#
#   run_test <fn>             - runs a test function in a subshell;
#                               prints PASS/FAIL with captured assertion errors.
#   assert_eq <act> <exp> [l] - fails if $act != $exp.
#   assert_contains    <h> <n> [l] - fails if $h does not contain $n.
#   assert_not_contains <h> <n> [l] - fails if $h contains $n.
#   run_hook <hook> <payload> - runs $hook with $payload on stdin;
#                               sets HOOK_OUT, HOOK_EC, HOOK_ERR.
#   finish                    - prints summary; exits 1 if any failures.

PASS=0
FAIL=0
HOOK_OUT=""
HOOK_EC=0
HOOK_ERR=""

if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    GREEN=$(tput setaf 2); RED=$(tput setaf 1); RESET=$(tput sgr0); BOLD=$(tput bold)
else
    GREEN=""; RED=""; RESET=""; BOLD=""
fi

run_test() {
    local fn=$1
    local errfile
    errfile=$(mktemp)
    if ( "$fn" ) 2>"$errfile"; then
        PASS=$((PASS+1))
        printf '  %s[PASS]%s %s\n' "$GREEN" "$RESET" "$fn"
    else
        FAIL=$((FAIL+1))
        printf '  %s[FAIL]%s %s\n' "$RED" "$RESET" "$fn"
        sed 's/^/         /' "$errfile" >&2
    fi
    rm -f "$errfile"
}

assert_eq() {
    local actual=$1 expected=$2 label=${3:-value}
    if [ "$actual" = "$expected" ]; then return 0; fi
    printf '%s mismatch:\n  expected: [%s]\n  actual:   [%s]\n' \
        "$label" "$expected" "$actual" >&2
    return 1
}

assert_contains() {
    local haystack=$1 needle=$2 label=${3:-output}
    case "$haystack" in
        *"$needle"*) return 0 ;;
    esac
    printf '%s missing %q:\n  actual: [%s]\n' "$label" "$needle" "$haystack" >&2
    return 1
}

assert_not_contains() {
    local haystack=$1 needle=$2 label=${3:-output}
    case "$haystack" in
        *"$needle"*) ;;
        *) return 0 ;;
    esac
    printf '%s unexpectedly contains %q:\n  actual: [%s]\n' "$label" "$needle" "$haystack" >&2
    return 1
}

run_hook() {
    local hook=$1 payload=$2
    local errfile
    errfile=$(mktemp)
    HOOK_OUT=$(printf '%s' "$payload" | bash "$hook" 2>"$errfile")
    HOOK_EC=$?
    HOOK_ERR=$(cat "$errfile")
    rm -f "$errfile"
}

finish() {
    local total=$((PASS+FAIL))
    printf '\n'
    if [ $FAIL -eq 0 ]; then
        printf '%s%s%d/%d passed%s\n' "$BOLD" "$GREEN" "$PASS" "$total" "$RESET"
        exit 0
    else
        printf '%s%s%d/%d failed (%d passed)%s\n' "$BOLD" "$RED" "$FAIL" "$total" "$PASS" "$RESET"
        exit 1
    fi
}
