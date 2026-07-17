#!/usr/bin/env bash
# Ship rotated SBC logs + completed SIP pcap segments to org S3.
# Spec: FLEET_LOG_RETENTION_REQUIREMENTS.md Phase 3
#
# Keys: s3://$PBX3_ORG_BUCKET/sbc/$PBX3_SBC_ID/logs/{class}/{stamp}/{basename}
# Classes: opensips | syslog | sip-pcap
#
# Usage:
#   sudo ./ship-logs-to-s3.sh [--limit N] [--dry-run]
# Requires: aws CLI, IAM (instance role or keys) for sbc/{id}/logs/*
# Env: /etc/pbx3sbc/log-ship.env

set -euo pipefail
shopt -s nullglob

ENV_FILE="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
[[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"

LIMIT=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--limit N] [--dry-run]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

BUCKET="${PBX3_ORG_BUCKET:-}"
SBC_ID="${PBX3_SBC_ID:-sbc}"
ENABLED="${PBX3_LOG_UPLOAD_ENABLED:-true}"
STATE_PATH="${PBX3_LOG_SHIP_STATE:-/var/lib/pbx3sbc/log-ship-state.json}"
SIP_DIR="${SIP_PCAP_DIR:-/var/log/pbx3sbc/sip-pcap}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

if [[ "${ENABLED}" != "true" && "${ENABLED}" != "1" ]]; then
  echo "upload disabled (PBX3_LOG_UPLOAD_ENABLED=${ENABLED})"
  exit 0
fi
if [[ -z "$BUCKET" ]]; then
  echo "PBX3_ORG_BUCKET unset — local-only mode" >&2
  exit 0
fi
if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq required" >&2
  exit 1
fi

mkdir -p "$(dirname "$STATE_PATH")"
[[ -f "$STATE_PATH" ]] || echo '{}' >"$STATE_PATH"

fingerprint() {
  local path=$1
  local ino size mtime
  ino=$(stat -c '%i' "$path" 2>/dev/null || stat -f '%i' "$path")
  size=$(stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path")
  mtime=$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path")
  printf '%s' "${path}|${ino}|${size}|${mtime}" | sha256sum | awk '{print $1}'
}

stamp_for() {
  local path=$1
  local mtime
  mtime=$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path")
  date -u -d "@${mtime}" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -r "$mtime" +%Y%m%dT%H%M%SZ
}

is_rotated() {
  local base=$1 class=$2
  case "$class" in
    opensips) [[ "$base" =~ ^opensips\.log\.[0-9] ]] ;;
    syslog) [[ "$base" =~ ^syslog\.[0-9] ]] ;;
    sip-pcap)
      # dumpcap ring: siplog_*.pcap (completed); skip live siplog.pcap
      [[ "$base" =~ ^siplog_.*\.pcap$ ]] || [[ "$base" =~ ^siplog\.pcap[0-9]+$ ]]
      ;;
    *) return 1 ;;
  esac
}

collect() {
  local class=$1
  shift
  local pattern path base
  for pattern in "$@"; do
    # shellcheck disable=SC2086
    for path in $pattern; do
      [[ -f "$path" && -r "$path" ]] || continue
      base=$(basename "$path")
      if is_rotated "$base" "$class"; then
        printf '%s\t%s\n' "$class" "$path"
      fi
    done
  done
}

# Ensure policy.json once
POLICY_KEY="sbc/${SBC_ID}/logs/policy.json"
if [[ "$DRY_RUN" -eq 0 ]]; then
  if ! aws s3api head-object --bucket "$BUCKET" --key "$POLICY_KEY" >/dev/null 2>&1; then
    POLICY_JSON=$(jq -n '{
      schema_version: 1,
      classes: { syslog: 30, opensips: 30, "sip-pcap": 30 },
      updated_at: (now | todateiso8601)
    }')
    echo "$POLICY_JSON" | aws s3 cp - "s3://${BUCKET}/${POLICY_KEY}" --content-type application/json
  fi
fi

mapfile -t CANDIDATES < <(
  {
    collect opensips "/var/log/opensips/opensips.log.[0-9]*" "/var/log/opensips/opensips.log.*.gz"
    collect syslog "/var/log/syslog.[0-9]*" "/var/log/syslog.*.gz"
    collect sip-pcap "${SIP_DIR}/siplog_*.pcap" "${SIP_DIR}/siplog.pcap[0-9]*"
  } | sort -u
)

uploaded=0
skipped=0
errors=0
count=0

for line in "${CANDIDATES[@]:-}"; do
  [[ -z "$line" ]] && continue
  class=${line%%$'\t'*}
  path=${line#*$'\t'}
  [[ -f "$path" ]] || continue

  if [[ -n "$LIMIT" && "$count" -ge "$LIMIT" ]]; then
    break
  fi
  count=$((count + 1))

  fp=$(fingerprint "$path")
  if jq -e --arg fp "$fp" 'has($fp)' "$STATE_PATH" >/dev/null 2>&1; then
    skipped=$((skipped + 1))
    continue
  fi

  stamp=$(stamp_for "$path")
  base=$(basename "$path")
  key="sbc/${SBC_ID}/logs/${class}/${stamp}/${base}"
  tag="class=${class}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN would upload $path -> s3://${BUCKET}/${key} (${tag})"
    uploaded=$((uploaded + 1))
    continue
  fi

  if aws s3 cp "$path" "s3://${BUCKET}/${key}" --only-show-errors \
    && aws s3api put-object-tagging --bucket "$BUCKET" --key "$key" \
      --tagging "TagSet=[{Key=class,Value=${class}}]" 2>/dev/null; then
    :
  elif aws s3 cp "$path" "s3://${BUCKET}/${key}" --only-show-errors; then
    echo "warn: uploaded without tag (PutObjectTagging denied?): $key" >&2
  else
    echo "error: upload failed: $path" >&2
    errors=$((errors + 1))
    continue
  fi

  tmp=$(mktemp)
  jq --arg fp "$fp" --arg path "$path" --arg class "$class" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.[$fp] = {path: $path, class: $class, shipped_at: $at}' "$STATE_PATH" >"$tmp"
  mv "$tmp" "$STATE_PATH"
  uploaded=$((uploaded + 1))
  echo "uploaded $path -> s3://${BUCKET}/${key}"
done

echo "Log ship: ${uploaded} uploaded, ${skipped} skipped, ${errors} errors"
[[ "$errors" -eq 0 ]] || exit 1
