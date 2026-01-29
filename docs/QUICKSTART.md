# Quick Start Guide

## Installation

```bash
# Clone the repository
git clone https://github.com/aelintra/pbx3sbc.git
cd pbx3sbc

# Run installer
sudo ./install.sh
```

The installer will prompt you for:
- S3/MinIO configuration (bucket name, credentials, etc.)
- Firewall setup
- Database initialization

## Post-Installation Setup

### 1. Add Your First Domain

```bash
sudo ./scripts/add-domain.sh yourdomain.com 10 1 "Your tenant"
```

### 2. Add Asterisk Backends

```bash
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060
```

Note: The dispatcher script now uses the OpenSIPS 3.6 schema. Optional parameters include priority, weight, socket, and description.

### 3. Verify Everything Works

```bash
# Check status
sudo ./scripts/view-status.sh

# Check logs
sudo journalctl -u opensips -f
sudo journalctl -u litestream -f
```

## Common Tasks

### View Database Contents

```bash
sudo sqlite3 /var/lib/opensips/routing.db
```

```sql
-- List all domains
SELECT * FROM sip_domains;

-- List all dispatcher entries
SELECT * FROM dispatcher;

-- Check replication status
.exit
sudo litestream databases
```

### Restart Services

```bash
sudo systemctl restart opensips
sudo systemctl restart litestream
```

### Restore Database from Backup

```bash
# Restore to latest
sudo ./scripts/restore-database.sh

# Restore to specific time
sudo ./scripts/restore-database.sh "2024-01-15T10:30:00Z"
```

### Update Configuration

```bash
# Edit OpenSIPS config
sudo nano /etc/opensips/opensips.cfg

# Edit Litestream config
sudo nano /etc/litestream.yml

# Restart services after changes
sudo systemctl restart opensips
sudo systemctl restart litestream
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
sudo journalctl -u opensips -n 50
sudo journalctl -u litestream -n 50

# Check configuration syntax
sudo opensips -C -f /etc/opensips/opensips.cfg
```

### Database Issues

```bash
# Check integrity
sudo sqlite3 /var/lib/opensips/routing.db "PRAGMA integrity_check;"

# Reinitialize database (WARNING: deletes data)
sudo ./scripts/init-database.sh
```

### Replication Not Working

```bash
# Check Litestream status
sudo litestream databases

# Verify S3/MinIO connectivity
# Check credentials in /etc/litestream.yml
sudo cat /etc/litestream.yml
```

## File Locations

- **OpenSIPS Config**: `/etc/opensips/opensips.cfg`
- **Litestream Config**: `/etc/litestream.yml`
- **Database**: `/var/lib/opensips/routing.db`
- **Logs**: `journalctl -u opensips` and `journalctl -u litestream`

## Next Steps

1. Add your domains and dispatcher entries
2. Configure monitoring and alerts
3. Set up backup verification procedures
4. Review security settings
5. Test failover scenarios

For detailed information, see [INSTALLATION.md](INSTALLATION.md).
