#!/usr/bin/env bash
# Tests for plugins/guardrails/scripts/url-allowlist.sh.
#
# Run directly:  bash plugins/guardrails/tests/url-allowlist.tests.sh
# Or via:        bash plugins/guardrails/tests/run.sh

set -u
TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./_helpers.sh
. "$TEST_DIR/_helpers.sh"

HOOK="$TEST_DIR/../scripts/url-allowlist.sh"

# ---- pass-through paths ------------------------------------------------------

test_empty_input_passes_through() {
    run_hook "$HOOK" ''
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_unknown_tool_passes_through() {
    run_hook "$HOOK" '{"toolName":"view","toolArgs":"{\"path\":\"/etc/hosts\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_web_fetch_no_url_arg_passes_through() {
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_bash_no_web_command_passes_through() {
    # No curl/wget/Invoke-* in the command -> hook leaves it alone, even if a
    # disallowed URL is mentioned in the text.
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"echo https://evil.example.com\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

# ---- allow paths -------------------------------------------------------------

test_web_fetch_allowed_host() {
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://github.com/octocat\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_web_fetch_allowed_subdomain_via_dot_rule() {
    # api.github.com matches the github.com entry via the dot-suffix rule.
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://api.github.com/repos/x/y\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_web_fetch_url_with_port() {
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://github.com:443/x\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_web_fetch_url_with_userinfo() {
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://user:pw@github.com/x\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_web_search_allowed_url_in_query() {
    run_hook "$HOOK" '{"toolName":"web_search","toolArgs":"{\"query\":\"see https://github.com/octocat\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_bash_curl_allowed_host() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"curl -sSL https://github.com/x\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_bash_wget_allowed_host() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"wget https://raw.githubusercontent.com/x/y/main/z\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

test_powershell_invoke_webrequest_allowed() {
    run_hook "$HOOK" '{"toolName":"powershell","toolArgs":"{\"command\":\"Invoke-WebRequest https://github.com/x\"}"}'
    assert_eq "$HOOK_EC"  0  "exit code"
    assert_eq "$HOOK_OUT" "" "stdout"
}

# ---- deny paths --------------------------------------------------------------

test_web_fetch_disallowed_host_denied() {
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://evil.example.com/x\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
    assert_contains "$HOOK_OUT" "evil.example.com"            "host in reason"
}

test_web_fetch_confusable_host_denied() {
    # evilgithub.com must NOT match github.com -- the entry must be matched
    # on a dot boundary, never as a substring.
    run_hook "$HOOK" '{"toolName":"web_fetch","toolArgs":"{\"url\":\"https://evilgithub.com/x\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
    assert_contains "$HOOK_OUT" "evilgithub.com"              "host in reason"
}

test_web_search_disallowed_url_in_query_denied() {
    run_hook "$HOOK" '{"toolName":"web_search","toolArgs":"{\"query\":\"see https://evil.example.com/x\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

test_bash_curl_disallowed_denied() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"curl -sSL https://evil.example.com/x\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
}

test_bash_curl_multiple_urls_one_disallowed_denied() {
    run_hook "$HOOK" '{"toolName":"bash","toolArgs":"{\"command\":\"curl https://github.com/a && curl https://evil.example.com/b\"}"}'
    assert_eq "$HOOK_EC" 0 "exit code"
    assert_contains "$HOOK_OUT" '"permissionDecision":"deny"' "deny json"
    assert_contains "$HOOK_OUT" "evil.example.com"           "denied host in reason"
}

# ---- run ---------------------------------------------------------------------

printf '%surl-allowlist.sh%s\n' "$BOLD" "$RESET"

run_test test_empty_input_passes_through
run_test test_unknown_tool_passes_through
run_test test_web_fetch_no_url_arg_passes_through
run_test test_bash_no_web_command_passes_through

run_test test_web_fetch_allowed_host
run_test test_web_fetch_allowed_subdomain_via_dot_rule
run_test test_web_fetch_url_with_port
run_test test_web_fetch_url_with_userinfo
run_test test_web_search_allowed_url_in_query
run_test test_bash_curl_allowed_host
run_test test_bash_wget_allowed_host
run_test test_powershell_invoke_webrequest_allowed

run_test test_web_fetch_disallowed_host_denied
run_test test_web_fetch_confusable_host_denied
run_test test_web_search_disallowed_url_in_query_denied
run_test test_bash_curl_disallowed_denied
run_test test_bash_curl_multiple_urls_one_disallowed_denied

finish
