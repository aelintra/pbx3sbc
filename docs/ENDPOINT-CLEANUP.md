# Endpoint Location Cleanup

**⚠️ NOTE:** This document references the old `endpoint_locations` table. The current system uses OpenSIPS `location` table (usrloc module) which handles expiration automatically. This cleanup script may still be needed for legacy installations or can be updated to work with the `location` table.

## Overview

The `endpoint_locations` table (old implementation) stored endpoint registration information (IP, port, expiration time). While expired entries are automatically filtered out of queries using `expires > NOW()`, they remain in the database until explicitly deleted.

**Current System:** Uses OpenSIPS `location` table (usrloc module) which handles expiration automatically via `timer_interval` parameter.

The cleanup script removes expired endpoint location records to:
- Reduce database size
- Improve query performance
- Keep the database clean

## Manual Cleanup

### Run Cleanup Script

```bash
# Run cleanup (requires sudo)
sudo scripts/cleanup-expired-endpoints.sh

# Dry run (see what would be deleted without deleting)
sudo scripts/cleanup-expired-endpoints.sh --dry-run

# Verbose output (show details)
sudo scripts/cleanup-expired-endpoints.sh --verbose
```

### Set Database Credentials

The script uses environment variables for database credentials:

```bash
export DB_NAME=opensips
export DB_USER=opensips
export DB_PASS=your-password
sudo -E scripts/cleanup-expired-endpoints.sh
```

Or use the credentials file:

```bash
# If using /etc/opensips/.mysql_credentials
source /etc/opensips/.mysql_credentials
sudo -E scripts/cleanup-expired-endpoints.sh
```

## Automated Cleanup

### Option 1: Systemd Timer (Recommended)

1. **Copy script to system location:**
   ```bash
   sudo cp scripts/cleanup-expired-endpoints.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/cleanup-expired-endpoints.sh
   ```

2. **Edit service file with your database credentials:**
   ```bash
   sudo nano scripts/cleanup-expired-endpoints.service
   # Update DB_PASS environment variable
   ```

3. **Install service and timer:**
   ```bash
   sudo cp scripts/cleanup-expired-endpoints.service /etc/systemd/system/
   sudo cp scripts/cleanup-expired-endpoints.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable cleanup-expired-endpoints.timer
   sudo systemctl start cleanup-expired-endpoints.timer
   ```

4. **Check timer status:**
   ```bash
   sudo systemctl status cleanup-expired-endpoints.timer
   sudo systemctl list-timers cleanup-expired-endpoints.timer
   ```

5. **Run manually to test:**
   ```bash
   sudo systemctl start cleanup-expired-endpoints.service
   sudo journalctl -u cleanup-expired-endpoints.service
   ```

**Timer Schedule:** Runs daily at 2:00 AM (configurable in `.timer` file)

### Option 2: Cron Job

Add to crontab:

```bash
sudo crontab -e
```

Add line (runs daily at 2:00 AM):

```cron
0 2 * * * /path/to/scripts/cleanup-expired-endpoints.sh >> /var/log/opensips-cleanup.log 2>&1
```

Or if using credentials file:

```cron
0 2 * * * source /etc/opensips/.mysql_credentials && /path/to/scripts/cleanup-expired-endpoints.sh >> /var/log/opensips-cleanup.log 2>&1
```

## How It Works

The cleanup script:

1. **Checks for expired entries:**
   ```sql
   SELECT COUNT(*) FROM endpoint_locations WHERE expires < NOW();
   ```

2. **Shows expired entries** (if `--verbose` or `--dry-run`):
   ```sql
   SELECT aor, contact_ip, contact_port, expires, 
          TIMESTAMPDIFF(SECOND, expires, NOW()) as expired_seconds_ago
   FROM endpoint_locations 
   WHERE expires < NOW()
   ORDER BY expires DESC;
   ```

3. **Deletes expired entries:**
   ```sql
   DELETE FROM endpoint_locations WHERE expires < NOW();
   ```

## Safety Features

- **Dry run mode:** Test without deleting (`--dry-run`)
- **Table existence check:** Verifies table exists before running
- **Error handling:** Exits gracefully on errors
- **Verbose logging:** Shows what's being deleted

## Monitoring

### Check Expired Entries Count

```sql
SELECT COUNT(*) as expired_count 
FROM endpoint_locations 
WHERE expires < NOW();
```

### Check Active Entries Count

```sql
SELECT COUNT(*) as active_count 
FROM endpoint_locations 
WHERE expires > NOW();
```

### View All Entries (Active and Expired)

```sql
SELECT 
    aor,
    contact_ip,
    contact_port,
    expires,
    CASE 
        WHEN expires < NOW() THEN 'EXPIRED'
        ELSE 'ACTIVE'
    END as status,
    TIMESTAMPDIFF(SECOND, NOW(), expires) as seconds_until_expiry
FROM endpoint_locations
ORDER BY expires DESC;
```

## Troubleshooting

### Script Fails with "Table does not exist"

**Solution:** Run `init-database.sh` to create the table:
```bash
sudo scripts/init-database.sh
```

### Script Fails with "Access denied"

**Solution:** Check database credentials:
```bash
# Test connection
sudo scripts/test-mysql-connection.sh

# Or manually
mysql -u opensips -p'your-password' opensips -e "SELECT 1;"
```

### No Expired Entries Found

This is normal if:
- All endpoints are actively registered
- Cleanup was recently run
- Endpoints re-register before expiration

### Timer Not Running

**Check timer status:**
```bash
sudo systemctl status cleanup-expired-endpoints.timer
```

**Check last run:**
```bash
sudo journalctl -u cleanup-expired-endpoints.service
```

**Manually trigger:**
```bash
sudo systemctl start cleanup-expired-endpoints.service
```

## Related Documentation

- [Database Initialization](../scripts/init-database.sh)
- [MySQL Port Opening Procedure](MYSQL-PORT-OPENING-PROCEDURE.md)
- [OpenSIPS Routing Logic](opensips-routing-logic.md)
