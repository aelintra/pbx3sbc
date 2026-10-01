#!/bin/sh
# Install fleet edge provision nginx vhost (provision.{apex}:41363).
# Spec: PROVISIONING_IMPLEMENTATION_PLAN.md C2
#
# Usage (root on SBC):
#   install-provision-edge.sh
#   PROVISION_FQDN=provision.pbx3.com SSL_CERT=... SSL_KEY=... install-provision-edge.sh
#
# Requires: nginx, LE cert for provision FQDN (or paths via env).
# Idempotent.
set -eu

SCRIPTS="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$SCRIPTS/.." && pwd)"
CONF_SRC="$REPO/config/nginx"
CONF_DST="/etc/nginx/pbx3-provision"
SITE_NAME="pbx3-provision-edge.conf"
AVAILABLE="/etc/nginx/sites-available/$SITE_NAME"
ENABLED="/etc/nginx/sites-enabled/$SITE_NAME"
HTTP_SNIPPET="/etc/nginx/conf.d/pbx3-provision-maps.conf"

PROVISION_FQDN="${PROVISION_FQDN:-provision.pbx3.com}"
SSL_CERT="${SSL_CERT:-/etc/letsencrypt/live/${PROVISION_FQDN}/fullchain.pem}"
SSL_KEY="${SSL_KEY:-/etc/letsencrypt/live/${PROVISION_FQDN}/privkey.pem}"

die() { echo "install-provision-edge: $*" >&2; exit 1; }
log() { echo "install-provision-edge: $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root"
command -v nginx >/dev/null 2>&1 || die "nginx not installed"
[ -f "$CONF_SRC/pbx3-provision-edge.conf" ] || die "missing $CONF_SRC/pbx3-provision-edge.conf"
[ -f "$CONF_SRC/mac-from-request.map" ] || die "missing mac-from-request.map"
[ -f "$SSL_CERT" ] || die "missing SSL cert $SSL_CERT — issue LE for $PROVISION_FQDN first"
[ -f "$SSL_KEY" ] || die "missing SSL key $SSL_KEY"

mkdir -p "$CONF_DST" /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d

cp "$CONF_SRC/mac-from-request.map" "$CONF_DST/mac-from-request.map"
if [ ! -f "$CONF_DST/provision-mac.map" ]; then
	cp "$CONF_SRC/provision-mac.map.example" "$CONF_DST/provision-mac.map"
	log "seeded empty provision-mac.map — run sync-provision-mac-map.sh after MAC claims"
fi

# http{} map includes (conf.d is pulled into http on Ubuntu nginx)
cat > "$HTTP_SNIPPET" <<EOF
# PBX3 provision edge — MAC extract + catalog map (C2 / #3)
include $CONF_DST/mac-from-request.map;
include $CONF_DST/provision-mac.map;
EOF

sed -e "s|__PROVISION_SERVER_NAME__|${PROVISION_FQDN}|g" \
	-e "s|__SSL_CERTIFICATE__|${SSL_CERT}|g" \
	-e "s|__SSL_CERTIFICATE_KEY__|${SSL_KEY}|g" \
	"$CONF_SRC/pbx3-provision-edge.conf" > "$AVAILABLE"

ln -sfn "$AVAILABLE" "$ENABLED"

nginx -t || die "nginx -t failed"
systemctl reload nginx
log "enabled $ENABLED for $PROVISION_FQDN:41363"
log "next: DNS A $PROVISION_FQDN → edge VIP; sync-provision-mac-map.sh; open UFW 41363/tcp public (phone-facing)"
