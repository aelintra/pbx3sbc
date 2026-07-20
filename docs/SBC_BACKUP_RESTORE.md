# SBC backup & restore

**Spec:** [`pbx3/pbx3-directory/docs/SBC_BACKUP_RESTORE_REQUIREMENTS.md`](../../pbx3/pbx3-directory/docs/SBC_BACKUP_RESTORE_REQUIREMENTS.md) (path from monorepo)  
**Operator MkDocs:** `pbx3-docs` → Fleet → SBC backup and restore  
**Engine:** MariaDB (`opensips` DB). Litestream / SQLite — parked.

## What is NOT in the backup zip

These must be re-established on a new host (installers / ops), not restored from S3:

| Missing from zip | How to get it back |
|------------------|--------------------|
| OpenSIPS / MariaDB / nginx packages | `sudo ./install.sh` + admin `./install.sh` |
| `/etc/sudoers.d/pbx3sbc-admin` | `sudo ./scripts/setup-admin-panel-sudoers.sh` — **required for Fail2ban Log/Status** |
| Let’s Encrypt certs | certbot (or HTTP/self-signed on LAN) |
| Host identity (`advertised_address`, LAN IP) | Edit `opensips.cfg` after restore |
| MariaDB OS user password vs dump | Align with restored `.mysql_credentials` |

## Create local backup

```bash
sudo /home/ubuntu/pbx3sbc/scripts/backup-sbc.sh --trigger manual
# → /var/lib/pbx3sbc/bkup/sbcbak.{epoch}.zip
sudo /home/ubuntu/pbx3sbc/scripts/backup-sbc.sh --dry-run
```

Zip includes `opensips.sql` (soft-state tables ignored), `/etc/opensips/opensips.cfg`, credentials if present, and pbx3sbc-admin `.env`. Local FIFO keeps **9** zips.

## Upload to org S3

Needs `/etc/pbx3sbc/log-ship.env` (`PBX3_ORG_BUCKET`, `PBX3_SBC_ID`) and IAM for `sbc/{id}/*` (same as log ship).

```bash
sudo /home/ubuntu/pbx3sbc/scripts/backup-sbc.sh --trigger manual --upload
```

Keys: `s3://{bucket}/sbc/{id}/backups/{stamp}/backup.zip` + `manifest.json` (tag `class=backup`).

## Fetch from S3 (ops laptop or scratch host)

```bash
export PBX3_ORG_BUCKET=08jzwn-pbx3
# from pbx3 clone:
./pbx3-directory/tools/fetch-latest-sbc-backup.sh --sbc-id sbc --output-dir /tmp
# → /tmp/sbcbak.{epoch}.zip
```

## Restore (this host)

```bash
# Preview
sudo ./scripts/restore-sbc-backup.sh --dry-run /path/to/sbcbak.EPOCH.zip

# Side-DB integrity (safe on live lab — does not touch opensips or FS)
sudo ./scripts/restore-sbc-backup.sh --target-db opensips_restore_test --yes /path/to/sbcbak.EPOCH.zip
sudo mysql -e 'DROP DATABASE opensips_restore_test;'   # cleanup

# Live / scratch full restore (REPLACES opensips DB + selective FS)
sudo ./scripts/restore-sbc-backup.sh --full --yes --restart /path/to/sbcbak.EPOCH.zip
```

**Never** run `init-database.sh` after a successful restore.

## Scratch restore drill

Goal: blank host → regular installers → restore from S3 backup → Filament (+ optional SIP) smoke.

**Valid hosts (pick one):**

| Host | Good for |
|------|----------|
| **Local / other host `x86_64` Ubuntu 24.04** | Preferred for OpenSIPS apt packages — lab SBC is **amd64** (`apt.opensips.org` has no noble **arm64** Packages). Parallels Intel guest (emulated on Apple Silicon) or a spare AMD box both work. |
| **Local ARM64 VM** | Good for non-OpenSIPS experiments only until arm64 packages exist; **not** for full SBC install from apt today. |
| **Scratch EC2** | Use **x86_64** (e.g. `t3.*`) to match lab SBC, not `t4g.*`, unless you build OpenSIPS from source. |

### Local ARM64 VM

OpenSIPS apt on noble is **amd64-only** today — use an **x86_64** host for full install (see table above). ARM64 guests are fine for non-OpenSIPS experiments only.

### Cloud or local — same install/restore steps

1. **Snapshot source:** `aws s3 ls s3://08jzwn-pbx3/sbc/sbc/backups/` (lab stamp e.g. `20260720T172044Z`).
2. **Install with the regular SBC installer** — clone `pbx3sbc`, `sudo ./install.sh` (creates empty `opensips` DB + template cfg). Then clone **pbx3sbc-admin**, `./install.sh`. Empty DB is fine; restore replaces it.  
   Do **not** hand-seed domains/peers before restore. Prefer **`--skip-migrations`** on admin if you will restore immediately (avoids “table already exists” noise).
3. **Fetch** backup onto the box (or scp from laptop):  
   `fetch-latest-sbc-backup.sh --sbc-id sbc --output-dir /var/lib/pbx3sbc/bkup`
4. **Restore:**  
   `sudo PBX3SBC_ADMIN_ENV=$HOME/pbx3sbc-admin/.env ./scripts/restore-sbc-backup.sh --full --yes --restart …/sbcbak.*.zip`  
   Do **not** re-init the DB afterward.
5. **Post-restore host alignment** (when scratch ≠ lab identity):  
   - Set MariaDB `opensips` password to match restored `/etc/opensips/.mysql_credentials`.  
   - Set `advertised_address` in `/etc/opensips/opensips.cfg` to this host.  
   - `chmod 755` home + app so `www-data` can read `.env`; record migrations if tables already exist.  
   - Optional: `APP_URL=http://<scratch-ip>`.  
   - **Fail2ban / log panels:** run `sudo ./scripts/setup-admin-panel-sudoers.sh` from the `pbx3sbc` tree (passwordless sudo for `www-data` — not in the backup zip).
6. **Smoke:** open `http://<ip>/admin/login`; spot-check Peers / domains in Filament; SIP optional.
7. **Tear down** when done.

### First scratch drill (2026-07-20)

- Host: **amd64** Ubuntu 24.04 @ `192.168.1.55` (`sbctest1`).  
- Backup: `20260720T172044Z` / `sbcbak.1784568044.zip`.  
- Restored counts: **users=1 domain=5 dr_gateways=13** (matched lab).  
- OpenSIPS **active** after DB password + `advertised_address=192.168.1.55`.  
- Filament **Login** page **HTTP 200** at `http://192.168.1.55/admin/login` (user `admin@example.com` — reset password if lab hash unknown).

## Cron (backup)

```bash
sudo cp scripts/cron.d/pbx3sbc-backup.example /etc/cron.d/pbx3sbc-backup
sudo chmod 644 /etc/cron.d/pbx3sbc-backup
```
