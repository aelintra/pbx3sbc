# MySQL Migration Notes

**Date:** January 2026  
**Status:** Scripts need updating for MySQL (currently SQLite-based)

## Overview

All scripts are currently SQLite-based but we're using MySQL from the start. These scripts need to be updated after MySQL is set up.

## Scripts Needing Updates

### 1. `scripts/init-database.sh`
**Current:** Uses SQLite (`sqlite3`, `.db` file)  
**Needs:** MySQL version that:
- Uses `mysql` command instead of `sqlite3`
- Loads schema files from `/usr/share/opensips/mysql/`
- Requires MySQL credentials (user, password, database name)
- Creates `endpoint_locations` table with MySQL syntax

**Required Schema Files:**
- `/usr/share/opensips/mysql/standard-create.sql` (core tables including `version`)
- `/usr/share/opensips/mysql/dispatcher-create.sql` (dispatcher table)
- `/usr/share/opensips/mysql/domain-create.sql` (domain table)

### 2. `scripts/add-domain.sh`
**Current:** Uses `sqlite3` with `last_insert_rowid()`  
**Needs:** MySQL version using:
- `mysql` command
- `LAST_INSERT_ID()` function
- MySQL connection parameters

### 3. `scripts/view-status.sh`
**Current:** Uses `sqlite3` with SQLite-specific commands  
**Needs:** MySQL version using:
- `mysql` command
- Remove SQLite-specific checks (PRAGMA integrity_check)
- MySQL syntax for queries

### 4. `scripts/add-dispatcher.sh`
**Current:** Likely uses SQLite  
**Needs:** Check and update for MySQL

### 5. `install.sh`
**Current:** References SQLite database initialization  
**Needs:** Update `initialize_database()` function to use MySQL

## MySQL Schema Files Location

After installing OpenSIPS packages:
- Location: `/usr/share/opensips/mysql/`
- Key files:
  - `standard-create.sql` - Core schema (version table, etc.)
  - `dispatcher-create.sql` - Dispatcher table
  - `domain-create.sql` - Domain table
  - Other module schemas as needed

## Database Configuration

**Database:** `opensips`  
**User:** `opensips`  
**Password:** `rigmarole` (stored in config files)

## Next Steps After Fresh Install

1. Install OpenSIPS packages (schema files will be available)
2. Set up MySQL database and user
3. Update scripts to use MySQL
4. Test database initialization
5. Verify all scripts work with MySQL

## Alternative: Use opensips-cli

The `opensips-cli -x database create` command can initialize the database, but it may require interactive password entry. Scripts provide more control over the process.

