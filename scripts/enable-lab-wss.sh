#!/usr/bin/env bash
# Enable OpenSIPS WSS on a Lab SBC (LAN / no Let's Encrypt).
#
# Packages + self-signed cert for SBC_IP + enable W1 block with ONE cert pair only.
# Cloud / VIP with LE: use setup-opensips-wss.sh instead (does not auto-uncomment).
#
# Usage (on the SBC, as root):
#   sudo ./scripts/enable-lab-wss.sh
#   sudo SBC_IP=192.168.1.85 ./scripts/enable-lab-wss.sh
#
# Footguns this avoids (lab soak 2026-08-20):
#   - apt upgrading opensips and prompting on opensips.cfg → use force-confold
#   - uncommenting BOTH template cert pairs (LE + sbc.pbx3.com) → OpenSIPS fails to start

set -euo pipefail

SBC_IP="${SBC_IP:-192.168.1.85}"
CFG="${CFG:-/etc/opensips/opensips.cfg}"
TLS_DIR="${TLS_DIR:-/etc/opensips/tls}"
CERT_NAME="${CERT_NAME:-lab-sbc}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"
FULLCHAIN="$TLS_DIR/${CERT_NAME}-fullchain.pem"
PRIVKEY="$TLS_DIR/${CERT_NAME}-privkey.pem"

log() { printf 'lab-wss: %s\n' "$*"; }
err() { printf 'lab-wss: ERROR: %s\n' "$*" >&2; }

if [[ "$(id -u)" -ne 0 ]]; then
  err "run as root (sudo $0)"
  exit 1
fi

if [[ ! -f "$CFG" ]]; then
  err "missing $CFG"
  exit 1
fi

log "enable WSS on ${SBC_IP} (self-signed lab path)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Keep existing opensips.cfg if apt upgrades opensips with the WSS modules.
apt-get install -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  opensips-wss-module opensips-tls-openssl-module opensips-tlsmgm-module \
  || apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    opensips-wss-module opensips-tls-openssl-module

for m in proto_wss.so tls_openssl.so tls_mgm.so; do
  if ! ls /usr/lib/*/opensips/modules/"$m" >/dev/null 2>&1; then
    err "module $m not found after apt install"
    apt-cache search opensips | grep -Ei 'wss|tls' || true
    exit 1
  fi
done

mkdir -p "$TLS_DIR"
if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
  log "generating self-signed cert CN/SAN=${SBC_IP}"
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout "$PRIVKEY" -out "$FULLCHAIN" \
    -subj "/CN=${SBC_IP}" \
    -addext "subjectAltName=IP:${SBC_IP}"
fi
if id "$OPENSIPS_USER" >/dev/null 2>&1; then
  chown "${OPENSIPS_USER}:${OPENSIPS_USER}" "$FULLCHAIN" "$PRIVKEY" 2>/dev/null || true
fi
chmod 644 "$FULLCHAIN"
chmod 600 "$PRIVKEY"

BACKUP="${CFG}.pre-lab-wss.$(date +%Y%m%d%H%M%S)"
cp -a "$CFG" "$BACKUP"
log "backup $BACKUP"

# Enable transport/modules; force a single lab cert pair; leave LE / Magrathea example paths commented.
python3 - "$CFG" "$FULLCHAIN" "$PRIVKEY" <<'PY'
import re
import sys

path, fullchain, privkey = sys.argv[1:4]
with open(path) as f:
    text = f.read()

start = text.find("# --- WebRTC / WSS")
if start < 0:
    # Already enabled or custom layout — search for proto_wss block start
    start = text.find('loadmodule "proto_udp.so"')
    if start < 0:
        sys.exit("ERROR: cannot locate WSS section in opensips.cfg")
    # Insert after proto_udp line
    nl = text.find("\n", start)
    start = nl + 1 if nl >= 0 else start

end = text.find('\nloadmodule "db_mysql.so"', start)
if end < 0:
    sys.exit("ERROR: cannot find end of WSS block (loadmodule db_mysql.so)")

# Rebuild a clean WSS enable block (one cert pair only).
block = f'''# --- WebRTC / WSS (W1 / S8.11) — ENABLED (lab self-signed) ---
# Lab helper: scripts/enable-lab-wss.sh — ONE certificate pair only.
# Cloud LE: scripts/setup-opensips-wss.sh then enable a single pair (not both template examples).
#
loadmodule "tls_openssl.so"
loadmodule "tls_mgm.so"
loadmodule "proto_wss.so"
socket=wss:0.0.0.0:8089
modparam("proto_wss", "wss_resource", "/ws")
modparam("tls_mgm", "server_domain", "wss")
modparam("tls_mgm", "match_ip_address", "[wss]*")
modparam("tls_mgm", "certificate", "[wss]{fullchain}")
modparam("tls_mgm", "private_key", "[wss]{privkey}")
modparam("tls_mgm", "verify_cert", "[wss]0")
modparam("tls_mgm", "require_cert", "[wss]0")
# Example paths kept commented (do not also enable these):
# modparam("tls_mgm", "certificate", "[wss]/etc/letsencrypt/live/sbc.pbx3.com/fullchain.pem")
# modparam("tls_mgm", "private_key", "[wss]/etc/letsencrypt/live/sbc.pbx3.com/privkey.pem")
# modparam("tls_mgm", "certificate", "[wss]/etc/opensips/tls/sbc.pbx3.com-fullchain.pem")
# modparam("tls_mgm", "private_key", "[wss]/etc/opensips/tls/sbc.pbx3.com-privkey.pem")
#
'''

text2 = text[:start] + block + text[end:]
# Safety: if any active Magrathea/LE cert modparams remain elsewhere, comment them.
def comment_bad(m):
    line = m.group(0)
    if line.lstrip().startswith("#"):
        return line
    return "# " + line

text2 = re.sub(
    r'^modparam\("tls_mgm", "(?:certificate|private_key)", "\[wss\]/etc/(?:letsencrypt/live|opensips/tls)/sbc\.pbx3\.com[^"]*"\)\s*$',
    comment_bad,
    text2,
    flags=re.M,
)

with open(path, "w") as f:
    f.write(text2)
print("OK: WSS block rewritten with single lab cert pair")
PY

if command -v ufw >/dev/null 2>&1; then
  ufw allow 8089/tcp comment 'OpenSIPS WSS lab' || true
fi

log "opensips -C"
if ! opensips -C -f "$CFG"; then
  err "config check failed — restoring $BACKUP"
  cp -a "$BACKUP" "$CFG"
  exit 1
fi

systemctl reset-failed opensips 2>/dev/null || true
systemctl restart opensips
sleep 1
if ! systemctl is-active --quiet opensips; then
  err "opensips failed to start — check journalctl -u opensips; backup at $BACKUP"
  systemctl status opensips --no-pager || true
  exit 1
fi

if ! ss -lnt | grep -q ':8089'; then
  err "8089 not listening"
  exit 1
fi
if ! ss -ulnt | grep -q ':5060'; then
  err "UDP 5060 not listening after WSS enable"
  exit 1
fi

cat <<EOF

Lab WSS ready.

  URL:     wss://${SBC_IP}:8089/ws
  Cert:    ${FULLCHAIN} (self-signed)
  Backup:  ${BACKUP}

SPA Line test: override WSS to wss://${SBC_IP}:8089/ws
Trust the cert on the Mac (Keychain Always Trust) or WSS handshake fails.

EOF
