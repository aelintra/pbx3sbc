# SBC log retention & SIP capture (Phase 3)

**Status:** Shipped on branch **`logs`** (2026-07-17) — install on host with **`scripts/install-log-retention.sh`**.  
**Spec:** **`pbx3/pbx3-directory/docs/FLEET_LOG_RETENTION_REQUIREMENTS.md`**.

## What it does

| Stream | Local | S3 |
|--------|-------|-----|
| OpenSIPS text | logrotate 7d (`pbx3sbc-opensips`) | `sbc/{id}/logs/opensips/…` (30d tag) |
| syslog | system rsyslog | `sbc/{id}/logs/syslog/…` |
| SIP pcap (no RTP) | systemd **`pbx3sbc-sip-pcap`** dumpcap ring | `sbc/{id}/logs/sip-pcap/…` |

## Install (on SBC)

```bash
cd /path/to/pbx3sbc   # or git pull logs
sudo ./scripts/install-log-retention.sh
sudoedit /etc/pbx3sbc/log-ship.env   # PBX3_ORG_BUCKET, PBX3_SBC_ID=sbc
```

IAM: apply **`pbx3-directory/schema/pbx3-sbc-s3-writer.policy.json.tmpl`** (replace `__BUCKET__`, `__SBC_ID__`) to an instance role or user used by the SBC.

```bash
systemctl status pbx3sbc-sip-pcap
sudo /usr/local/bin/pbx3sbc-ship-logs-to-s3 --dry-run
sudo /usr/local/bin/pbx3sbc-ship-logs-to-s3 --limit=5
```

Lifecycle (ops Mac): re-run **`apply-logs-lifecycle-rules.sh`** so `sbc/` prefixes with the same `class` tags expire (script filters `instances/` today — extend or add parallel rules for `sbc/` if needed).

## Solo vs fleet

SBC is always the fleet SIP edge. Instance `sys-ua-siplog` stays **off** in fleet (`siplog-set-mode.sh fleet`).
