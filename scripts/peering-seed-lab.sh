#!/bin/bash
#
# Seed lab peering data (Phases 1–2 outbound, Phase 3–4 inbound).
# Golden fleet nodes send PSTN via PJSIP Egress → this SBC; SBC relays to carrier.
# Inbound: Magrathea (Tier-2) signaling IPs → DID prefix → Asterisk gw.
#
# Required:
#   CARRIER_ADDRESS   sip:host:5060  (failover / legacy primary — e.g. ael.vcloudpbx.com)
#
# Optional:
#   CARRIER_FAILOVER_ADDRESS     legacy second outbound (gwid 2); prefer Phase 2 Magrathea path below
#   MAGRATHEA_OUTBOUND_ADDRESS   default sip:sipipgw.magrathea.net:5060 (gwid 20, Phase 2 primary)
#   SEED_MAGRATHEA_OUTBOUND=0    skip Magrathea outbound gwid 20 (default: seed when SEED_MAGRATHEA=1)
#   ASTERISK_GW_ADDRESS          default sip:54.236.153.81:5060 (golden public SIP)
#   INBOUND_DID_PREFIX           default 01924918076 (lab Magrathea DID → Asterisk gw)
#   SEED_MAGRATHEA=0             skip Magrathea inbound source gateways (default: seed them)
#
# Phase 2 lab (2026-07-13): gwlist 20,1 — Magrathea sipipgw primary, Brindley/ael failover.
#
# Usage:
#   CARRIER_ADDRESS='sip:ael.vcloudpbx.com:5060' sudo -E ./scripts/peering-seed-lab.sh
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
INBOUND_DID_PREFIX="${INBOUND_DID_PREFIX:-01924918076}"
SEED_MAGRATHEA="${SEED_MAGRATHEA:-1}"
MAGRATHEA_OUTBOUND_ADDRESS="${MAGRATHEA_OUTBOUND_ADDRESS:-sip:sipipgw.magrathea.net:5060}"
SEED_MAGRATHEA_OUTBOUND="${SEED_MAGRATHEA_OUTBOUND:-$SEED_MAGRATHEA}"

if [[ -z "$DB_PASS" || "$DB_PASS" == "your-password" ]]; then
  echo "Error: set DB_PASS or configure /etc/opensips/.mysql_credentials" >&2
  exit 1
fi
if [[ -z "$CARRIER_ADDRESS" ]]; then
  echo "Error: CARRIER_ADDRESS required (e.g. sip:ael.vcloudpbx.com:5060)" >&2
  exit 1
fi
if [[ ! "$CARRIER_ADDRESS" =~ ^sip: ]]; then
  echo "Error: CARRIER_ADDRESS must be a SIP URI (sip:host:port)" >&2
  exit 1
fi

# Phase 2: Magrathea outbound (20) primary + Brindley/ael (1) failover when Magrathea outbound seeded
GWLIST="1"
RULE_DESC="Default outbound — Egress path from fleet nodes"
if [[ "$SEED_MAGRATHEA_OUTBOUND" == "1" ]]; then
  GWLIST="20,1"
  RULE_DESC="Outbound failover — Magrathea (20) then Brindley (1)"
elif [[ -n "$CARRIER_FAILOVER_ADDRESS" ]]; then
  GWLIST="1,2"
  RULE_DESC="Outbound failover — gwid 1 then 2"
fi

if [[ "$SEED_MAGRATHEA_OUTBOUND" == "1" ]]; then
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('20', 0, '${MAGRATHEA_OUTBOUND_ADDRESS}', 0, '', '', 0, 0, 'Magrathea outbound (sipipgw IP auth)')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;
SQL
  echo "OK: Magrathea outbound gateway (gwid 20) ${MAGRATHEA_OUTBOUND_ADDRESS}"
fi

mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
-- Outbound carriers (group 0) + inbound source match via is_from_gw
-- NOTE: fleet node Asterisk (gwid 10) is in dr_gateways for inbound DID relay only.
-- opensips.cfg must check CHECK_IS_FROM_ASTERISK + do_routing(0) BEFORE is_from_gw,
-- or golden egress INVITEs are misclassified as FROM_CARRIER.
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('1', 0, '${CARRIER_ADDRESS}', 0, '', '', 0, 0, 'Brindley/Aelintra failover (lab)')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;

INSERT INTO dr_rules (ruleid, groupid, prefix, timerec, priority, routeid, gwlist, sort_alg, sort_profile, attrs, description)
VALUES
  (1, '0', '', NULL, 10, NULL, '${GWLIST}', 'N', NULL, '', '${RULE_DESC}')
ON DUPLICATE KEY UPDATE gwlist=VALUES(gwlist), description=VALUES(description);

-- Asterisk backend for inbound DID delivery (group 1) — fleet node public SIP
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('10', 0, '${ASTERISK_GW_ADDRESS}', 0, '', '', 0, 0, 'Fleet node Asterisk (golden)')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;

INSERT INTO dr_rules (ruleid, groupid, prefix, timerec, priority, routeid, gwlist, sort_alg, sort_profile, attrs, description)
VALUES
  (10, '1', '${INBOUND_DID_PREFIX}', NULL, 10, NULL, '10', 'N', NULL, '', 'Inbound DID ${INBOUND_DID_PREFIX} → golden')
ON DUPLICATE KEY UPDATE prefix=VALUES(prefix), gwlist=VALUES(gwlist), description=VALUES(description);
SQL

if [[ -n "$CARRIER_FAILOVER_ADDRESS" && "$SEED_MAGRATHEA_OUTBOUND" != "1" ]]; then
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<SQL
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('2', 0, '${CARRIER_FAILOVER_ADDRESS}', 0, '', '', 0, 0, 'Lab carrier failover')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;
SQL
fi

# Magrathea (UK Tier-2) signaling IPs — inbound is_from_gw sources only (not outbound)
if [[ "$SEED_MAGRATHEA" == "1" ]]; then
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<'SQL'
INSERT INTO dr_gateways (gwid, type, address, strip, pri_prefix, attrs, probe_mode, state, description)
VALUES
  ('3', 0, 'sip:87.238.72.129:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.72.129'),
  ('4', 0, 'sip:87.238.72.130:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.72.130'),
  ('5', 0, 'sip:87.238.73.129:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.73.129'),
  ('6', 0, 'sip:87.238.73.130:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.73.130'),
  ('7', 0, 'sip:87.238.74.129:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.74.129'),
  ('8', 0, 'sip:87.238.74.130:5060', 0, '', '', 0, 0, 'Magrathea inbound 87.238.74.130'),
  ('9', 0, 'sip:213.166.3.129:5060', 0, '', '', 0, 0, 'Magrathea inbound 213.166.3.129'),
  ('11', 0, 'sip:213.166.3.130:5060', 0, '', '', 0, 0, 'Magrathea inbound 213.166.3.130')
ON DUPLICATE KEY UPDATE address=VALUES(address), description=VALUES(description), state=0;
SQL
  echo "OK: Magrathea inbound source gateways (gwid 3–9, 11)"
fi

echo "OK: dr_gateways + dr_rules seeded (outbound gwlist=${GWLIST}, inbound prefix='${INBOUND_DID_PREFIX}')"
echo "Reload drouting:"
if curl -sS -X POST http://127.0.0.1:8888/mi -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"dr_reload","params":[],"id":1}' | grep -q '"result"'; then
  echo "  dr_reload OK (HTTP MI)"
elif command -v opensips-cli >/dev/null 2>&1; then
  opensips-cli -x mi dr_reload && echo "  dr_reload OK"
else
  echo "  Run manually: curl -X POST http://127.0.0.1:8888/mi -d '{\"jsonrpc\":\"2.0\",\"method\":\"dr_reload\",\"id\":1}'"
fi

echo
echo "Verify Asterisk source is in dispatcher (for do_routing gate):"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT setid,destination,attrs FROM dispatcher;"
