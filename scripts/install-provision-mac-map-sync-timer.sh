#!/bin/sh
# Install + enable 1-minute provision MAC map sync timer on the SBC.
# Spec: PROVISION_EDGE_PROXY.md — removes manual sync after MAC claim.
#
# Usage (root on SBC):
#   install-provision-mac-map-sync-timer.sh
#
# Requires: /etc/pbx3sbc/log-ship.env with PBX3_ORG_BUCKET (same as log-ship).
# Idempotent.
set -eu

SCRIPTS="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$SCRIPTS/.." && pwd)"
UNIT_SRC="$REPO/systemd"
BIN_DST="/usr/local/sbin/sync-provision-mac-map.sh"
ENV_FILE="/etc/pbx3sbc/log-ship.env"

die() { echo "install-provision-mac-map-sync-timer: $*" >&2; exit 1; }
log() { echo "install-provision-mac-map-sync-timer: $*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root"
[ -f "$SCRIPTS/sync-provision-mac-map.sh" ] || die "missing $SCRIPTS/sync-provision-mac-map.sh"
[ -f "$UNIT_SRC/pbx3-provision-mac-map-sync.service" ] || die "missing systemd service unit"
[ -f "$UNIT_SRC/pbx3-provision-mac-map-sync.timer" ] || die "missing systemd timer unit"
[ -f "$ENV_FILE" ] || die "missing $ENV_FILE — set PBX3_ORG_BUCKET (see log-ship.env.example)"
# shellcheck disable=SC1090
. "$ENV_FILE"
[ -n "${PBX3_ORG_BUCKET:-}" ] || die "$ENV_FILE has no PBX3_ORG_BUCKET"
command -v aws >/dev/null 2>&1 || die "aws CLI required to fetch s3://\$PBX3_ORG_BUCKET/catalog/provision-mac.map"

install -m 0755 "$SCRIPTS/sync-provision-mac-map.sh" "$BIN_DST"
install -m 0644 "$UNIT_SRC/pbx3-provision-mac-map-sync.service" /etc/systemd/system/
install -m 0644 "$UNIT_SRC/pbx3-provision-mac-map-sync.timer" /etc/systemd/system/

# Fix Documentation= to repo path if present (optional; unit already has a default)
systemctl daemon-reload
systemctl enable --now pbx3-provision-mac-map-sync.timer
# Prime once so Save→claim is not waiting for first tick
systemctl start pbx3-provision-mac-map-sync.service || log "prime sync failed — check journalctl -u pbx3-provision-mac-map-sync.service"

log "enabled pbx3-provision-mac-map-sync.timer (every 1 min; bucket=$PBX3_ORG_BUCKET)"
systemctl list-timers pbx3-provision-mac-map-sync.timer --no-pager || true
