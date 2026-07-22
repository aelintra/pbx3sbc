#!/usr/bin/env bash
# Filament / fleet panel helper for SBC cold backup (list + create).
# Invoked as: sudo -n sbc-backup-panel.sh <list|create|vip-role> …
# Spec: SBC_BACKUP_RESTORE_REQUIREMENTS.md — DR only; warm sync is Fleet.
#
# Subcommands:
#   list                 JSON { backups: [...] }
#   create [--upload]    run backup-sbc.sh; JSON { zip, epoch, stamp, uploaded }
#   warm-pull [--stamp]  S3 fetch + restore --db-only (standby warmth)
#   vip-role             JSON { vip_holder, advertised_address, local_ips }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BKUP_DIR="${PBX3SBC_BKUP_DIR:-/var/lib/pbx3sbc/bkup}"
OPENSIPS_CFG="${PBX3SBC_OPENSIPS_CFG:-/etc/opensips/opensips.cfg}"

usage() {
  sed -n '2,12p' "$0" | tr -d '#'
}

cmd="${1:-}"
shift || true

case "$cmd" in
  list)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "sbc-backup-panel: run as root (sudo)" >&2
      exit 1
    fi
    mkdir -p "$BKUP_DIR"
    # Optional S3 presence map (stamp → true) for Filament “On S3?” column
    S3_STAMPS='{}'
    ENV_FILE="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
    # shellcheck disable=SC1090
    [[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || true
    BUCKET="${PBX3_ORG_BUCKET:-}"
    SBC_ID="${PBX3_SBC_ID:-sbc}"
    REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    export AWS_DEFAULT_REGION="$REGION"
    if [[ -n "$BUCKET" ]] && command -v aws >/dev/null 2>&1; then
      PREFIX="sbc/${SBC_ID}/backups"
      S3_STAMPS="$(
        aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "${PREFIX}/" --delimiter / \
          --query 'CommonPrefixes[].Prefix' --output text 2>/dev/null \
          | tr '\t' '\n' | sed -n "s|^${PREFIX}/\\([^/]*\\)/|\\1|p" \
          | jq -Rnc '[inputs | select(length>0)] | map({(.): true}) | add // {}' \
          || echo '{}'
      )"
      [[ -n "$S3_STAMPS" && "$S3_STAMPS" != "null" ]] || S3_STAMPS='{}'
    fi
    # shellcheck disable=SC2012
    mapfile -t FILES < <(ls -1t "${BKUP_DIR}"/sbcbak.*.zip 2>/dev/null || true)
    JSON='[]'
    for f in "${FILES[@]:-}"; do
      [[ -n "$f" && -f "$f" ]] || continue
      base="$(basename "$f")"
      if [[ ! "$base" =~ ^sbcbak\.([0-9]+)\.zip$ ]]; then
        continue
      fi
      epoch="${BASH_REMATCH[1]}"
      stamp="$(date -u -d "@${epoch}" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -r "$epoch" +%Y%m%dT%H%M%SZ)"
      created="$(date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ)"
      bytes="$(wc -c <"$f" | tr -d ' ')"
      on_s3="$(jq -r --arg s "$stamp" '.[$s] // false' <<<"$S3_STAMPS")"
      [[ "$on_s3" == "true" ]] && on_s3=true || on_s3=false
      JSON="$(jq -c --arg name "$base" --arg path "$f" --arg stamp "$stamp" \
        --arg created "$created" --argjson epoch "$epoch" --argjson bytes "$bytes" \
        --argjson on_s3 "$on_s3" \
        '. + [{name:$name, path:$path, backup_stamp:$stamp, created_at:$created, epoch:$epoch, bytes:$bytes, on_s3:$on_s3}]' <<<"$JSON")"
    done
    jq -n --argjson backups "$JSON" '{backups:$backups}'
    ;;

  create)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "sbc-backup-panel: run as root (sudo)" >&2
      exit 1
    fi
    DO_UPLOAD=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --upload) DO_UPLOAD=1; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
      esac
    done
    ARGS=(--trigger manual)
    [[ "$DO_UPLOAD" -eq 1 ]] && ARGS+=(--upload)
    # Capture last line (zip path); upload script prints more after exec replace —
    # when --upload, backup-sbc execs upload; parse zip from earlier echo.
    OUT="$("${SCRIPT_DIR}/backup-sbc.sh" "${ARGS[@]}" 2>&1)" || {
      echo "$OUT" >&2
      exit 1
    }
    echo "$OUT" >&2
    ZIP_PATH="$(echo "$OUT" | grep -E '^/.*sbcbak\.[0-9]+\.zip$' | tail -1 || true)"
    if [[ -z "$ZIP_PATH" ]]; then
      ZIP_PATH="$(echo "$OUT" | grep -Eo '/var/lib/pbx3sbc/bkup/sbcbak\.[0-9]+\.zip' | tail -1 || true)"
    fi
    if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
      # After --upload, zip still on disk; find newest
      ZIP_PATH="$(ls -1t "${BKUP_DIR}"/sbcbak.*.zip 2>/dev/null | head -1 || true)"
    fi
    if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
      echo "sbc-backup-panel: could not determine zip path" >&2
      exit 1
    fi
    base="$(basename "$ZIP_PATH")"
    [[ "$base" =~ ^sbcbak\.([0-9]+)\.zip$ ]] || {
      echo "sbc-backup-panel: bad zip name $base" >&2
      exit 1
    }
    epoch="${BASH_REMATCH[1]}"
    stamp="$(date -u -d "@${epoch}" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -r "$epoch" +%Y%m%dT%H%M%SZ)"
    uploaded=false
    if echo "$OUT" | grep -q 'upload-sbc-backup: complete'; then
      uploaded=true
    fi
    jq -cn \
      --arg zip "$ZIP_PATH" \
      --arg stamp "$stamp" \
      --argjson epoch "$epoch" \
      --argjson uploaded "$uploaded" \
      '{zip:$zip, backup_stamp:$stamp, epoch:$epoch, uploaded:$uploaded}'
    ;;

  warm-pull)
    if [[ "$(id -u)" -ne 0 ]]; then
      echo "sbc-backup-panel: run as root (sudo)" >&2
      exit 1
    fi
    STAMP=""
    RESTART=1
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --stamp) STAMP="${2:-}"; shift 2 ;;
        --stamp=*) STAMP="${1#--stamp=}"; shift ;;
        --no-restart) RESTART=0; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
      esac
    done

    # Refuse on VIP holder — warm pull is for standby only
    ROLE_JSON="$(bash "$0" vip-role)"
    if jq -e '.vip_holder == true' <<<"$ROLE_JSON" >/dev/null 2>&1; then
      echo "sbc-backup-panel: warm-pull refused — this host holds the VIP (use Sync on standby)" >&2
      exit 3
    fi

    ENV_FILE="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
    [[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
      source "$ENV_FILE"
    BUCKET="${PBX3_ORG_BUCKET:-}"
    SBC_ID="${PBX3_SBC_ID:-sbc}"
    REGION="${AWS_DEFAULT_REGION:-us-east-1}"
    export AWS_DEFAULT_REGION="$REGION"
    if [[ -z "$BUCKET" ]]; then
      echo "sbc-backup-panel: PBX3_ORG_BUCKET unset" >&2
      exit 1
    fi
    if ! command -v aws >/dev/null 2>&1; then
      echo "sbc-backup-panel: aws CLI required" >&2
      exit 1
    fi

    PREFIX="sbc/${SBC_ID}/backups"
    if [[ -z "$STAMP" ]]; then
      STAMP="$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "${PREFIX}/" --delimiter / \
        --query 'CommonPrefixes[].Prefix' --output text 2>/dev/null \
        | tr '\t' '\n' | sed -n "s|^${PREFIX}/\\([^/]*\\)/|\\1|p" | sort | tail -1 || true)"
    fi
    if [[ -z "$STAMP" ]]; then
      echo "sbc-backup-panel: no S3 backup stamps under s3://${BUCKET}/${PREFIX}/" >&2
      exit 1
    fi

    # stamp YYYYMMDDThhmmssZ → epoch for local zip name
    EPOCH="$(python3 - "$STAMP" <<'PY' 2>/dev/null || true
import sys
from datetime import datetime, timezone
s = sys.argv[1]
dt = datetime.strptime(s, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
print(int(dt.timestamp()))
PY
)"
    if [[ -z "$EPOCH" ]]; then
      y=${STAMP:0:4}; mo=${STAMP:4:2}; d=${STAMP:6:2}
      h=${STAMP:9:2}; mi=${STAMP:11:2}; se=${STAMP:13:2}
      EPOCH="$(date -u -d "${y}-${mo}-${d} ${h}:${mi}:${se}" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%d %H:%M:%S" "${y}-${mo}-${d} ${h}:${mi}:${se}" +%s)"
    fi

    mkdir -p "$BKUP_DIR"
    ZIP_PATH="${BKUP_DIR}/sbcbak.${EPOCH}.zip"
    echo "sbc-backup-panel: fetching s3://${BUCKET}/${PREFIX}/${STAMP}/backup.zip" >&2
    aws s3 cp "s3://${BUCKET}/${PREFIX}/${STAMP}/backup.zip" "$ZIP_PATH" --only-show-errors
    chmod 640 "$ZIP_PATH" || true

    RESTORE_ARGS=(--db-only --yes)
    [[ "$RESTART" -eq 1 ]] && RESTORE_ARGS+=(--restart)
    echo "sbc-backup-panel: restore --db-only ${ZIP_PATH}" >&2
    "${SCRIPT_DIR}/restore-sbc-backup.sh" "${RESTORE_ARGS[@]}" "$ZIP_PATH" >&2

    jq -cn \
      --arg stamp "$STAMP" \
      --arg zip "$ZIP_PATH" \
      --argjson epoch "$EPOCH" \
      --argjson restarted "$RESTART" \
      '{ok:true, backup_stamp:$stamp, zip:$zip, epoch:$epoch, restarted:($restarted==1)}'
    ;;

  vip-role)
    # Does this host hold the OpenSIPS advertised_address (EIP/VIP)?
    # HA standby keeps advertised_address=EIP in cfg but EIP is on active only.
    # On AWS the EIP is often NOT on a local iface (1:1 NAT) — also check IMDS public-ipv4.
    ADV=""
    if [[ -f "$OPENSIPS_CFG" ]]; then
      ADV="$(grep -E '^\s*advertised_address=' "$OPENSIPS_CFG" 2>/dev/null \
        | head -1 | sed -E 's/.*advertised_address="?([^";]+)"?.*/\1/' | tr -d '[:space:]' || true)"
    fi
    LOCAL_JSON='[]'
    if command -v ip >/dev/null 2>&1; then
      while read -r ipaddr; do
        [[ -n "$ipaddr" ]] || continue
        LOCAL_JSON="$(jq -c --arg ip "$ipaddr" '. + [$ip]' <<<"$LOCAL_JSON")"
      done < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
    fi
    if [[ "$LOCAL_JSON" == '[]' ]]; then
      for ipaddr in $(hostname -I 2>/dev/null || true); do
        LOCAL_JSON="$(jq -c --arg ip "$ipaddr" '. + [$ip]' <<<"$LOCAL_JSON")"
      done
    fi
    # EC2 public IPv4 (EIP when associated)
    PUBLIC_IP=""
    if command -v curl >/dev/null 2>&1; then
      IMDST="$(curl -sS -m 2 -X PUT 'http://169.254.169.254/latest/api/token' \
        -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null || true)"
      if [[ -n "$IMDST" ]]; then
        PUBLIC_IP="$(curl -sS -m 2 -H "X-aws-ec2-metadata-token: $IMDST" \
          http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
      else
        PUBLIC_IP="$(curl -sS -m 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)"
      fi
      PUBLIC_IP="$(echo "$PUBLIC_IP" | tr -d '[:space:]')"
      if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != *"404"* ]]; then
        LOCAL_JSON="$(jq -c --arg ip "$PUBLIC_IP" 'if index($ip) == null then . + [$ip] else . end' <<<"$LOCAL_JSON")"
      fi
    fi
    HOLDER=false
    if [[ -z "$ADV" || "$ADV" == "CHANGE_ME" ]]; then
      # Solo / unset — allow DR backup on this box
      HOLDER=true
    else
      if jq -e --arg adv "$ADV" 'index($adv) != null' <<<"$LOCAL_JSON" >/dev/null 2>&1; then
        HOLDER=true
      fi
    fi
    jq -cn \
      --argjson vip_holder "$HOLDER" \
      --arg advertised_address "$ADV" \
      --argjson local_ips "$LOCAL_JSON" \
      '{vip_holder:$vip_holder, advertised_address:$advertised_address, local_ips:$local_ips}'
    ;;

  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown subcommand: $cmd" >&2
    usage
    exit 2
    ;;
esac
