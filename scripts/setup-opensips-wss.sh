#!/usr/bin/env bash
# Prepare / document OpenSIPS WSS (W1) on an SBC host (Magrathea VIP path).
# Spec checklist: workingdocs/WEBRTC_W1_MAGRATHEA.md
#
# Usage (on Magrathea, as root preferred):
#   sudo ./scripts/setup-opensips-wss.sh --cert-domain sbc.pbx3.com
#   sudo ./scripts/setup-opensips-wss.sh --cert-domain sbc.pbx3.com --install-packages
#   sudo ./scripts/setup-opensips-wss.sh --print-cfg-snippet
#
# Does NOT auto-uncomment opensips.cfg — operator enables after backup (Phase 1.2).

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
# Paths assume --cert-domain sbc.pbx3.com

loadmodule "tls_openssl.so"
loadmodule "tls_mgm.so"
loadmodule "proto_wss.so"
socket=wss:0.0.0.0:8089
modparam("proto_wss", "wss_resource", "/ws")
modparam("tls_mgm", "server_domain", "wss")
modparam("tls_mgm", "match_ip_address", "[wss]*")
modparam("tls_mgm", "certificate", "[wss]/etc/letsencrypt/live/sbc.pbx3.com/fullchain.pem")
modparam("tls_mgm", "private_key", "[wss]/etc/letsencrypt/live/sbc.pbx3.com/privkey.pem")
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
  # Best-effort common names; ignore failures
  apt-get install -y opensips-tls-openssl-module opensips-wss-module 2>/dev/null \
    || apt-get install -y opensips-module-tls opensips-module-wss 2>/dev/null \
    || echo "WARN: auto package install incomplete — install modules manually."
fi

FULLCHAIN="$LE_LIVE/$CERT_DOMAIN/fullchain.pem"
PRIVKEY="$LE_LIVE/$CERT_DOMAIN/privkey.pem"

if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
  echo "ERROR: LE material not found:" >&2
  echo "  $FULLCHAIN" >&2
  echo "  $PRIVKEY" >&2
  echo "Admin HTTPS path: pbx3sbc workingdocs/LE_HTTPS_SBC_ADMIN.md" >&2
  exit 1
fi

# Read ACLs for opensips (and ssl-cert group, common LE pattern)
if getent group ssl-cert >/dev/null 2>&1; then
  chgrp ssl-cert "$PRIVKEY" 2>/dev/null || true
  chmod 640 "$PRIVKEY" 2>/dev/null || true
  if id -nG "$OPENSIPS_USER" 2>/dev/null | tr ' ' '\n' | grep -qx ssl-cert; then
    echo "OK: $OPENSIPS_USER already in ssl-cert"
  else
    usermod -aG ssl-cert "$OPENSIPS_USER" 2>/dev/null \
      && echo "OK: added $OPENSIPS_USER to ssl-cert" \
      || echo "WARN: could not add $OPENSIPS_USER to ssl-cert — fix manually"
  fi
fi

# Traversal for group ssl-cert through le live chain
for d in \
  /etc/letsencrypt \
  /etc/letsencrypt/live \
  /etc/letsencrypt/archive \
  "/etc/letsencrypt/live/$CERT_DOMAIN" \
  "/etc/letsencrypt/archive/$CERT_DOMAIN"
do
  if [[ -d "$d" ]]; then
    chmod o+x "$d" 2>/dev/null || true
  fi
done
chmod o+r "$FULLCHAIN" 2>/dev/null || true

if id "$OPENSIPS_USER" >/dev/null 2>&1; then
  if sudo -u "$OPENSIPS_USER" test -r "$FULLCHAIN" && sudo -u "$OPENSIPS_USER" test -r "$PRIVKEY"; then
    echo "OK: $OPENSIPS_USER can read fullchain + privkey"
  else
    echo "WARN: $OPENSIPS_USER still cannot read certs — adjust ACLs before enable" >&2
    ls -la "$FULLCHAIN" "$PRIVKEY" || true
  fi
else
  echo "WARN: user $OPENSIPS_USER not found — skip readability test"
fi

HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
HOOK="$HOOK_DIR/reload-opensips-wss.sh"
if [[ -d /etc/letsencrypt/renewal-hooks/deploy ]]; then
  cat >"$HOOK" <<'HOOK'
#!/bin/sh
# Reload/restart OpenSIPS after LE renew so WSS picks up new cert.
# Installed by pbx3sbc scripts/setup-opensips-wss.sh
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
echo "  2. Uncomment W1 block in opensips.cfg (or: $0 --print-cfg-snippet)"
echo "  3. opensips -C -f /etc/opensips/opensips.cfg && systemctl restart opensips"
echo "  4. ss -lntp | grep 8089"
echo "  5. Smoke wss://$CERT_DOMAIN:8089/ws  (domain=tenant, user=shortuid)"
echo "Done prep for $CERT_DOMAIN."
