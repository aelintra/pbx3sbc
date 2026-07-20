#!/usr/bin/env bash
# Restore an SBC backup zip onto this host (cold DR).
# Spec: pbx3/pbx3-directory/docs/SBC_BACKUP_RESTORE_REQUIREMENTS.md
#
# Usage:
#   sudo ./restore-sbc-backup.sh --dry-run /var/lib/pbx3sbc/bkup/sbcbak.EPOCH.zip
#   sudo ./restore-sbc-backup.sh --full --yes sbcbak.EPOCH.zip
#   sudo ./restore-sbc-backup.sh --db-only --yes /path/to/sbcbak.EPOCH.zip
#   sudo ./restore-sbc-backup.sh --target-db opensips_restore_test --yes sbcbak.EPOCH.zip
#     (integrity check into a side schema — does not touch live opensips or FS)
#
# Default: --full (DB + selective FS). Does NOT run init-database.sh.
# After live restore: start MariaDB → OpenSIPS → admin; certbot if new host;
# catalog reconcile without wiping edge-authored rows.

set -euo pipefail

BKUP_DIR="${PBX3SBC_BKUP_DIR:-/var/lib/pbx3sbc/bkup}"
ADMIN_ENV="${PBX3SBC_ADMIN_ENV:-/home/ubuntu/pbx3sbc-admin/.env}"
DB_NAME="${PBX3SBC_DB:-opensips}"
OPENSIPS_SERVICE="${PBX3SBC_OPENSIPS_SERVICE:-opensips}"

MODE="full"          # full | db-only
DRY_RUN=0
YES=0
TARGET_DB=""         # if set, import only into this DB name (no FS, no stop services)
RESTART=0
ZIP_ARG=""

usage() {
  cat <<'EOF'
Usage: restore-sbc-backup.sh [options] PATH|basename

  --full              restore MariaDB + selective FS (default)
  --db-only           restore MariaDB only (no cfg / .env)
  --target-db NAME    import into NAME only (side-DB integrity; no FS / no service stop)
  --dry-run           show actions; make no changes
  --yes               required for non-dry-run (safety)
  --restart           after live restore, try systemctl start opensips
  PATH                sbcbak.{epoch}.zip (absolute or under /var/lib/pbx3sbc/bkup)

Run as root. Never run init-database.sh after a successful restore.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) MODE="full"; shift ;;
    --db-only) MODE="db-only"; shift ;;
    --target-db) TARGET_DB="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    --restart) RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "restore-sbc-backup: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      ZIP_ARG=$1
      shift
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "restore-sbc-backup: run as root (sudo)" >&2
  exit 1
fi

if [[ -z "$ZIP_ARG" ]]; then
  echo "restore-sbc-backup: missing zip argument" >&2
  usage
  exit 2
fi

if [[ "$DRY_RUN" -eq 0 && "$YES" -eq 0 ]]; then
  echo "restore-sbc-backup: refusing without --yes (or use --dry-run)" >&2
  exit 2
fi

BASENAME="$(basename "$ZIP_ARG")"
if [[ "$ZIP_ARG" = "$BASENAME" ]]; then
  ZIP_PATH="${BKUP_DIR}/${BASENAME}"
else
  ZIP_PATH="$ZIP_ARG"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "restore-sbc-backup: file not found: $ZIP_PATH" >&2
  exit 1
fi

if [[ ! "$BASENAME" =~ ^sbcbak\.[0-9]+\.zip$ ]]; then
  echo "restore-sbc-backup: expected sbcbak.{epoch}.zip, got: $BASENAME" >&2
  exit 1
fi

extract_zip() {
  local dest=$1
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$ZIP_PATH" -d "$dest"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$ZIP_PATH" "$dest" <<'PY'
import sys, zipfile
zf = zipfile.ZipFile(sys.argv[1])
zf.extractall(sys.argv[2])
PY
  else
    echo "restore-sbc-backup: need unzip or python3" >&2
    exit 1
  fi
}

mysql_exec() {
  # Prefer root unix_socket; fall back to OpenSIPS credentials. Do not hide errors.
  if mysql "$@"; then
    return 0
  fi
  if [[ -f /etc/opensips/.mysql_credentials ]]; then
    # shellcheck disable=SC1091
    source /etc/opensips/.mysql_credentials
    mysql -u"${DB_USER:-opensips}" -p"${DB_PASS:?}" "$@"
    return
  fi
  return 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "restore-sbc-backup: extracting $(basename "$ZIP_PATH") ..."
extract_zip "$STAGE"

SQL="${STAGE}/opensips.sql"
if [[ ! -f "$SQL" ]]; then
  echo "restore-sbc-backup: opensips.sql missing from zip" >&2
  exit 1
fi

IMPORT_DB="${TARGET_DB:-$DB_NAME}"
LIVE=1
[[ -n "$TARGET_DB" ]] && LIVE=0

echo "restore-sbc-backup: mode=${MODE} import_db=${IMPORT_DB} live=${LIVE} dry_run=${DRY_RUN}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY-RUN would:"
  echo "  - import ${SQL} -> MariaDB database ${IMPORT_DB}"
  if [[ "$LIVE" -eq 1 ]]; then
    echo "  - stop ${OPENSIPS_SERVICE} before import (if active)"
    if [[ "$MODE" = "full" ]]; then
      [[ -f "${STAGE}/etc/opensips/opensips.cfg" ]] && echo "  - restore /etc/opensips/opensips.cfg"
      [[ -f "${STAGE}/etc/opensips/.mysql_credentials" ]] && echo "  - restore /etc/opensips/.mysql_credentials"
      [[ -f "${STAGE}/pbx3sbc-admin/.env" ]] && echo "  - restore ${ADMIN_ENV}"
    fi
    [[ "$RESTART" -eq 1 ]] && echo "  - systemctl start ${OPENSIPS_SERVICE}"
  else
    echo "  - side-DB only (no FS, no service stop)"
  fi
  echo "DRY-RUN OK"
  exit 0
fi

# Prepare SQL for alternate DB name if needed
IMPORT_SQL="$SQL"
if [[ -n "$TARGET_DB" && "$TARGET_DB" != "$DB_NAME" ]]; then
  IMPORT_SQL="${STAGE}/opensips.retarget.sql"
  # Rewrite dump that used --databases opensips (must not redirect onto $SQL)
  sed -E \
    -e "s/\`${DB_NAME}\`/\`${TARGET_DB}\`/g" \
    -e "s/USE ${DB_NAME};/USE \`${TARGET_DB}\`;/g" \
    "$SQL" >"$IMPORT_SQL"
  if ! grep -q "CREATE DATABASE" "$IMPORT_SQL"; then
    { echo "CREATE DATABASE IF NOT EXISTS \`${TARGET_DB}\`;"; echo "USE \`${TARGET_DB}\`;"; cat "$IMPORT_SQL"; } >"${IMPORT_SQL}.tmp"
    mv "${IMPORT_SQL}.tmp" "$IMPORT_SQL"
  fi
  # Strip MariaDB client sandbox prologue if present (blocks DDL in some clients)
  grep -v 'enable the sandbox mode' "$IMPORT_SQL" >"${IMPORT_SQL}.nosb" && mv "${IMPORT_SQL}.nosb" "$IMPORT_SQL"
  mysql_exec -e "CREATE DATABASE IF NOT EXISTS \`${TARGET_DB}\`;" \
    || { echo "restore-sbc-backup: cannot create ${TARGET_DB}" >&2; exit 1; }
fi

# Always strip sandbox line from import payload (in-place via temp)
grep -v 'enable the sandbox mode' "$IMPORT_SQL" >"${STAGE}/opensips.import.sql"
IMPORT_SQL="${STAGE}/opensips.import.sql"

if [[ "$LIVE" -eq 1 ]]; then
  if systemctl is-active --quiet "$OPENSIPS_SERVICE" 2>/dev/null; then
    echo "restore-sbc-backup: stopping ${OPENSIPS_SERVICE} ..."
    systemctl stop "$OPENSIPS_SERVICE"
  fi
fi

echo "restore-sbc-backup: importing SQL into ${IMPORT_DB} ..."
if ! mysql_exec <"$IMPORT_SQL"; then
  echo "restore-sbc-backup: mysql import failed" >&2
  exit 1
fi

# Sanity counts
COUNTS="$(mysql_exec -N -e "
SELECT CONCAT('users=', (SELECT COUNT(*) FROM \`${IMPORT_DB}\`.users),
  ' domain=', (SELECT COUNT(*) FROM \`${IMPORT_DB}\`.domain),
  ' dr_gateways=', (SELECT COUNT(*) FROM \`${IMPORT_DB}\`.dr_gateways),
  ' fail2ban_whitelist=', (SELECT COUNT(*) FROM \`${IMPORT_DB}\`.fail2ban_whitelist));
" 2>/dev/null || echo "counts_unavailable")"
echo "restore-sbc-backup: ${COUNTS}"

if [[ "$COUNTS" = "counts_unavailable" ]] || [[ "$COUNTS" != *users=* ]]; then
  echo "restore-sbc-backup: import produced no usable tables — aborting" >&2
  exit 1
fi

if [[ "$LIVE" -eq 1 && "$MODE" = "full" ]]; then
  mkdir -p /etc/opensips
  if [[ -f "${STAGE}/etc/opensips/opensips.cfg" ]]; then
    echo "restore-sbc-backup: restoring /etc/opensips/opensips.cfg"
    cp -a "${STAGE}/etc/opensips/opensips.cfg" /etc/opensips/opensips.cfg
  fi
  if [[ -f "${STAGE}/etc/opensips/.mysql_credentials" ]]; then
    echo "restore-sbc-backup: restoring /etc/opensips/.mysql_credentials"
    cp -a "${STAGE}/etc/opensips/.mysql_credentials" /etc/opensips/.mysql_credentials
    chmod 600 /etc/opensips/.mysql_credentials
  fi
  if [[ -f "${STAGE}/pbx3sbc-admin/.env" ]]; then
    echo "restore-sbc-backup: restoring ${ADMIN_ENV}"
    mkdir -p "$(dirname "$ADMIN_ENV")"
    cp -a "${STAGE}/pbx3sbc-admin/.env" "$ADMIN_ENV"
    # Prefer ownership of parent tree owner
    if id ubuntu >/dev/null 2>&1; then
      chown ubuntu:ubuntu "$ADMIN_ENV" 2>/dev/null || true
    fi
    chmod 600 "$ADMIN_ENV"
  else
    echo "restore-sbc-backup: warn: no pbx3sbc-admin/.env in zip" >&2
  fi
fi

if [[ "$LIVE" -eq 1 && "$RESTART" -eq 1 ]]; then
  echo "restore-sbc-backup: starting ${OPENSIPS_SERVICE} ..."
  systemctl start "$OPENSIPS_SERVICE" || true
  systemctl is-active --quiet "$OPENSIPS_SERVICE" && echo "restore-sbc-backup: ${OPENSIPS_SERVICE} active" \
    || echo "restore-sbc-backup: warn: ${OPENSIPS_SERVICE} not active — check journal" >&2
fi

echo "restore-sbc-backup: OK — ${BASENAME}"
if [[ "$LIVE" -eq 1 ]]; then
  cat <<'EOF'
restore-sbc-backup: next steps (if this host is not the original)
  1. Do NOT run init-database.sh (would wipe restored data).
  2. Align MariaDB opensips password with /etc/opensips/.mysql_credentials
  3. Set advertised_address in /etc/opensips/opensips.cfg to THIS host IP
  4. sudo systemctl reset-failed opensips && sudo systemctl start opensips
  5. chmod 755 ~ and the pbx3sbc-admin dir so www-data can read .env
  6. sudo ./scripts/setup-admin-panel-sudoers.sh   # Fail2ban Log / Status panels
  7. Optional: APP_URL=http://<this-host> in admin .env; certbot if public HTTPS
  8. Filament smoke; fleet reconcile only for catalog-owned rows (Rule 13)
EOF
else
  echo "restore-sbc-backup: side-DB ${IMPORT_DB} ready — drop when done: mysql -e 'DROP DATABASE \`${IMPORT_DB}\`;'"
fi
