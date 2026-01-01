# OpenSIPS Configuration Guide

This document provides guidance for using the OpenSIPS configuration that replicates the Kamailio SBC functionality while addressing the INVITE transaction handling issues.

## Overview

The OpenSIPS configuration (`config/opensips.cfg.template`) has been created to replicate all functionality from the Kamailio implementation, with the goal of resolving the INVITE transaction handling issues encountered with Kamailio (see `TROUBLESHOOTING-OPTIONS-ROUTING.md`).

## Key Differences from Kamailio

### 1. Pseudo-Variables

OpenSIPS uses slightly different pseudo-variable syntax:

| Purpose | Kamailio | OpenSIPS |
|---------|----------|----------|
| To header username | `$(tu{uri.user})` | `$tU` |
| To header domain | `$td` | `$tD` |
| Request-URI username | `$(ru{uri.user})` | `$rU` |
| Request-URI domain | `$rd` | `$rD` |
| Full To URI | `$tu` | `$tu` |
| Full Request-URI | `$ru` | `$ru` |

### 2. Module Names

Most module names are the same, but some may differ:
- SQL operations: `sqlops` (Kamailio) vs `sql` (OpenSIPS)
- Database modules: Both use `db_sqlite`

### 3. Transaction Handling

OpenSIPS transaction module (`tm`) may handle INVITE transactions differently than Kamailio, which is why we're switching. The configuration uses the same timer settings, but OpenSIPS may process provisional responses (like 100 Trying) more reliably.

### 4. Event Routes

Dispatcher event route names may vary by OpenSIPS version:
- `dispatcher:dst-up` / `dispatcher:dst-down` (common)
- `E_DISPATCHER_DST_UP` / `E_DISPATCHER_DST_DOWN` (some versions)

Check your OpenSIPS version's documentation for the correct event names.

## Installation Steps

### 1. Install OpenSIPS

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y opensips opensips-sqlite-modules

# Or compile from source if needed
```

### 2. Create OpenSIPS User and Directories

```bash
sudo useradd -r -s /bin/false -d /var/run/opensips -c "OpenSIPS SIP Server" opensips
sudo mkdir -p /var/lib/opensips
sudo mkdir -p /var/log/opensips
sudo mkdir -p /var/run/opensips
sudo chown opensips:opensips /var/lib/opensips /var/log/opensips /var/run/opensips
```

### 3. Copy Configuration

```bash
# Copy the template to the OpenSIPS config directory
sudo cp config/opensips.cfg.template /etc/opensips/opensips.cfg

# Update the advertised_address in the config file
sudo sed -i 's/advertised_address="198.51.100.1"/advertised_address="YOUR_IP_ADDRESS"/' /etc/opensips/opensips.cfg
```

### 4. Initialize Database

The same database schema works for OpenSIPS. Use the existing `scripts/init-database.sh` script, but update the paths:

```bash
# Update DB_PATH in the script or set it manually
export DB_PATH=/var/lib/opensips/routing.db
sudo -u opensips sqlite3 $DB_PATH < scripts/init-database.sh
```

Or manually run the SQL from `scripts/init-database.sh`, updating paths as needed.

### 5. Set Database Permissions

```bash
sudo chown opensips:opensips /var/lib/opensips/routing.db
sudo chmod 644 /var/lib/opensips/routing.db
```

### 6. Test Configuration

```bash
# Check syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# If syntax is OK, start OpenSIPS
sudo systemctl start opensips
sudo systemctl enable opensips
```

## Configuration Customization

### Update Advertised Address

Edit `/etc/opensips/opensips.cfg` and set the correct IP address:

```
advertised_address="YOUR_SERVER_IP"
```

### Database Path

If your database is in a different location, update the SQLite connection strings:

```
modparam("sql", "sqlcon", "cb=>sqlite:///path/to/routing.db")
modparam("dispatcher", "db_url", "sqlite:///path/to/routing.db")
```

## Testing

After installation, test the following scenarios (same as Kamailio testing):

1. **Endpoint Registration**
   - Register a SIP endpoint
   - Verify endpoint location is stored in `endpoint_locations` table
   - Check logs for successful tracking

2. **OPTIONS from Asterisk**
   - Send OPTIONS from Asterisk backend to registered endpoint
   - Verify routing to endpoint IP:port
   - Check logs for routing decisions

3. **INVITE Transactions**
   - Send INVITE from endpoint to Asterisk
   - **Key Test:** Verify 100 Trying from Asterisk is forwarded to endpoint
   - **Key Test:** Verify transaction does NOT timeout prematurely (no 408 in ~26ms)
   - Verify call completes successfully

4. **Domain Validation**
   - Try request to unknown domain - should be blocked
   - Try request to disabled domain - should be blocked

5. **In-Dialog Requests**
   - Complete a call
   - Send BYE - should route correctly via Record-Route

## Monitoring

### View Logs

```bash
# OpenSIPS logs
sudo tail -f /var/log/opensips/opensips.log

# Or via journalctl if using systemd
sudo journalctl -u opensips -f
```

### Check Database

```bash
# View endpoint locations
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM endpoint_locations;"

# View dispatcher destinations
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM dispatcher;"

# View domains
sqlite3 /var/lib/opensips/routing.db "SELECT * FROM sip_domains;"
```

## Troubleshooting

### Configuration Syntax Errors

```bash
# Check syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Common issues:
# - Module not found: Install missing modules
# - Pseudo-variable errors: Check syntax against OpenSIPS documentation
# - SQL errors: Verify database path and permissions
```

### Transaction Issues

If you still encounter INVITE transaction issues:

1. **Check Timer Settings**
   - Verify `fr_inv_timer` is set appropriately (30 seconds)
   - Verify `restart_fr_on_each_reply` is enabled

2. **Review Logs**
   - Look for 408 errors and their timing
   - Check if 100 Trying is being received from Asterisk
   - Verify transaction state in logs

3. **Compare with Kamailio Behavior**
   - If OpenSIPS shows the same issue, it may be a network or Asterisk configuration problem
   - If OpenSIPS works correctly, the issue was Kamailio-specific

### SQL Query Issues

If database queries fail:

1. **Verify Database Path**
   ```bash
   ls -la /var/lib/opensips/routing.db
   ```

2. **Check Permissions**
   ```bash
   sudo chown opensips:opensips /var/lib/opensips/routing.db
   ```

3. **Test SQL Connection**
   ```bash
   sudo -u opensips sqlite3 /var/lib/opensips/routing.db "SELECT 1;"
   ```

## Key Improvements Expected

The main reason for switching to OpenSIPS is to resolve the INVITE transaction handling issue. Expected improvements:

1. **Proper 100 Trying Forwarding**
   - OpenSIPS should forward 100 Trying from Asterisk to endpoints
   - No premature 408 Request Timeout

2. **Transaction State Management**
   - Better handling of provisional responses
   - Proper transaction lifecycle management

3. **Response Correlation**
   - Correct matching of responses to requests
   - Proper transaction state tracking

## Migration from Kamailio

If you're currently running Kamailio:

1. **Backup Current Setup**
   ```bash
   sudo cp /etc/kamailio/kamailio.cfg /etc/kamailio/kamailio.cfg.backup
   sudo cp /var/lib/kamailio/routing.db /var/lib/kamailio/routing.db.backup
   ```

2. **Stop Kamailio**
   ```bash
   sudo systemctl stop kamailio
   ```

3. **Copy Database**
   ```bash
   sudo cp /var/lib/kamailio/routing.db /var/lib/opensips/routing.db
   sudo chown opensips:opensips /var/lib/opensips/routing.db
   ```

4. **Install and Configure OpenSIPS** (follow steps above)

5. **Test Thoroughly** before switching production traffic

6. **Monitor Closely** for the first few hours/days

## Additional Resources

- OpenSIPS Documentation: https://www.opensips.org/Documentation
- OpenSIPS Transaction Module: https://www.opensips.org/docs/modules/3.1.x/tm.html
- OpenSIPS Dispatcher Module: https://www.opensips.org/docs/modules/3.1.x/dispatcher.html

## Support

If you encounter issues:

1. Check OpenSIPS logs for errors
2. Verify configuration syntax
3. Review `REQUIREMENTS-FOR-OPENSIPS.md` for functional requirements
4. Review `TROUBLESHOOTING-OPTIONS-ROUTING.md` for known issues and solutions
5. Consult OpenSIPS community forums or documentation

