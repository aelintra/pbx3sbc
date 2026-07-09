#!/bin/bash
#
# Seed lab peering data (Phases 1–2 outbound, Phase 3–4 inbound scaffold).
# Golden fleet nodes send PSTN via PJSIP Egress → this SBC; SBC relays to carrier.
#
# Required:
#   CARRIER_ADDRESS   sip:host:5060  (test relay carrier — IP-trusted peer)
#
# Optional:
#   CARRIER_FAILOVER_ADDRESS  second carrier for Phase 2 failover
#   ASTERISK_GW_ADDRESS       default sip:54.236.153.81:5060 (golden public SIP)
#   INBOUND_DID_PREFIX        default empty (catch-all inbound DID → Asterisk gw)
#
# Usage:
#   CARRIER_ADDRESS='sip:203.0.113.50:5060' sudo -E ./scripts/peering-seed-lab.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/db-config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/db-config.sh" 2>/dev/null || true
fi
if [[ -f /etc/opensips/.mysql_credentials ]]; then
  # shellcheck disable=SC1091
  source /etc/opensips/.mysql_credentials 2>/dev/null || true
  DB_PASS="${PASSWORD:-${DB_PASS:-}}"
  DB_USER="${USER:-${DB_USER:-opensips}}"
  DB_NAME="${DATABASE:-${DB_NAME:-opensips}}"
fi

DB_PASS="${DB_PASS:-}"
CARRIER_ADDRESS="${CARRIER_ADDRESS:-}"
CARRIER_FAILOVER_ADDRESS="${CARRIER_FAILOVER_ADDRESS:-}"
ASTERISK_GW_ADDRESS="${ASTERISK_GW_ADDRESS:-sip:54.236.153.81:5060}"
INBOUND_DID_PREFIX="${INBOUND_DID_PREFIX:-}"

if [[ -z "$DB_PASS" || "$DB_PASS" == "your-password" ]]; then
  echo "Error: set DB_PASS or configure /etc/opensips/.mysql_credentials" >&2
  exit 1
fi
if [[ -z "$CARRIER_ADDRESS" ]]; then
  echo "Error: CARRIER_ADDRESS required (e.g. sip:203.0.113.50:5060)" >&2
  exit 1
fi
if [[ ! "$CARRIER_ADDRESS" =~ ^sip: ]]; then
  echo "Error: CARRIER_ADDRESS must be a SIP URI (sip:host:port)" >&2
  exit 1
fi

GWLIST="1"
if [[ -n "$CARRIER_FAILOVER_ADDRESS" ]]; then
  GWLIST="1,2"
fi

mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
-- Outbound carriers (group 0) + inbound source match via is_from_gw
-- NOTE: fleet node Asterisk (gwid 10) is in dr_gateways for inbound DID relay only.
-- opensips.cfg must check CHECK_IS_FROM_ASTERISK + do_routing(0) BEFORE is_from_gw,
-- or golden egress INVITEs are misclassified as FROM_CARRIER.
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('1', 0, '${CARRIER_ADDRESS}', 0, '', '', 0, 0, 'Lab carrier primary')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;

INSERT INTO dr_rules (ruleid, groupid, prefix, timerec, priority, routeid, gwlist, sort_alg, sort_profile, attrs, description)
VALUES
  (1, '0', '', NULL, 10, NULL, '${GWLIST}', 'N', NULL, '', 'Default outbound — Egress path from fleet nodes')
ON DUPLICATE KEY UPDATE gwlist=VALUES(gwlist), description=VALUES(description);

-- Asterisk backend for inbound DID delivery (group 1) — fleet node public SIP
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('10', 0, '${ASTERISK_GW_ADDRESS}', 0, '', '', 0, 0, 'Fleet node Asterisk (golden)')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;

INSERT INTO dr_rules (ruleid, groupid, prefix, timerec, priority, routeid, gwlist, sort_alg, sort_profile, attrs, description)
VALUES
  (10, '1', '${INBOUND_DID_PREFIX}', NULL, 10, NULL, '10', 'N', NULL, '', 'Inbound DID → fleet node')
ON DUPLICATE KEY UPDATE prefix=VALUES(prefix), gwlist=VALUES(gwlist);
SQL

if [[ -n "$CARRIER_FAILOVER_ADDRESS" ]]; then
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('2', 0, '${CARRIER_FAILOVER_ADDRESS}', 0, '', '', 0, 0, 'Lab carrier failover')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;
SQL
fi

echo "OK: dr_gateways + dr_rules seeded (outbound gwlist=${GWLIST})"
echo "Reload drouting:"
if command -v opensips-cli >/dev/null 2>&1; then
  opensips-cli -x dr_reload && echo "  dr_reload OK"
elif [[ -p /var/run/opensips/opensips_fifo ]]; then
  echo "dr_reload" > /var/run/opensips/opensips_fifo && echo "  dr_reload sent via fifo"
else
  echo "  Run manually: opensips-cli -x dr_reload (or restart opensips)"
fi

echo
echo "Verify Asterisk source is in dispatcher (for do_routing gate):"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT setid,destination,attrs FROM dispatcher;"
