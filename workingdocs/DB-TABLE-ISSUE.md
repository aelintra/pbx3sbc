# Database Table Creation Issue

## Problem
Only 4 tables are being created in the MySQL `opensips` database, but `standard-create.sql` should create 20+ tables.

## Expected Tables from standard-create.sql
Based on OpenSIPS 3.6 documentation and SQLite dump reference:
- `version` - Schema version tracking
- `acc` - Accounting/CDR
- `missed_calls` - Missed call logging
- `dbaliases` - Database aliases
- `subscriber` - Subscriber management
- `uri` - URI table
- `clusterer` - Clustering
- `dialog` - Dialog tracking
- `dialplan` - Dialplan
- `dispatcher` - Dispatcher (from dispatcher-create.sql)
- `domain` - Domain (from domain-create.sql)
- `dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `dr_partitions` - Dialplan routing
- `grp`, `re_grp` - Groups
- `load_balancer` - Load balancer
- `silo` - Silo
- `address` - Address table
- `rtpproxy_sockets` - RTP proxy
- `rtpengine` - RTP engine
- `speed_dial` - Speed dial
- `tls_mgm` - TLS management
- `location` - Location (usrloc)

Plus custom table:
- `endpoint_locations` - Custom endpoint tracking

## Diagnostic Steps Added

The updated `init-database.sh` script now:
1. Checks `standard-create.sql` file size before loading
2. Displays total table count after loading standard-create.sql
3. Lists all tables created
4. Shows final table count at end

## Possible Causes

1. **Empty/Minimal standard-create.sql**
   - The OpenSIPS package may have a minimal schema file
   - Check: `ls -lh /usr/share/opensips/mysql/standard-create.sql`
   - Check: `head -50 /usr/share/opensips/mysql/standard-create.sql`

2. **Schema Loading Errors**
   - MySQL errors may be silently ignored
   - Check MySQL error log
   - Run manually: `mysql -u opensips -p opensips < /usr/share/opensips/mysql/standard-create.sql`

3. **Wrong Schema File**
   - Verify the correct file is being loaded
   - Check: `ls -la /usr/share/opensips/mysql/`

4. **Database Already Initialized**
   - If database was partially initialized, tables might not be recreated
   - Check: `mysql -u opensips -p opensips -e "SHOW TABLES;"`

## Next Steps

1. Run `init-database.sh` with the new diagnostics
2. Check the output for:
   - File size warning
   - Table count after standard-create.sql
   - List of tables created
3. If only 4 tables, manually check:
   ```bash
   # Check schema file
   ls -lh /usr/share/opensips/mysql/standard-create.sql
   head -100 /usr/share/opensips/mysql/standard-create.sql
   
   # Check current tables
   mysql -u opensips -p opensips -e "SHOW TABLES;"
   
   # Try manual load
   mysql -u opensips -p opensips < /usr/share/opensips/mysql/standard-create.sql
   ```

## Python Warning (Non-Critical)

The Python warning from opensips-cli:
```
/usr/lib/python3/dist-packages/opensipscli/modules/mi.py:87: SyntaxWarning: invalid escape sequence '\.'
```

This is a known issue in the `opensips-cli` package (not our code). It's a warning, not an error, and doesn't affect functionality. Can be safely ignored.
