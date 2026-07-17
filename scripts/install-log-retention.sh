#!/usr/bin/env bash
# Install SBC log retention (Phase 3) — upgrade / existing hosts, or S3 ship follow-up.
# Run as root from a pbx3sbc checkout on the SBC host.
#
# Fresh installs: install.sh already does CORE pieces (rsyslog OpenSIPS split + sip-pcap).
# This script is idempotent and also installs S3-OPT pieces:
#   /etc/pbx3sbc/log-ship.env
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

mkdir -p /etc/pbx3sbc /var/log/pbx3sbc/sip-pcap /var/lib/pbx3sbc /var/log/opensips
# rsyslog writes the dedicated file; keep dir writable by syslog
chown syslog:adm /var/log/opensips
chmod 755 /var/log/opensips

# CORE (same as install.sh configure_opensips_logging / configure_sip_pcap)
if [[ -f "$ROOT/config/rsyslog.d/30-pbx3sbc-opensips.conf" ]]; then
  install -m 644 "$ROOT/config/rsyslog.d/30-pbx3sbc-opensips.conf" /etc/rsyslog.d/30-pbx3sbc-opensips.conf
fi
install -m 644 "$ROOT/config/logrotate.d/pbx3sbc-opensips" /etc/logrotate.d/pbx3sbc-opensips

if systemctl is-active --quiet rsyslog 2>/dev/null || systemctl is-enabled --quiet rsyslog 2>/dev/null; then
  systemctl restart rsyslog || {
    echo "warn: rsyslog restart failed — check /etc/rsyslog.d/30-pbx3sbc-opensips.conf" >&2
  }
fi

install -m 644 "$ROOT/systemd/pbx3sbc-sip-pcap.service" /etc/systemd/system/pbx3sbc-sip-pcap.service

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

# S3-OPT — ship rotated/completed files when bucket + IAM ready
if [[ ! -f /etc/pbx3sbc/log-ship.env ]]; then
  install -m 640 "$ROOT/config/log-ship.env.example" /etc/pbx3sbc/log-ship.env
  echo "Created /etc/pbx3sbc/log-ship.env — edit PBX3_ORG_BUCKET / PBX3_SBC_ID"
fi

install -m 755 "$ROOT/scripts/ship-logs-to-s3.sh" /usr/local/bin/pbx3sbc-ship-logs-to-s3

cat >/etc/cron.d/pbx3sbc-logs <<'EOF'
# SBC log ship to org S3 (after daily logrotate ~06:25)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
45 6 * * * root /usr/local/bin/pbx3sbc-ship-logs-to-s3 >> /var/log/pbx3sbc-logs-s3.log 2>&1
EOF
chmod 644 /etc/cron.d/pbx3sbc-logs

echo "Installed. Next:"
echo "  1. Edit /etc/pbx3sbc/log-ship.env (S3 upload)"
echo "  2. Attach IAM allowing s3://\$BUCKET/sbc/\$PBX3_SBC_ID/logs/* (see pbx3-directory schema)"
echo "  3. Confirm OpenSIPS → dedicated log: tail -f /var/log/opensips/opensips.log"
echo "  4. systemctl status pbx3sbc-sip-pcap"
echo "  5. /usr/local/bin/pbx3sbc-ship-logs-to-s3 --dry-run"
echo "  6. Ops: apply-logs-lifecycle-rules.sh (includes sbc/ + control/ tags)"
