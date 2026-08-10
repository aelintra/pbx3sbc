#!/usr/bin/env bash
#
# sql-escape-contract-test.sh
#
# Regression test for PRE_RELEASE_SAFETY_DEBT item 11 (pbx3sbc):
#   - door-knock INSERTs, the failed_registrations INSERT, and the Slice D
#     usrloc SELECTs all build SQL by string concatenation (OpenSIPS's
#     sql_query() has no prepared-statement support for free-form values).
#   - Every free-form SIP value (User-Agent, From user/domain, Request-URI
#     username, response reason, etc.) that gets single-quoted into one of
#     these queries MUST be passed through the core {s.escape.common}
#     transformation first.
#
# This is a grep-based contract test (no OpenSIPS runtime needed). It is
# intentionally strict about the *raw* (unescaped) concatenation patterns so
# that reverting a fix (e.g. swapping `$(ua{s.escape.common})` back to a bare
# `$ua`) fails the test immediately.
#
# Run: ./tests/sql-escape-contract-test.sh
# Exit 0 on pass, 1 on failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_DIR/config/opensips.cfg.template"

fails=0

ok()   { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

if [[ ! -f "$TEMPLATE" ]]; then
    echo "FAIL: template not found at $TEMPLATE" >&2
    exit 1
fi

# ---- Negative checks: raw/unescaped concatenation must NOT be present ----
# Pattern: `+ $FIELD +` (any whitespace) with no {s.escape.common} transform.
# If someone reverts a fix by swapping $(FIELD{s.escape.common}) back to a
# bare $FIELD, this is exactly the string that would reappear.

# $ua/$fU/$fd/$rr are only ever concatenated into SQL string literals (never
# into a bare URI), so a generic `+ $FIELD +` check is safe/specific for them.
declare -a RAW_FIELDS=("\\\$ua" "\\\$fU" "\\\$fd" "\\\$rr")
for field_pat in "${RAW_FIELDS[@]}"; do
    # Strip backslashes for a human-readable label.
    label="${field_pat//\\/}"
    if grep -Eq "\+[[:space:]]*${field_pat}[[:space:]]*\+" "$TEMPLATE"; then
        fail "found raw unescaped concatenation of $label into a query (expected \$(${label#\$}{s.escape.common}))"
    else
        ok "no raw unescaped concatenation of $label found"
    fi
done

# $tU and $rU are also used in non-SQL URI concatenation (e.g. building a new
# Request-URI), which is not a SQL-injection risk, so scope the raw-concat
# check to the SQL `username='...'` clause pattern specifically.
for field in tU rU; do
    if grep -Eq "username='\"[[:space:]]*\+[[:space:]]*\\\$${field}[[:space:]]*\+" "$TEMPLATE"; then
        fail "found raw unescaped \$${field} concatenated directly into a SQL username='...' clause"
    else
        ok "no raw unescaped \$${field} found in a SQL username='...' clause"
    fi
done

# ---- Positive checks: expected escape sites are present ----

check_min_count() {
    local pattern="$1" min="$2" desc="$3"
    local count
    count=$(grep -cE "$pattern" "$TEMPLATE")
    if [[ "$count" -ge "$min" ]]; then
        ok "$desc (found $count, expected >= $min)"
    else
        fail "$desc (found $count, expected >= $min) — pattern: $pattern"
    fi
}

# door_knock_attempts INSERTs: user_agent, method, request_uri fields escaped
check_min_count '\$\(ua\{s\.escape\.common\}\)' 5 "door-knock/registration INSERTs escape \$ua via {s.escape.common}"
check_min_count '\$\(rm\{s\.escape\.common\}\)' 5 "door-knock INSERTs escape \$rm (method) via {s.escape.common}"
check_min_count '\$\(ru\{s\.escape\.common\}\)' 5 "door-knock INSERTs escape \$ru (Request-URI) via {s.escape.common}"
check_min_count '\$\(rd\{s\.escape\.common\}\)|\$\(var\(domain\)\{s\.escape\.common\}\)' 5 "door-knock INSERTs escape the domain field via {s.escape.common}"

# Slice D SELECTs: From user/domain and shortuid username escaped
check_min_count '\$\(fU\{s\.escape\.common\}\)' 1 "Slice D From-user SELECT escapes \$fU via {s.escape.common}"
check_min_count '\$\(fd\{s\.escape\.common\}\)' 1 "Slice D From-domain SELECT escapes \$fd via {s.escape.common}"
check_min_count '\$\(rU\{s\.escape\.common\}\)' 1 "Slice D shortuid SELECT escapes \$rU via {s.escape.common}"

# failed_registrations INSERT: username, domain, user-agent, response_reason escaped
check_min_count '\$\(tU\{s\.escape\.common\}\)' 1 "failed_registrations INSERT escapes \$tU (username) via {s.escape.common}"
check_min_count '\$\(tu\{uri\.domain\}\{s\.escape\.common\}\)' 1 "failed_registrations INSERT escapes To-domain via {s.escape.common}"
check_min_count '\$\(var\(log_user_agent\)\{s\.escape\.common\}\)' 1 "failed_registrations INSERT escapes user_agent via {s.escape.common}"
check_min_count '\$\(rr\{s\.escape\.common\}\)' 1 "failed_registrations INSERT escapes \$rr (response reason) via {s.escape.common}"

# ---- Charset gate for shortuid-like fields must still be present (Slice D) ----

if grep -Eq '\$rU =~ "\^\[0-9bcdfghjkmnpqrstvwxyz\]\+\$"' "$TEMPLATE"; then
    ok "Slice D shortuid charset gate on \$rU is present"
else
    fail "Slice D shortuid charset gate on \$rU is missing (expected the ^[0-9bcdfghjkmnpqrstvwxyz]+\$ regex before route(SLICE_D_SHORTUID_REPAIR))"
fi

# ---- Documentation: a comment near the risky lines should explain the approach ----

if grep -Eq 'SECURITY \(safety-debt #11\)' "$TEMPLATE"; then
    ok "SQL-escaping approach is documented near the risky lines (safety-debt #11 comment present)"
else
    fail "no safety-debt #11 documentation comment found near the risky SQL concat lines"
fi

echo
if [[ "$fails" -gt 0 ]]; then
    echo "$fails assertion(s) FAILED" >&2
    exit 1
fi

echo "PASS: sql-escape-contract-test (0 failures)"
exit 0
