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
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060 0 0
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060 0 0
```

### 3. Verify Everything Works

```bash
# Check status
sudo ./scripts/view-status.sh

# Check logs
sudo journalctl -u kamailio -f
sudo journalctl -u litestream -f
```

## Common Tasks

### View Database Contents

```bash
sudo sqlite3 /var/lib/kamailio/routing.d
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
sudo systemctl restart kamailio
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
# Edit Kamailio config
sudo nano /etc/kamailio/kamailio.cfg

# Edit Litestream config
sudo nano /etc/litestream.yml

# Restart services after changes
sudo systemctl restart kamailio
sudo systemctl restart litestream
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
sudo journalctl -u kamailio -n 50
sudo journalctl -u litestream -n 50

# Check configuration syntax
sudo kamailio -c -f /etc/kamailio/kamailio.cfg
```

### Database Issues

```bash
# Check integrity
sudo sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"

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

- **Kamailio Config**: `/etc/kamailio/kamailio.cfg`
- **Litestream Config**: `/etc/litestream.yml`
- **Database**: `/var/lib/kamailio/routing.db`
- **Logs**: `journalctl -u kamailio` and `journalctl -u litestream`

## Next Steps

1. Add your domains and dispatcher entries
2. Configure monitoring and alerts
3. Set up backup verification procedures
4. Review security settings
5. Test failover scenarios

For detailed information, see [03-Install_notes.md](03-Install_notes.md) and [01-overview.md](01-overview.md).
