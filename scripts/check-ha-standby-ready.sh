#!/usr/bin/env bash
# Verify this host can accept Fleet warm-pull (standby) / S3 backup (active).
# Run on each HA member after greenfield. Exit 0 only when all checks pass.
#
# Usage:
#   sudo ./scripts/check-ha-standby-ready.sh
#   sudo ./scripts/check-ha-standby-ready.sh --role standby   # stricter (expects non-VIP)
#   sudo ./scripts/check-ha-standby-ready.sh --role active
#
# Spec: Fleet Sync now needs on the standby:
#   - PBX3_FLEET_SERVICE_TOKEN in pbx3sbc-admin .env (same as active / control)
#   - /etc/pbx3sbc/log-ship.env (PBX3_ORG_BUCKET, PBX3_SBC_ID)
#   - aws CLI
#   - IAM instance profile with sbc/{id}/* read (lab: pbx3-sbc)
#   - sbc-backup-panel.sh + sudoers for www-data
#   - SG: control → this host TCP 80 (admin API)

set -euo pipefail

ROLE="any" # any|active|standby
ADMIN_ENV="${PBX3SBC_ADMIN_ENV:-/home/ubuntu/pbx3sbc-admin/.env}"
LOG_SHIP="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
PANEL="${PBX3SBC_PANEL_SCRIPT:-/home/ubuntu/pbx3sbc/scripts/sbc-backup-panel.sh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --role=*) ROLE="${1#--role=}"; shift ;;
    -h|--help) sed -n '2,20p' "$0" | tr -d '#'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$ROLE" in any|active|standby) ;; *)
  echo "check-ha-standby-ready: --role must be any|active|standby" >&2
  exit 2
  ;;
esac

FAIL=0
pass() { echo "OK  $*"; }
fail() { echo "FAIL $*"; FAIL=1; }
warn() { echo "WARN $*"; }

echo "=== HA warm-sync readiness ($(hostname)) role=$ROLE ==="

# 1) aws CLI
if command -v aws >/dev/null 2>&1; then
  pass "aws CLI: $(command -v aws) ($(aws --version 2>&1 | head -1))"
else
  fail "aws CLI missing — install AWS CLI v2 (required for S3 upload/pull)"
fi

# 2) log-ship.env
if [[ -f "$LOG_SHIP" ]]; then
  # shellcheck disable=SC1090
  source "$LOG_SHIP"
  if [[ -n "${PBX3_ORG_BUCKET:-}" && -n "${PBX3_SBC_ID:-}" ]]; then
    pass "log-ship.env: bucket=${PBX3_ORG_BUCKET} sbc_id=${PBX3_SBC_ID}"
  else
    fail "log-ship.env present but PBX3_ORG_BUCKET / PBX3_SBC_ID unset — copy from active or edit $LOG_SHIP"
  fi
else
  fail "missing $LOG_SHIP — copy from active or run install-log-retention.sh and edit"
fi

# 3) fleet service token
if [[ -f "$ADMIN_ENV" ]]; then
  if grep -qE '^PBX3_FLEET_SERVICE_TOKEN=.+' "$ADMIN_ENV"; then
    pass "PBX3_FLEET_SERVICE_TOKEN set in $ADMIN_ENV"
  else
    fail "PBX3_FLEET_SERVICE_TOKEN missing in $ADMIN_ENV — copy from active (same value as control PBX3_FLEET_SERVICE_TOKEN)"
  fi
else
  fail "missing admin .env at $ADMIN_ENV"
fi

# 4) IAM instance profile (IMDS)
IMDST="$(curl -sS -m 2 -X PUT 'http://169.254.169.254/latest/api/token' \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null || true)"
PROFILE=""
if [[ -n "$IMDST" ]]; then
  PROFILE="$(curl -sS -m 2 -H "X-aws-ec2-metadata-token: $IMDST" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null || true)"
fi
PROFILE="$(echo "$PROFILE" | tr -d '[:space:]')"
if [[ -n "$PROFILE" && "$PROFILE" != *"404"* && "$PROFILE" != *"Not Found"* ]]; then
  pass "IAM instance profile credentials present ($PROFILE)"
  if command -v aws >/dev/null 2>&1; then
    if aws sts get-caller-identity >/dev/null 2>&1; then
      pass "aws sts get-caller-identity OK"
    else
      fail "IAM profile associated but sts failed — wait ~15s after associate-iam-instance-profile or check policy"
    fi
  fi
else
  fail "no IAM instance profile — attach lab profile pbx3-sbc (or equivalent sbc/{id}/* read/write)"
fi

# 5) panel helper + sudoers
if [[ -x "$PANEL" ]]; then
  pass "panel helper: $PANEL"
else
  fail "missing executable $PANEL — deploy pbx3sbc scripts"
fi
if sudo -n -u www-data sudo -n "$PANEL" vip-role >/dev/null 2>&1; then
  pass "www-data sudoers can run sbc-backup-panel.sh"
else
  fail "www-data cannot sudo $PANEL — run: sudo ./scripts/setup-admin-panel-sudoers.sh"
fi

# 6) VIP role vs expected
if [[ -x "$PANEL" ]]; then
  ROLE_JSON="$(sudo "$PANEL" vip-role 2>/dev/null || true)"
  HOLDER="$(jq -r '.vip_holder // empty' <<<"$ROLE_JSON" 2>/dev/null || true)"
  ADV="$(jq -r '.advertised_address // empty' <<<"$ROLE_JSON" 2>/dev/null || true)"
  echo "INFO vip_holder=${HOLDER:-?} advertised_address=${ADV:-?}"
  if [[ "$ROLE" == "standby" && "$HOLDER" == "true" ]]; then
    fail "expected standby (non-VIP) but vip_holder=true — wrong host or EIP still here?"
  fi
  if [[ "$ROLE" == "active" && "$HOLDER" == "false" ]]; then
    fail "expected active (VIP holder) but vip_holder=false"
  fi
fi

# 7) ops notes (non-fatal)
warn "SG: allow control plane → this host TCP/80 for /api/fleet/* (standby public IP)"
warn "After fixes: Fleet → Edge HA → Sync now"

echo "==="
if [[ "$FAIL" -ne 0 ]]; then
  echo "NOT READY ($FAIL check(s) failed)"
  exit 1
fi
echo "READY"
exit 0
