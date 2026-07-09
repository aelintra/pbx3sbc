#!/bin/bash
#
# Apply SBC peering Phases 0–2 on an existing install:
#   Phase 0 — dr_* tables + drouting module in opensips.cfg
#   Phase 1 — outbound PSTN (Asterisk → do_routing("0") → carrier)
#   Phase 2 — optional failover gwlist (when seed includes second carrier)
#
# Does NOT seed carrier data — run peering-seed-lab.sh after setting CARRIER_ADDRESS.
#
# Usage (on SBC host, from pbx3sbc repo root):
#   sudo DB_PASS='…' ./scripts/apply-peering-phase0-2.sh
#   sudo DB_PASS='…' ./scripts/apply-peering-phase0-2.sh --skip-restart
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENSIPS_CFG="${OPENSIPS_CFG:-/etc/opensips/opensips.cfg}"
TEMPLATE="${REPO_ROOT}/config/opensips.cfg.template"
SKIP_RESTART=false

for arg in "$@"; do
  case "$arg" in
    --skip-restart) SKIP_RESTART=true ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

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
if [[ -z "$DB_PASS" || "$DB_PASS" == "your-password" ]]; then
  echo "Error: set DB_PASS or configure /etc/opensips/.mysql_credentials" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Error: template not found: $TEMPLATE" >&2
  exit 1
fi

echo "=== Phase 0: peering tables ==="
if mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SHOW TABLES LIKE 'dr_gateways';" 2>/dev/null | grep -q dr_gateways; then
  echo "  dr_gateways exists — skipping peering-create.sql"
else
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "${SCRIPT_DIR}/peering-create.sql"
  echo "  peering tables created"
fi

echo "=== Apply opensips.cfg from template (peering routes + REGISTER fixes) ==="
if [[ -f "$OPENSIPS_CFG" ]]; then
  cp -a "$OPENSIPS_CFG" "${OPENSIPS_CFG}.bak.$(date +%Y%m%d%H%M%S)"
fi

# Preserve live advertised_address and DB password from current config when present
ADV=""
if [[ -f "$OPENSIPS_CFG" ]]; then
  ADV="$(grep -m1 '^advertised_address=' "$OPENSIPS_CFG" | sed 's/^advertised_address=//' | tr -d '"')"
  LIVE_PASS="$(grep -m1 'modparam("sqlops", "db_url"' "$OPENSIPS_CFG" | sed -n 's|.*mysql://[^:]*:\([^@]*\)@.*|\1|p')"
  if [[ -n "$LIVE_PASS" && "$LIVE_PASS" != "your-password" ]]; then
    DB_PASS="$LIVE_PASS"
  fi
fi
if [[ -z "$ADV" || "$ADV" == "CHANGE_ME" ]]; then
  ADV="$(curl -sS --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
fi
if [[ -z "$ADV" ]]; then
  echo "Warning: could not detect advertised_address — edit $OPENSIPS_CFG after apply" >&2
  ADV="CHANGE_ME"
fi

cp "$TEMPLATE" "$OPENSIPS_CFG"
escaped_pass="$(printf '%s' "$DB_PASS" | sed 's|/|\\/|g; s|&|\\&|g')"
sed -i "s|your-password|${escaped_pass}|g" "$OPENSIPS_CFG"
sed -i "s|advertised_address=\"CHANGE_ME\"|advertised_address=\"${ADV}\"|g" "$OPENSIPS_CFG"

# Match install.sh NAT auto-detect for public IP
if [[ "$ADV" != "CHANGE_ME" ]] && [[ ! "$ADV" =~ ^10\. ]] && [[ ! "$ADV" =~ ^192\.168\. ]] && [[ ! "$ADV" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
  sed -i 's|#define NAT_ENVIRONMENT_AUTO_DETECT "0"|#define NAT_ENVIRONMENT_AUTO_DETECT "1"|g' "$OPENSIPS_CFG" || true
fi

chown opensips:opensips "$OPENSIPS_CFG" 2>/dev/null || true

echo "  config syntax check…"
if ! opensips -C -f "$OPENSIPS_CFG" >/dev/null 2>&1; then
  echo "Error: opensips -C failed — restore from ${OPENSIPS_CFG}.bak.*" >&2
  opensips -C -f "$OPENSIPS_CFG" 2>&1 | tail -20 >&2 || true
  exit 1
fi
echo "  opensips -C OK (advertised_address=${ADV})"

if [[ "$SKIP_RESTART" == true ]]; then
  echo "=== Skipping OpenSIPS restart (--skip-restart) ==="
else
  echo "=== Restart OpenSIPS ==="
  systemctl restart opensips
  systemctl is-active opensips
fi

echo
echo "Next: seed carrier + node gateway rows, then MI dr_reload:"
echo "  CARRIER_ADDRESS='sip:carrier-host:5060' \\"
echo "  ASTERISK_GW_ADDRESS='sip:54.236.153.81:5060' \\"
echo "  sudo -E ./scripts/peering-seed-lab.sh"
echo "  opensips-cli -x dr_reload   # or: opensipsctl fifo dr_reload"
