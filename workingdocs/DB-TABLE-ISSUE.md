# Database Table Creation Issue

## Problem
During initial test install, only 4 tables were created in the OpenSIPS database instead of the expected tables (version, acc, missed_calls, dispatcher, domain, endpoint_locations).

## Root Cause
**OpenSIPS uses modular schema files** - each module has its own create script:
- `standard-create.sql` - Only creates the `version` table (schema version tracking)
- `acc-create.sql` - Creates `acc` and `missed_calls` tables (accounting/CDR)
- `dispatcher-create.sql` - Creates `dispatcher` table
- `domain-create.sql` - Creates `domain` table
- Other modules have their own `*-create.sql` files

The script was only loading `standard-create.sql` and expecting it to create all tables.

## Solution
Updated `scripts/init-database.sh` to:
1. Load `acc-create.sql` explicitly for accounting tables
2. Check for file existence before loading (warn instead of fail)
3. Show available schema files if some are missing
4. Display table count and list after loading all schemas

## Required Schema Files

The following schema files should be present in `/usr/share/opensips/mysql/`:
- `standard-create.sql` - Version table (always present)
- `acc-create.sql` - Accounting tables (if `acc` module is installed)
- `dispatcher-create.sql` - Dispatcher table (if `dispatcher` module is installed)
- `domain-create.sql` - Domain table (if `domain` module is installed)

**Note:** If `acc-create.sql` is missing, you may need to install `opensips-mysql-module` package.

## Expected Tables After Full Load

After loading all required schema files, you should have:
- `version` - Schema version tracking (from standard-create.sql)
- `acc` - Accounting/CDR records (from acc-create.sql)
- `missed_calls` - Missed call logging (from acc-create.sql)
- `dispatcher` - Dispatcher table (from dispatcher-create.sql)
- `domain` - Domain table (from domain-create.sql)
- `endpoint_locations` - Custom endpoint tracking (created by init-database.sh)

## Diagnostic Steps

The updated `init-database.sh` script now:
1. Checks for file existence before loading each schema
2. Shows warnings if schema files are missing (instead of failing)
3. Lists available schema files if some are missing
4. Displays table count and list after loading all schemas
5. Shows final table count at end

## Verification

After running `init-database.sh`, verify tables were created:
```bash
mysql -u opensips -p opensips -e "SHOW TABLES;"
mysql -u opensips -p opensips -e "DESCRIBE acc;"
mysql -u opensips -p opensips -e "DESCRIBE missed_calls;"
```

## Python Warning (Non-Critical)

The Python warning from opensips-cli:
```
/usr/lib/python3/dist-packages/opensipscli/modules/mi.py:87: SyntaxWarning: invalid escape sequence '\.'
```

This is a known issue in the `opensips-cli` package (not our code). It's a warning, not an error, and doesn't affect functionality. Can be safely ignored.
