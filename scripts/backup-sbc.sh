#!/usr/bin/env bash
# Create a local SBC backup zip (MariaDB dump + selective config).
# Spec: pbx3/pbx3-directory/docs/SBC_BACKUP_RESTORE_REQUIREMENTS.md
#
# Usage:
#   sudo ./backup-sbc.sh [--trigger manual|scheduled|pre-upgrade] [--dry-run] [--no-prune]
#   sudo ./backup-sbc.sh --upload   # create then upload-sbc-backup.sh
#
# Output: /var/lib/pbx3sbc/bkup/sbcbak.{epoch}.zip
# Env (optional): /etc/pbx3sbc/log-ship.env for PBX3_SBC_ID / FQDN hints;
#   PBX3SBC_ADMIN_ENV — path to admin .env (default lab: /home/ubuntu/pbx3sbc-admin/.env)
#   PBX3SBC_BKUP_DIR — override local backup dir
#   PBX3SBC_BKUP_KEEP — local FIFO count (default 9)
#   PBX3SBC_DB — database name (default opensips)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${PBX3_LOG_SHIP_ENV:-/etc/pbx3sbc/log-ship.env}"
[[ -f "$ENV_FILE" ]] && # shellcheck disable=SC1090
  source "$ENV_FILE"

TRIGGER="manual"
DRY_RUN=0
DO_UPLOAD=0
NO_PRUNE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger)
      TRIGGER="${2:-}"
      shift 2
      ;;
    --trigger=*)
      TRIGGER="${1#--trigger=}"
      shift
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --upload) DO_UPLOAD=1; shift ;;
    --no-prune) NO_PRUNE=1; shift ;;
    -h|--help)
      sed -n '2,16p' "$0" | tr -d '#'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

case "$TRIGGER" in
  manual|scheduled|pre-upgrade) ;;
  *)
    echo "backup-sbc: --trigger must be manual|scheduled|pre-upgrade" >&2
    exit 2
    ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  echo "backup-sbc: run as root (sudo)" >&2
  exit 1
fi

BKUP_DIR="${PBX3SBC_BKUP_DIR:-/var/lib/pbx3sbc/bkup}"
KEEP="${PBX3SBC_BKUP_KEEP:-9}"
DB_NAME="${PBX3SBC_DB:-opensips}"
ADMIN_ENV="${PBX3SBC_ADMIN_ENV:-/home/ubuntu/pbx3sbc-admin/.env}"
SBC_ID="${PBX3_SBC_ID:-sbc}"
FQDN="${PBX3_SBC_FQDN:-}"
if [[ -z "$FQDN" ]] && [[ -f /etc/hostname ]]; then
  FQDN="$(tr -d '\n' </etc/hostname)"
fi
# Prefer public admin hostname when known
if [[ -z "${PBX3_SBC_FQDN:-}" ]] && getent hosts sbc.pbx3.com >/dev/null 2>&1; then
  FQDN="sbc.pbx3.com"
fi

IGNORE_TABLES=(
  dialog
  location
  sessions
  cache
  cache_locks
  jobs
  job_batches
  failed_jobs
)

EPOCH="$(date -u +%s)"
STAMP="$(date -u -d "@${EPOCH}" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -r "$EPOCH" +%Y%m%dT%H%M%SZ)"
CREATED_AT="$(date -u -d "@${EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
ZIP_NAME="sbcbak.${EPOCH}.zip"
ZIP_PATH="${BKUP_DIR}/${ZIP_NAME}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN would create ${ZIP_PATH}"
  echo "  DB=${DB_NAME} ignore=${IGNORE_TABLES[*]}"
  echo "  include: opensips.sql, /etc/opensips/opensips.cfg, .mysql_credentials (if any), admin .env"
  echo "  trigger=${TRIGGER} sbc_id=${SBC_ID} stamp=${STAMP}"
  exit 0
fi

make_zip() {
  local dest=$1
  shift
  if command -v zip >/dev/null 2>&1; then
    zip -q -r "$dest" "$@"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$dest" "$@" <<'PY'
import sys, zipfile, os
dest = sys.argv[1]
with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for root_name in sys.argv[2:]:
        if os.path.isfile(root_name):
            zf.write(root_name, root_name)
        elif os.path.isdir(root_name):
            for dirpath, _, filenames in os.walk(root_name):
                for fn in filenames:
                    path = os.path.join(dirpath, fn)
                    zf.write(path, path)
PY
  else
    echo "backup-sbc: need zip or python3 to build archive" >&2
    exit 1
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "backup-sbc: jq required" >&2
  exit 1
fi

mkdir -p "$BKUP_DIR"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

DUMP_ARGS=(--single-transaction --routines --triggers --databases "$DB_NAME")
for t in "${IGNORE_TABLES[@]}"; do
  DUMP_ARGS+=(--ignore-table="${DB_NAME}.${t}")
done

echo "backup-sbc: dumping ${DB_NAME} (soft-state excluded)..."
# Prefer root unix_socket (lab); fall back to defaults file if present
if mysqldump "${DUMP_ARGS[@]}" >"${STAGE}/opensips.sql" 2>/tmp/pbx3sbc-mysqldump.err; then
  :
elif [[ -f /etc/opensips/.mysql_credentials ]]; then
  # shellcheck disable=SC1091
  source /etc/opensips/.mysql_credentials
  mysqldump -u"${DB_USER:-opensips}" -p"${DB_PASS:?}" "${DUMP_ARGS[@]}" >"${STAGE}/opensips.sql"
else
  cat /tmp/pbx3sbc-mysqldump.err >&2 || true
  echo "backup-sbc: mysqldump failed (try root socket or /etc/opensips/.mysql_credentials)" >&2
  exit 1
fi

if [[ ! -s "${STAGE}/opensips.sql" ]]; then
  echo "backup-sbc: opensips.sql empty" >&2
  exit 1
fi
# Strip MariaDB dump sandbox prologue so restore clients accept DDL
grep -v 'enable the sandbox mode' "${STAGE}/opensips.sql" >"${STAGE}/opensips.sql.clean"
mv "${STAGE}/opensips.sql.clean" "${STAGE}/opensips.sql"

mkdir -p "${STAGE}/etc/opensips"
if [[ -f /etc/opensips/opensips.cfg ]]; then
  cp -a /etc/opensips/opensips.cfg "${STAGE}/etc/opensips/"
fi
if [[ -f /etc/opensips/.mysql_credentials ]]; then
  cp -a /etc/opensips/.mysql_credentials "${STAGE}/etc/opensips/"
fi

if [[ -f "$ADMIN_ENV" ]]; then
  mkdir -p "${STAGE}/pbx3sbc-admin"
  cp -a "$ADMIN_ENV" "${STAGE}/pbx3sbc-admin/.env"
else
  echo "backup-sbc: warn: admin .env not found at ${ADMIN_ENV}" >&2
fi

# Sidecar for upload (not required inside zip; upload script can rebuild)
SUMMARY_JSON=$(jq -n \
  --arg trigger "$TRIGGER" \
  --arg sbc "$SBC_ID" \
  --arg fqdn "$FQDN" \
  --arg created "$CREATED_AT" \
  --arg stamp "$STAMP" \
  --arg epoch "$EPOCH" \
  '{
    trigger: $trigger,
    sbc_id: $sbc,
    node_fqdn: $fqdn,
    created_at: $created,
    backup_stamp: $stamp,
    epoch: ($epoch | tonumber)
  }')
echo "$SUMMARY_JSON" >"${STAGE}/backup-meta.json"

ZIP_ARGS=(opensips.sql backup-meta.json)
[[ -d "${STAGE}/etc" ]] && ZIP_ARGS+=(etc)
[[ -d "${STAGE}/pbx3sbc-admin" ]] && ZIP_ARGS+=(pbx3sbc-admin)
(
  cd "$STAGE"
  make_zip "$ZIP_PATH" "${ZIP_ARGS[@]}"
)

chmod 640 "$ZIP_PATH"
chown root:root "$ZIP_PATH" 2>/dev/null || true

echo "backup-sbc: wrote ${ZIP_PATH} ($(wc -c <"$ZIP_PATH" | tr -d ' ') bytes)"

if [[ "$NO_PRUNE" -eq 0 ]]; then
  # FIFO keep N newest sbcbak.*.zip
  mapfile -t OLD < <(ls -1t "${BKUP_DIR}"/sbcbak.*.zip 2>/dev/null | tail -n +"$((KEEP + 1))" || true)
  for f in "${OLD[@]:-}"; do
    [[ -n "$f" ]] || continue
    echo "backup-sbc: prune local $f"
    rm -f "$f"
  done
fi

# Write companion manifest path hint for upload
echo "${ZIP_PATH}"

if [[ "$DO_UPLOAD" -eq 1 ]]; then
  exec "${SCRIPT_DIR}/upload-sbc-backup.sh" --zip "$ZIP_PATH" --trigger "$TRIGGER"
fi
