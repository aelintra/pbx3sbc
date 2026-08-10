#!/usr/bin/env bash
#
# mi-localhost-bind-test.sh
#
# Regression test for PRE_RELEASE_SAFETY_DEBT item 10 (pbx3sbc):
#   - The OpenSIPS httpd listener (MI JSON-RPC + Prometheus /metrics) has no
#     auth of its own, so it must be bound to 127.0.0.1 only, never 0.0.0.0.
#   - install.sh must not open a public UFW rule for port 8888.
#
# This is a grep-based contract test (no OpenSIPS runtime needed) so it can
# run in CI / on a laptop without a live SBC.
#
# Run: ./tests/mi-localhost-bind-test.sh
# Exit 0 on pass, 1 on failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE="$REPO_DIR/config/opensips.cfg.template"
INSTALL_SH="$REPO_DIR/install.sh"

fails=0

ok()   { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

if [[ ! -f "$TEMPLATE" ]]; then
    fail "template not found at $TEMPLATE"
    echo "Aborting: cannot continue without the template." >&2
    exit 1
fi

# ---- httpd must bind to 127.0.0.1, never 0.0.0.0 ----

if grep -Eq 'modparam\("httpd",\s*"ip",\s*"0\.0\.0\.0"\)' "$TEMPLATE"; then
    fail "opensips.cfg.template still binds httpd to 0.0.0.0 (MI/metrics would be reachable off-box)"
else
    ok "opensips.cfg.template does not bind httpd to 0.0.0.0"
fi

if grep -Eq 'modparam\("httpd",\s*"ip",\s*"127\.0\.0\.1"\)' "$TEMPLATE"; then
    ok "opensips.cfg.template binds httpd to 127.0.0.1"
else
    fail "opensips.cfg.template does not bind httpd to 127.0.0.1 (expected modparam(\"httpd\", \"ip\", \"127.0.0.1\"))"
fi

# ---- install.sh must not open a public firewall rule for MI/metrics port 8888 ----

if [[ -f "$INSTALL_SH" ]]; then
    # Look for an *active* (non-comment) add_ufw_rule_if_missing call for 8888.
    if grep -E '^[^#]*add_ufw_rule_if_missing\s+"8888' "$INSTALL_SH" >/dev/null; then
        fail "install.sh still opens a public UFW rule for port 8888 (MI/metrics is localhost-only)"
    else
        ok "install.sh does not open a public UFW rule for port 8888"
    fi
else
    fail "install.sh not found at $INSTALL_SH"
fi

echo
if [[ "$fails" -gt 0 ]]; then
    echo "$fails assertion(s) FAILED" >&2
    exit 1
fi

echo "PASS: mi-localhost-bind-test (0 failures)"
exit 0
