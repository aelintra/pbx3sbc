#!/bin/bash
#
# Tail Fail2ban log for pbx3sbc-admin (invoked via sudo from www-data).
# Usage: tail-fail2ban-log.sh [lines]
# Default 200 lines; hard cap 2000.
#
set -euo pipefail

LOG_FILE="${FAIL2BAN_LOG_FILE:-/var/log/fail2ban.log}"
LINES="${1:-200}"

# Digits only
if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
  echo "Invalid line count" >&2
  exit 1
fi

if (( LINES < 1 )); then
  LINES=1
fi
if (( LINES > 2000 )); then
  LINES=2000
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Log file not found: $LOG_FILE" >&2
  exit 1
fi

exec /usr/bin/tail -n "$LINES" "$LOG_FILE"
