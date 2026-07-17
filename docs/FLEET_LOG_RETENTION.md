# SBC log retention & SIP capture (Phase 3)

**Status:** Shipped on branch **`logs`** (2026-07-17).  
**Spec:** **`pbx3/pbx3-directory/docs/FLEET_LOG_RETENTION_REQUIREMENTS.md`**.

## Installer map

| Piece | Fresh `install.sh` | `scripts/install-log-retention.sh` |
|-------|--------------------|-------------------------------------|
| OpenSIPS rsyslog split + logrotate | **CORE** (`configure_opensips_logging`) | Idempotent re-apply |
| SIP pcap dumpcap ring | **CORE** (`configure_sip_pcap`) | Idempotent re-apply |
| `log-ship.env` + ship binary + daily cron | Banner points here | **S3-OPT** |

## What it does

| Stream | Local | S3 |
|--------|-------|-----|
| OpenSIPS text | rsyslog split → `/var/log/opensips/opensips.log` (not shared syslog); logrotate 7d | `sbc/{id}/logs/opensips/…` (30d tag) |
| syslog | system rsyslog (host noise only — OpenSIPS stopped from here) | `sbc/{id}/logs/syslog/…` |
| SIP pcap (no RTP) | systemd **`pbx3sbc-sip-pcap`** dumpcap ring | `sbc/{id}/logs/sip-pcap/…` |

**OpenSIPS logging:** `programname == opensips` → dedicated file (`stop` — no duplicate in `/var/log/syslog`). Lab Fail2ban uses **systemd journal**, so this split does not change ban input.

## S3 ship (when bucket/IAM ready)

```bash
cd /path/to/pbx3sbc
sudo ./scripts/install-log-retention.sh
sudoedit /etc/pbx3sbc/log-ship.env   # PBX3_ORG_BUCKET, PBX3_SBC_ID=sbc
```

IAM: apply **`pbx3-directory/schema/pbx3-sbc-s3-writer.policy.json.tmpl`** (replace `__BUCKET__`, `__SBC_ID__`) to the SBC instance role.

```bash
systemctl status pbx3sbc-sip-pcap
sudo /usr/local/bin/pbx3sbc-ship-logs-to-s3 --dry-run
sudo /usr/local/bin/pbx3sbc-ship-logs-to-s3 --limit=5
```

Lifecycle (ops Mac): **`apply-logs-lifecycle-rules.sh BUCKET`** (merges instance + sbc + control tag rules).

## Solo vs fleet

SBC is always the fleet SIP edge. Instance `sys-ua-siplog` stays **off** in fleet (`siplog-set-mode.sh fleet`).
