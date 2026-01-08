# Session Summary - Database Schema Enhancement

## Date
2025-01-07

## Overview
Enhanced the OpenSIPS routing database schema by adding an explicit `setid` column to the `domain` table, and updated the installer to accept database passwords as parameters.

## Key Decisions

### 1. Domain Table Schema Enhancement
**Decision:** Added explicit `setid` column to `domain` table instead of using `domain.id` as the dispatcher set ID.

**Rationale:**
- IDs are surrogate keys and should be allowed to change
- Explicit setid provides flexibility and decouples domain identity from routing
- Better alignment with best practices (explicit over implicit)
- Easier to understand and maintain

**Implementation:**
- Added `setid INT NOT NULL DEFAULT 0` column to domain table
- Created index on `setid` for performance
- Migrated existing data: `setid = id` for existing domains
- Updated OpenSIPS config to use `SELECT setid FROM domain` instead of `SELECT id`

### 2. Database Password Handling
**Decision:** Added `--db-password` parameter to installer and sanitized repository.

**Rationale:**
- Avoids hardcoded passwords in repository
- Allows non-interactive installations
- Improves security posture

## Changes Made

### Database Schema
- **File:** MySQL database `opensips`, table `domain`
- Added `setid` column with index
- Migrated existing data (setid = id)

**SQL Changes:**
```sql
ALTER TABLE domain ADD COLUMN setid INT NOT NULL DEFAULT 0;
UPDATE domain SET setid = id WHERE setid = 0;
CREATE INDEX idx_domain_setid ON domain(setid);
```

### OpenSIPS Configuration
- **File:** `config/opensips.cfg.template`
- Updated domain lookup query from `SELECT id` to `SELECT setid`
- Changed from: `SELECT id FROM domain WHERE domain='...'`
- Changed to: `SELECT setid FROM domain WHERE domain='...'`

### Scripts

#### `scripts/add-domain.sh`
- Updated for MySQL (previously SQLite)
- Supports optional `setid` parameter: `./add-domain.sh <domain> [setid]`
- Defaults setid to auto-generated ID if not provided
- Uses MySQL syntax and commands

#### `scripts/init-database.sh`
- Automatically adds `setid` column when initializing new databases
- Includes migration logic: `UPDATE domain SET setid = id WHERE setid = 0`
- Creates index on setid column

### Control Panel (OpenSIPS Control Panel)
Modified the existing control panel domain tool to support setid:

- **File:** `/var/www/opensips-cp/web/tools/system/domains/domains.php`
  - INSERT query includes setid field
  - UPDATE query includes setid field
  - SELECT query includes setid for edit form population

- **File:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.form.php`
  - Added "Set ID" input field to add/edit forms
  - Includes validation regex for numeric input

- **File:** `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`
  - Added "ID" and "Set ID" columns to domain list view
  - Updated colspan for empty state message

**Note:** These are modifications to the upstream control panel. Consider building a new admin panel in the future (see ADMIN-PANEL-DESIGN.md).

### Installer
- **File:** `install.sh`
- Added `--db-password <PASSWORD>` command-line parameter
- Added interactive password prompt if not provided via parameter
- Password is collected early (before config creation)
- Password is used in:
  - MySQL database user creation
  - OpenSIPS config template replacement (replaces 'your-password')
  - Database verification
  - Next steps output

**Usage:**
```bash
# With password as parameter (non-interactive)
sudo ./install.sh --db-password 'mypassword'

# Without parameter (interactive - will prompt)
sudo ./install.sh
```

### Security Improvements
- **All repository files:**
  - Replaced all occurrences of hardcoded password 'rigmarole' with placeholder 'your-password'
  - This sanitizes the repository for version control
  - Password should be provided via installer parameter or prompt

**Files sanitized:**
- `config/opensips.cfg.template`
- `scripts/add-domain.sh`
- `scripts/init-database.sh`
- `install.sh`
- `OPENSIPS-CONTROL-PANEL-INSTALLATION.md`
- `MANUAL-INSTALL-STEPS.md`
- `MYSQL-MIGRATION-NOTES.md`

## Files Modified

### Repository Files
- `config/opensips.cfg.template`
- `scripts/add-domain.sh`
- `scripts/init-database.sh`
- `install.sh`
- `OPENSIPS-CONTROL-PANEL-INSTALLATION.md`
- `MANUAL-INSTALL-STEPS.md`
- `MYSQL-MIGRATION-NOTES.md`
- `ADMIN-PANEL-DESIGN.md` (created/updated with setid decision)

### System Files (Control Panel - Not in Repository)
- `/var/www/opensips-cp/web/tools/system/domains/domains.php`
- `/var/www/opensips-cp/web/tools/system/domains/template/domains.form.php`
- `/var/www/opensips-cp/web/tools/system/domains/template/domains.main.php`

**Note:** Control panel files are on the server, not in the repository. These modifications need to be documented or scripted for future installations.

## Testing Status

- ✅ Database schema changes applied
- ✅ OpenSIPS config updated
- ✅ Scripts updated and tested (syntax)
- ✅ Control panel modified and Apache restarted
- ⏳ Domain routing with new setid column - **Needs testing**
- ⏳ Installer with --db-password parameter - **Needs testing**

## Next Steps

1. **Immediate:**
   - Test domain routing with new setid column
   - Test adding/editing domains via control panel
   - Test installer with --db-password parameter
   - Verify OpenSIPS reloads config correctly with new setid queries

2. **Short-term:**
   - Document control panel setid usage in user guide
   - Consider creating script to apply control panel modifications

3. **Future:**
   - Build new admin panel (see ADMIN-PANEL-DESIGN.md)
   - Migrate away from modified control panel
   - Consider secrets management for production deployments

## Important Notes

- The setid column modification is an additive change that doesn't break existing functionality
- The domain module doesn't use the setid column - it's purely for our routing logic
- Control panel modifications are temporary until new admin panel is built
- Password sanitization ensures repository is safe for version control
- The installer now properly handles database passwords without hardcoding them

## Design Documents

- `ADMIN-PANEL-DESIGN.md` - Design document for future admin panel replacement
  - Documents setid column decision
  - Architecture recommendations
  - Technology stack suggestions
  - Migration strategy

