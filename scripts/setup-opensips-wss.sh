#!/usr/bin/env bash
# Prepare / document OpenSIPS WSS (W1) on an SBC host (Magrathea VIP / LE path).
# Spec checklist: workingdocs/WEBRTC_W1_MAGRATHEA.md
#
# Usage (on Magrathea, as root preferred):
#   sudo ./scripts/setup-opensips-wss.sh --cert-domain sbc.pbx3.com
#   sudo ./scripts/setup-opensips-wss.sh --cert-domain sbc.pbx3.com --install-packages
#   sudo ./scripts/setup-opensips-wss.sh --print-cfg-snippet
#
# Does NOT auto-uncomment opensips.cfg — operator enables after backup (Phase 1.2).
# When enabling: ONE certificate/private_key pair only (never both template examples).
# Lab LAN self-signed (auto-enable): scripts/enable-lab-wss.sh
#
# Apt: installing WSS modules may upgrade opensips and prompt on opensips.cfg —
# --install-packages uses force-confold so the live cfg is kept.

set -euo pipefail

CERT_DOMAIN=""
INSTALL_PACKAGES=0
PRINT_SNIPPET=0
LE_LIVE="${LE_LIVE:-/etc/letsencrypt/live}"
OPENSIPS_USER="${OPENSIPS_USER:-opensips}"

usage() {
  sed -n '2,12p' "$0" | tr -d '#'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert-domain)
      CERT_DOMAIN="${2:-}"
      shift 2
      ;;
    --cert-domain=*)
      CERT_DOMAIN="${1#--cert-domain=}"
      shift
      ;;
    --install-packages) INSTALL_PACKAGES=1; shift ;;
    --print-cfg-snippet) PRINT_SNIPPET=1; shift ;;
    -h|--help) usage ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$PRINT_SNIPPET" -eq 1 ]]; then
  cat <<'EOF'
# Paste into /etc/opensips/opensips.cfg after proto_udp (or match template).
# Enable EXACTLY ONE certificate/private_key pair (this snippet uses the tls/ copy).

loadmodule "tls_openssl.so"
loadmodule "tls_mgm.so"
loadmodule "proto_wss.so"
socket=wss:0.0.0.0:8089
modparam("proto_wss", "wss_resource", "/ws")
modparam("tls_mgm", "server_domain", "wss")
modparam("tls_mgm", "match_ip_address", "[wss]*")
modparam("tls_mgm", "certificate", "[wss]/etc/opensips/tls/sbc.pbx3.com-fullchain.pem")
modparam("tls_mgm", "private_key", "[wss]/etc/opensips/tls/sbc.pbx3.com-privkey.pem")
modparam("tls_mgm", "verify_cert", "[wss]0")
modparam("tls_mgm", "require_cert", "[wss]0")
EOF
  exit 0
fi

if [[ -z "$CERT_DOMAIN" ]]; then
  echo "setup-opensips-wss: require --cert-domain <fqdn> (e.g. sbc.pbx3.com)" >&2
  echo "  or --print-cfg-snippet" >&2
  exit 2
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "setup-opensips-wss: run as root (sudo)" >&2
  exit 1
fi

echo "== W1 OpenSIPS WSS prep for domain: $CERT_DOMAIN =="

if [[ "$INSTALL_PACKAGES" -eq 1 ]]; then
  echo "-- apt search (WSS / TLS packages) --"
  apt-cache search opensips 2>/dev/null | grep -Ei 'wss|tls|openssl|wolfssl' || true
  echo
  echo "Install the packages that match your OpenSIPS major, for example:"
  echo "  apt-get install -y opensips-tls-openssl-module opensips-wss-module"
  echo "Names vary; use search output above. Re-run without --install-packages after install."
  apt-get install -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    opensips-tls-openssl-module opensips-wss-module 2>/dev/null \
    || apt-get install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      opensips-module-tls opensips-module-wss 2>/dev/null \
    || echo "WARN: auto package install incomplete — install modules manually."
fi

FULLCHAIN="$LE_LIVE/$CERT_DOMAIN/fullchain.pem"
PRIVKEY="$LE_LIVE/$CERT_DOMAIN/privkey.pem"

if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
  # root-only perms often hide live paths from non-root; try readable check as root
  if [[ ! -r "$FULLCHAIN" ]]; then
    echo "ERROR: LE material not found or unreadable:" >&2
    echo "  $FULLCHAIN" >&2
    echo "  $PRIVKEY" >&2
    echo "Admin HTTPS path: pbx3sbc workingdocs/LE_HTTPS_SBC_ADMIN.md" >&2
    exit 1
  fi
fi

TLS_DIR="${PBX3SBC_OPENSIPS_TLS_DIR:-/etc/opensips/tls}"
mkdir -p "$TLS_DIR"
cp -L "$FULLCHAIN" "$TLS_DIR/${CERT_DOMAIN}-fullchain.pem"
cp -L "$PRIVKEY" "$TLS_DIR/${CERT_DOMAIN}-privkey.pem"
if id "$OPENSIPS_USER" >/dev/null 2>&1; then
  chown "${OPENSIPS_USER}:${OPENSIPS_USER}" \
    "$TLS_DIR/${CERT_DOMAIN}-fullchain.pem" \
    "$TLS_DIR/${CERT_DOMAIN}-privkey.pem" 2>/dev/null || true
fi
chmod 644 "$TLS_DIR/${CERT_DOMAIN}-fullchain.pem"
chmod 600 "$TLS_DIR/${CERT_DOMAIN}-privkey.pem"

if id "$OPENSIPS_USER" >/dev/null 2>&1; then
  if sudo -u "$OPENSIPS_USER" test -r "$TLS_DIR/${CERT_DOMAIN}-fullchain.pem" \
    && sudo -u "$OPENSIPS_USER" test -r "$TLS_DIR/${CERT_DOMAIN}-privkey.pem"; then
    echo "OK: $OPENSIPS_USER can read $TLS_DIR/${CERT_DOMAIN}-{fullchain,privkey}.pem"
  else
    echo "WARN: $OPENSIPS_USER still cannot read tls copies" >&2
  fi
fi

HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
HOOK="$HOOK_DIR/reload-opensips-wss.sh"
if [[ -d /etc/letsencrypt/renewal-hooks/deploy ]]; then
  cat >"$HOOK" <<HOOK
#!/bin/sh
# Copy LE material for OpenSIPS WSS then reload (no ssl-cert group required).
set -e
cp -L /etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem ${TLS_DIR}/${CERT_DOMAIN}-fullchain.pem
cp -L /etc/letsencrypt/live/${CERT_DOMAIN}/privkey.pem ${TLS_DIR}/${CERT_DOMAIN}-privkey.pem
chown ${OPENSIPS_USER}:${OPENSIPS_USER} ${TLS_DIR}/${CERT_DOMAIN}-fullchain.pem ${TLS_DIR}/${CERT_DOMAIN}-privkey.pem 2>/dev/null || true
chmod 644 ${TLS_DIR}/${CERT_DOMAIN}-fullchain.pem
chmod 600 ${TLS_DIR}/${CERT_DOMAIN}-privkey.pem
if systemctl is-active --quiet opensips 2>/dev/null; then
  systemctl reload opensips 2>/dev/null || systemctl restart opensips 2>/dev/null || true
elif systemctl is-active --quiet opensipsd 2>/dev/null; then
  systemctl restart opensipsd 2>/dev/null || true
fi
HOOK
  chmod 755 "$HOOK"
  echo "OK: certbot deploy hook $HOOK"
else
  echo "NOTE: $HOOK_DIR missing — create renew hook after certbot install"
fi

echo
echo "Next (do not skip Magrathea backup — WEBRTC_W1_MAGRATHEA.md Phase 1.2):"
echo "  1. SG + host firewall: allow TCP 8089"
echo "  2. Enable W1 in opensips.cfg: modules/socket + EXACTLY ONE cert pair under $TLS_DIR"
echo "     (do not also leave LE live paths active — dual pairs → OpenSIPS will not start)"
echo "  3. opensips -C -f /etc/opensips/opensips.cfg && systemctl restart opensips"
echo "  4. ss -lntp | grep 8089   and confirm UDP 5060 still listening"
echo "  5. Smoke wss://$CERT_DOMAIN:8089/ws  (domain=tenant, user=shortuid)"
echo "Done prep for $CERT_DOMAIN."
echo "Lab LAN (no LE): use scripts/enable-lab-wss.sh instead."
