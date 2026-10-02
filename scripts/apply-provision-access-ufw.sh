#!/usr/bin/env bash
# Apply SBC provision HTTPS (:41363) access lockdown from JSON state.
# Spec: pbx3-directory/docs/SBC_PROVISION_ACCESS_REQUIREMENTS.md (C10)
#
# Usage (root / via sudo from www-data):
#   apply-provision-access-ufw.sh /path/to/provision-access.json
#   apply-provision-access-ufw.sh --status
#
# Note: php-fpm ProtectSystem=full (/etc read-only even under sudo).
# Mutating apply needs systemd ReadWritePaths=/etc/ufw — see
# scripts/setup-php-fpm-ufw-write.sh
#
# UFW comments:
#   pbx3sbc-prov <comment>  — allowlist when lockdown on
#   pbx3sbc-prov-open       — world-open 41363 when lockdown off
#
set -euo pipefail

MARKER="pbx3sbc-prov"
MARKER_OPEN="pbx3sbc-prov-open"
PORT=41363
UFW="${UFW_BIN:-/usr/sbin/ufw}"

die() { echo "apply-provision-access-ufw: $*" >&2; exit 1; }
log() { echo "apply-provision-access-ufw: $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root (got uid=$(id -u))"
[ -x "$UFW" ] || die "ufw not found at $UFW"
command -v python3 >/dev/null 2>&1 || die "python3 required"

print_status() {
    echo "=== provision-access UFW (port ${PORT}) ==="
    "$UFW" status numbered 2>/dev/null | grep -E "${PORT}/tcp|${MARKER}" || echo "(no ${PORT}/tcp rules)"
}

if [[ "${1:-}" == "--status" ]]; then
    print_status
    exit 0
fi

STATE_FILE="${1:-}"
[ -n "$STATE_FILE" ] || die "usage: $0 <state.json> | --status"
[ -f "$STATE_FILE" ] || die "state file not found: $STATE_FILE"

if [ ! -w /etc/ufw/user.rules ]; then
    die "'/etc/ufw/user.rules' is not writable (uid=$(id -u)). php-fpm ProtectSystem=full blocks /etc — run sudo ./scripts/setup-php-fpm-ufw-write.sh && sudo systemctl restart php*-fpm"
fi

first_rule_num() {
    local pattern="$1"
    local num
    num=$("$UFW" status numbered 2>/dev/null | grep -F "$pattern" | sed -n 's/^\[\s*\([0-9][0-9]*\)\].*/\1/p' | head -1) || true
    echo "$num"
}

delete_comment_rules() {
    local needle="$1"
    local num
    while true; do
        num=$(first_rule_num "# ${needle}")
        [ -n "$num" ] || break
        "$UFW" --force delete "$num" >/dev/null
    done
}

delete_open_port_any() {
    local num
    while true; do
        num=$("$UFW" status numbered 2>/dev/null | sed -n \
            "s/^\[\s*\([0-9][0-9]*\)\]\s\+${PORT}\/tcp\s\+ALLOW IN\s\+Anywhere\s*$/\1/p" | head -1) || true
        [ -n "$num" ] || break
        "$UFW" --force delete "$num" >/dev/null
    done
    while true; do
        num=$("$UFW" status numbered 2>/dev/null | sed -n \
            "s/^\[\s*\([0-9][0-9]*\)\]\s\+${PORT}\/tcp (v6)\s\+ALLOW IN\s\+Anywhere (v6)\s*$/\1/p" | head -1) || true
        [ -n "$num" ] || break
        "$UFW" --force delete "$num" >/dev/null
    done
}

mapfile -t ROWS < <(python3 -c '
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
print("LOCKDOWN=" + ("1" if bool(data.get("lockdown", False)) else "0"))
for row in data.get("allows") or []:
    cidr = (row.get("cidr") or row.get("ip_or_cidr") or "").strip()
    comment = (row.get("comment") or "").strip().replace("\n", " ")[:80]
    if cidr:
        print("ALLOW|%s|%s" % (cidr, comment))
' "$STATE_FILE")

LOCKDOWN=0
ALLOWS=()
for line in "${ROWS[@]}"; do
    if [[ "$line" == LOCKDOWN=* ]]; then
        LOCKDOWN="${line#LOCKDOWN=}"
        continue
    fi
    if [[ "$line" == ALLOW\|* ]]; then
        ALLOWS+=("${line#ALLOW|}")
    fi
done

delete_comment_rules "${MARKER} "
delete_comment_rules "${MARKER_OPEN}"

if [[ "$LOCKDOWN" == "1" ]]; then
    if [[ ${#ALLOWS[@]} -eq 0 ]]; then
        die "lockdown enabled but allow list is empty — refusing"
    fi
    delete_open_port_any
    for entry in "${ALLOWS[@]}"; do
        cidr="${entry%%|*}"
        rest="${entry#*|}"
        comment="${rest%%|*}"
        [ -n "$comment" ] || comment="allow"
        comment=$(echo "$comment" | tr -cd 'A-Za-z0-9 ._/@+-' | cut -c1-60)
        "$UFW" allow from "$cidr" to any port "$PORT" proto tcp comment "${MARKER} ${comment}" >/dev/null \
            || die "failed to allow from $cidr"
        log "allow ${cidr} → ${PORT}/tcp (${comment})"
    done
    log "lockdown ON (${#ALLOWS[@]} source(s))"
else
    delete_open_port_any
    "$UFW" allow "${PORT}/tcp" comment "${MARKER_OPEN}" >/dev/null || die "failed to open ${PORT}/tcp"
    log "opened ${PORT}/tcp (Anywhere) — lockdown OFF"
fi

print_status
exit 0
