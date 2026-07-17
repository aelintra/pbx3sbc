#!/usr/bin/env bash
# Install SBC log retention pieces (Phase 3).
# Run as root from a pbx3sbc checkout on the SBC host.
#
# Installs:
#   /etc/logrotate.d/pbx3sbc-opensips
#   /etc/systemd/system/pbx3sbc-sip-pcap.service
#   /etc/pbx3sbc/log-ship.env (from example if missing)
#   /usr/local/bin/pbx3sbc-ship-logs-to-s3
#   /etc/cron.d/pbx3sbc-logs
#
# Spec: FLEET_LOG_RETENTION_REQUIREMENTS.md

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

mkdir -p /etc/pbx3sbc /var/log/pbx3sbc/sip-pcap /var/lib/pbx3sbc

install -m 644 "$ROOT/config/logrotate.d/pbx3sbc-opensips" /etc/logrotate.d/pbx3sbc-opensips

if [[ ! -f /etc/pbx3sbc/log-ship.env ]]; then
  install -m 640 "$ROOT/config/log-ship.env.example" /etc/pbx3sbc/log-ship.env
  echo "Created /etc/pbx3sbc/log-ship.env — edit PBX3_ORG_BUCKET / PBX3_SBC_ID"
fi

install -m 644 "$ROOT/systemd/pbx3sbc-sip-pcap.service" /etc/systemd/system/pbx3sbc-sip-pcap.service
install -m 755 "$ROOT/scripts/ship-logs-to-s3.sh" /usr/local/bin/pbx3sbc-ship-logs-to-s3

# dumpcap required
if ! command -v dumpcap >/dev/null 2>&1; then
  echo "Installing tshark/dumpcap (wireshark-common)..."
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tshark || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wireshark-common || true
fi

systemctl daemon-reload
systemctl enable pbx3sbc-sip-pcap.service
systemctl restart pbx3sbc-sip-pcap.service || {
  echo "warn: pbx3sbc-sip-pcap failed to start — check dumpcap and journalctl -u pbx3sbc-sip-pcap" >&2
}

cat >/etc/cron.d/pbx3sbc-logs <<'EOF'
# SBC log ship to org S3 (after daily logrotate ~06:25)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
45 6 * * * root /usr/local/bin/pbx3sbc-ship-logs-to-s3 >> /var/log/pbx3sbc-logs-s3.log 2>&1
EOF
chmod 644 /etc/cron.d/pbx3sbc-logs

echo "Installed. Next:"
echo "  1. Edit /etc/pbx3sbc/log-ship.env"
echo "  2. Attach IAM allowing s3://\$BUCKET/sbc/\$PBX3_SBC_ID/logs/* (see pbx3-directory schema)"
echo "  3. systemctl status pbx3sbc-sip-pcap"
echo "  4. /usr/local/bin/pbx3sbc-ship-logs-to-s3 --dry-run"
echo "  5. Ops: apply-logs-lifecycle-rules.sh (includes sbc/ tags when re-run)"
