#!/usr/bin/env bash
# Upload one local SBC backup zip to sbc/{id}/backups/{stamp}/ on PBX3_ORG_BUCKET.
# Spec: pbx3/pbx3-directory/docs/SBC_BACKUP_RESTORE_REQUIREMENTS.md
# Schema: pbx3/pbx3-directory/schema/sbc-backup-manifest.v0.json
#
# Usage:
#   sudo ./upload-sbc-backup.sh --zip /var/lib/pbx3sbc/bkup/sbcbak.EPOCH.zip [--trigger manual]
#   sudo ./upload-sbc-backup.sh --zip sbcbak.EPOCH.zip   # looks under BKUP_DIR
#
# Env: /etc/pbx3sbc/log-ship.env (PBX3_ORG_BUCKET, PBX3_SBC_ID, AWS_DEFAULT_REGION)
#   PBX3_BACKUP_UPLOAD_ENABLED — false to skip (default true when bucket set)

set -euo pipefail

ENV_FILE="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
[[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"

BKUP_DIR="${PBX3SBC_BKUP_DIR:-/var/lib/pbx3sbc/bkup}"
BUCKET="${PBX3_ORG_BUCKET:-}"
SBC_ID="${PBX3_SBC_ID:-sbc}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ENABLED="${PBX3_BACKUP_UPLOAD_ENABLED:-true}"
export AWS_DEFAULT_REGION="$REGION"

ZIP_PATH=""
TRIGGER="manual"
FQDN="${PBX3_SBC_FQDN:-}"

usage() {
  cat <<'EOF'
Usage: upload-sbc-backup.sh --zip PATH [--trigger manual|scheduled|pre-upgrade] [--fqdn FQDN]

  --zip PATH      sbcbak.{epoch}.zip (absolute or basename under /var/lib/pbx3sbc/bkup)
  --trigger TYPE  manual | scheduled | pre-upgrade (default: manual)
  --fqdn FQDN     optional node_fqdn in manifest
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip) ZIP_PATH="${2:-}"; shift 2 ;;
    --trigger) TRIGGER="${2:-}"; shift 2 ;;
    --fqdn) FQDN="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

case "$TRIGGER" in
  manual|scheduled|pre-upgrade) ;;
  *) echo "upload-sbc-backup: bad --trigger" >&2; exit 2 ;;
esac

if [[ "${ENABLED}" != "true" && "${ENABLED}" != "1" ]]; then
  echo "upload-sbc-backup: upload disabled (PBX3_BACKUP_UPLOAD_ENABLED=${ENABLED})"
  exit 0
fi

if [[ -z "$BUCKET" ]]; then
  echo "upload-sbc-backup: PBX3_ORG_BUCKET unset — local-only" >&2
  exit 0
fi

if [[ -z "$ZIP_PATH" ]]; then
  echo "upload-sbc-backup: --zip required" >&2
  usage
  exit 2
fi

if [[ "$ZIP_PATH" = "$(basename "$ZIP_PATH")" ]]; then
  ZIP_PATH="${BKUP_DIR}/${ZIP_PATH}"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "upload-sbc-backup: file not found: $ZIP_PATH" >&2
  exit 1
fi

BASENAME="$(basename "$ZIP_PATH")"
if [[ ! "$BASENAME" =~ ^sbcbak\.([0-9]+)\.zip$ ]]; then
  echo "upload-sbc-backup: expected sbcbak.{epoch}.zip, got: $BASENAME" >&2
  exit 1
fi
EPOCH="${BASH_REMATCH[1]}"
STAMP="$(date -u -d "@${EPOCH}" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -r "$EPOCH" +%Y%m%dT%H%M%SZ)"
CREATED_AT="$(date -u -d "@${EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

if [[ -z "$FQDN" ]]; then
  FQDN="$(tr -d '\n' </etc/hostname 2>/dev/null || echo "")"
fi
if getent hosts sbc.pbx3.com >/dev/null 2>&1; then
  FQDN="sbc.pbx3.com"
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "upload-sbc-backup: aws CLI required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "upload-sbc-backup: jq required" >&2
  exit 1
fi

SHA256="$(sha256sum "$ZIP_PATH" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
BYTES="$(wc -c <"$ZIP_PATH" | tr -d ' ')"

VERSION="unknown"
if [[ -d /home/ubuntu/pbx3sbc/.git ]]; then
  VERSION="$(git -C /home/ubuntu/pbx3sbc describe --always --dirty 2>/dev/null || echo unknown)"
elif [[ -d "$(dirname "$(dirname "${BASH_SOURCE[0]}")")/.git" ]]; then
  VERSION="$(git -C "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" describe --always --dirty 2>/dev/null || echo unknown)"
fi

PREFIX="sbc/${SBC_ID}/backups"
STAMP_PREFIX="${PREFIX}/${STAMP}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MANIFEST="${TMP}/manifest.json"
jq -n \
  --arg created "$CREATED_AT" \
  --arg sbc "$SBC_ID" \
  --arg fqdn "$FQDN" \
  --arg ver "$VERSION" \
  --arg trigger "$TRIGGER" \
  --arg sha "$SHA256" \
  --argjson bytes "$BYTES" \
  '{
    schema_version: 1,
    created_at: $created,
    scope: "sbc",
    trigger: $trigger,
    sbc_id: $sbc,
    node_fqdn: $fqdn,
    pbx3sbc_version: $ver,
    contents_summary: {},
    artifacts: [{name: "backup.zip", sha256: $sha, bytes: $bytes}]
  }' >"$MANIFEST"

echo "upload-sbc-backup: s3://${BUCKET}/${STAMP_PREFIX}/backup.zip"
aws s3 cp "$ZIP_PATH" "s3://${BUCKET}/${STAMP_PREFIX}/backup.zip" \
  --content-type application/zip --only-show-errors
aws s3 cp "$MANIFEST" "s3://${BUCKET}/${STAMP_PREFIX}/manifest.json" \
  --content-type application/json --only-show-errors

tag_obj() {
  local key=$1
  if aws s3api put-object-tagging --bucket "$BUCKET" --key "$key" \
    --tagging 'TagSet=[{Key=class,Value=backup}]' 2>/dev/null; then
    :
  else
    echo "upload-sbc-backup: warn: PutObjectTagging failed for ${key}" >&2
  fi
}
tag_obj "${STAMP_PREFIX}/backup.zip"
tag_obj "${STAMP_PREFIX}/manifest.json"

if ! aws s3api head-object --bucket "$BUCKET" --key "${STAMP_PREFIX}/backup.zip" >/dev/null 2>&1; then
  echo "upload-sbc-backup: verify failed — backup.zip missing after upload" >&2
  exit 1
fi

POLICY_KEY="${PREFIX}/policy.json"
if ! aws s3api head-object --bucket "$BUCKET" --key "$POLICY_KEY" >/dev/null 2>&1; then
  jq -n '{maxage_days: 30, glacier_after_days: 0, legal_hold: false}' >"${TMP}/policy.json"
  aws s3 cp "${TMP}/policy.json" "s3://${BUCKET}/${POLICY_KEY}" \
    --content-type application/json --only-show-errors
  echo "upload-sbc-backup: wrote ${POLICY_KEY}"
fi

echo "upload-sbc-backup: complete ${STAMP}"
