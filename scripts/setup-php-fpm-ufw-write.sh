#!/usr/bin/env bash
# Allow php-fpm (ProtectSystem=full) to mutate UFW rules via sudo helpers.
# Without this, uid=0 under sudo still cannot write /etc/ufw/user.rules.
#
# Usage:
#   sudo ./setup-php-fpm-ufw-write.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: run as root (sudo $0)" >&2
  exit 1
fi

DROP_IN_DIR=""
for unit in php8.4-fpm.service php8.3-fpm.service php8.2-fpm.service php-fpm.service; do
  if systemctl cat "$unit" &>/dev/null; then
    DROP_IN_DIR="/etc/systemd/system/${unit}.d"
    UNIT="$unit"
    break
  fi
done

if [[ -z "$DROP_IN_DIR" ]]; then
  echo "Error: no php-fpm systemd unit found" >&2
  exit 1
fi

mkdir -p "$DROP_IN_DIR"
CONF="${DROP_IN_DIR}/pbx3sbc-ufw-write.conf"
cat > "$CONF" <<'EOF'
# pbx3sbc — Management access panel needs to update UFW from www-data→sudo.
# ProtectSystem=full mounts /etc read-only for the service and children.
[Service]
ReadWritePaths=/etc/ufw
EOF

systemctl daemon-reload
systemctl restart "$UNIT"

echo "Installed $CONF"
echo "Restarted $UNIT"
echo "Verify: sudo -u www-data sudo -n /path/to/apply-management-access-ufw.sh --status"
