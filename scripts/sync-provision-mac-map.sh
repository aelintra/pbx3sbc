#!/bin/sh
# Sync catalog/provision-mac.map → local nginx include and reload.
# Spec: PROVISIONING_IMPLEMENTATION_PLAN.md C2 / #3 (static artifact; no live GK on GET)
#
# Sources (first that works):
#   1) PROVISION_MAC_MAP_FILE — local path (ops drop / gatekeeper project copy)
#   2) S3: aws s3 cp s3://$PBX3_ORG_BUCKET/catalog/provision-mac.map
#   3) Gatekeeper: POST /api/v1/mac-index/project then fetch S3 (optional curl of raw object)
#
# Usage (root on SBC):
#   sync-provision-mac-map.sh
#   PROVISION_MAC_MAP_FILE=/tmp/provision-mac.map sync-provision-mac-map.sh
set -eu

CONF_DST="/etc/nginx/pbx3-provision"
DEST="$CONF_DST/provision-mac.map"
TMP="${DEST}.tmp.$$"

die() { echo "sync-provision-mac-map: $*" >&2; exit 1; }
log() { echo "sync-provision-mac-map: $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root"
mkdir -p "$CONF_DST"

# Timer / oneshot: load org bucket from the same env as log-ship if unset
if [ -z "${PBX3_ORG_BUCKET:-}" ] && [ -f /etc/pbx3sbc/log-ship.env ]; then
	# shellcheck disable=SC1091
	set -a
	# shellcheck source=/dev/null
	. /etc/pbx3sbc/log-ship.env
	set +a
fi

fetch_to_tmp() {
	if [ -n "${PROVISION_MAC_MAP_FILE:-}" ] && [ -f "$PROVISION_MAC_MAP_FILE" ]; then
		cp "$PROVISION_MAC_MAP_FILE" "$TMP"
		log "copied $PROVISION_MAC_MAP_FILE"
		return 0
	fi

	BUCKET="${PBX3_ORG_BUCKET:-}"
	REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
	if [ -n "$BUCKET" ] && command -v aws >/dev/null 2>&1; then
		if aws s3 cp "s3://${BUCKET}/catalog/provision-mac.map" "$TMP" --region "$REGION" 2>/dev/null; then
			log "fetched s3://${BUCKET}/catalog/provision-mac.map"
			return 0
		fi
	fi

	# Optional: gatekeeper project then retry S3
	GK_URL="${PBX3_GATEKEEPER_URL:-}"
	GK_TOKEN="${PBX3_GATEKEEPER_TOKEN:-}"
	if [ -n "$GK_URL" ] && [ -n "$GK_TOKEN" ] && command -v curl >/dev/null 2>&1; then
		BASE=$(printf '%s' "$GK_URL" | sed 's|/*$||')
		code=$(curl -sk -o /dev/null -w '%{http_code}' \
			-H "Authorization: Bearer ${GK_TOKEN}" \
			-H "Accept: application/json" \
			-X POST "${BASE}/api/v1/mac-index/project" || true)
		log "gatekeeper mac-index/project → HTTP ${code:-?}"
		if [ -n "$BUCKET" ] && command -v aws >/dev/null 2>&1; then
			if aws s3 cp "s3://${BUCKET}/catalog/provision-mac.map" "$TMP" --region "$REGION" 2>/dev/null; then
				log "fetched map after project"
				return 0
			fi
		fi
	fi

	return 1
}

fetch_to_tmp || die "no map source — set PROVISION_MAC_MAP_FILE or PBX3_ORG_BUCKET (+ aws), or GATEKEEPER URL/TOKEN"

# Sanity: must look like an nginx map (no secrets)
grep -q 'map \$provision_mac \$provision_upstream' "$TMP" || die "artifact missing map \$provision_mac \$provision_upstream"
if grep -qiE 'password|sip_auth|secret' "$TMP"; then
	rm -f "$TMP"
	die "refusing map that looks like it contains secrets"
fi

if [ -f "$DEST" ] && cmp -s "$TMP" "$DEST"; then
	rm -f "$TMP"
	log "unchanged $DEST — skip reload"
	exit 0
fi

mv "$TMP" "$DEST"
chmod 644 "$DEST"
nginx -t || die "nginx -t failed after map update"
systemctl reload nginx
log "installed $DEST and reloaded nginx"
