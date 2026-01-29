# Installer MySQL Remote Access & Laravel Database Plan

## Overview

This document outlines the plan to address installer issues:
1. **MySQL Remote Access**: Will be handled by admin panel installer (not needed in core installer)
2. **Laravel Database Setup**: Ensure Laravel admin panel can connect to the database (note: uses same `opensips` database, not separate)

## Decision: Admin Panel Installation Strategy

**Default Approach:** Admin panel will be installed on the **same host system** after core OpenSIPS installation.

**Benefits:**
- No remote MySQL access required by default
- Simpler setup and configuration
- Better security (localhost-only access)
- Admin panel installer can connect directly to localhost MySQL

**Remote Access:** If admin panel needs to be installed on a different server, the **admin panel installer** will handle MySQL remote access configuration (bind-address, UFW rules, MySQL grants). The core installer does not need to implement this functionality.

## Issue Analysis

### Issue 1: MySQL Port 3306 Opening

**Current State:**
- Installer creates MySQL database and user
- MySQL only accessible from localhost (default `bind-address = 127.0.0.1`)
- UFW firewall doesn't open port 3306
- No remote access configured

**Decision:**
- **Core installer:** Keep MySQL localhost-only (no changes needed)
- **Admin panel installer:** Will handle remote MySQL access configuration if admin panel is installed on different server
- Core installer does not need to implement MySQL remote access functionality

### Issue 2: Laravel Database

**Current State:**
- Installer creates `opensips` database
- Admin panel uses same `opensips` database (not separate)
- Laravel migrations need to be run to create application tables (users, cache, etc.)
- Admin panel installer handles migrations

**Requirements:**
- Database must exist (already handled ✅)
- Database accessible from localhost (default - no changes needed ✅)
- Laravel migrations will be run by admin panel installer (separate repo)
- **Note:** Since admin panel is on same host, no remote access needed by default

## Implementation Plan

### Phase 1: Core Installer Changes (Simplified)

**Decision:** Core installer does NOT need to implement MySQL remote access functionality. This will be handled by the admin panel installer.

**Core Installer Responsibilities:**
1. ✅ Create `opensips` database (already implemented)
2. ✅ Create `opensips` MySQL user (already implemented)
3. ✅ Keep MySQL localhost-only (default behavior - no changes needed)
4. ✅ Update installer output to guide admin panel installation

### Phase 2: Documentation Updates

#### 2.1 Update Installer Verification Output

**Location:** `install.sh` - `verify_installation()` function

**Add message about admin panel installation:**
```
=== Admin Panel Setup ===
The database 'opensips' is ready for the admin panel.

To install the admin panel on this host:
1. cd ../pbx3sbc-admin  (or path to admin panel repository)
2. ./install.sh --db-host localhost --db-name opensips --db-user opensips

If installing the admin panel on a different server:
1. Run the admin panel installer on the remote server:
   cd pbx3sbc-admin
   ./install.sh --db-host <OPENSIPS_SERVER_IP> --db-name opensips --db-user opensips
   
   The admin panel installer will handle MySQL remote access configuration
   (bind-address, UFW rules, MySQL grants) automatically.
```

### Phase 3: Laravel Database Considerations (No Changes Needed)

#### 3.1 Clarification

**Important:** The admin panel uses the **same `opensips` database**, not a separate database. Laravel migrations create application tables (users, cache, jobs, etc.) in the same database.

#### 3.2 Default Installation Flow (Same Host)

**Since admin panel is installed on same host:**
- Database `opensips` is created and ready ✅
- Admin panel installer connects to `localhost` MySQL ✅
- No remote access configuration needed ✅
- Admin panel installer (separate repo) will run Laravel migrations ✅

#### 3.3 Remote Installation Flow (Different Host)

**If admin panel is installed on different server:**
- Database `opensips` exists on OpenSIPS server ✅
- Admin panel installer handles MySQL remote access configuration:
  - Configures MySQL `bind-address`
  - Adds UFW firewall rules
  - Grants MySQL user remote privileges
- Admin panel installer connects remotely and runs migrations ✅

#### 3.4 Documentation Update

**Action:** Update installer output to clarify:
- Database `opensips` is created and ready for admin panel
- Admin panel installer (separate repo) should be run on this same host (default)
- Admin panel installer will run Laravel migrations automatically
- If admin panel is on different server, admin panel installer handles remote access configuration

## Testing Plan

### Test Case 1: Core Installer (Default - Same Host)
1. Run installer: `sudo ./install.sh`
2. Verify `opensips` database created
3. Verify MySQL user `opensips` created
4. Verify MySQL remains localhost-only (bind-address = 127.0.0.1)
5. Verify installer output includes admin panel installation instructions

### Test Case 2: Admin Panel Installation (Same Host - Default)
1. Complete OpenSIPS installation (MySQL localhost-only)
2. Install admin panel on same host: `cd pbx3sbc-admin && ./install.sh --db-host localhost`
3. Verify admin panel can connect to localhost MySQL
4. Verify Laravel migrations run successfully

### Test Case 3: Admin Panel Installation (Remote Host)
1. Complete OpenSIPS installation (MySQL localhost-only)
2. Install admin panel on different server: `cd pbx3sbc-admin && ./install.sh --db-host <OPENSIPS_SERVER_IP>`
3. Verify admin panel installer handles MySQL remote access configuration:
   - MySQL bind-address configured
   - UFW rules added
   - MySQL grants created
4. Verify admin panel can connect remotely and run migrations

**Note:** Test Cases 2 and 3 are for admin panel installer (separate repo), not core installer.

## Security Considerations

1. **Default to Localhost Only**: ✅ **Core installer default** - MySQL remains localhost-only (admin panel on same host)
2. **Remote Access Handled by Admin Installer**: Admin panel installer will handle remote access configuration if needed
3. **Separation of Concerns**: Core installer keeps MySQL secure by default; admin installer handles remote access when required
4. **Strong Passwords**: Core installer ensures MySQL user has strong password
5. **Documentation**: Core installer guides users to admin panel installer for remote deployments

## Files to Modify

1. **`install.sh`**
   - Update `verify_installation()` function to add admin panel installation instructions
   - No MySQL remote access functions needed (handled by admin panel installer)

2. **`docs/MYSQL-PORT-OPENING-PROCEDURE.md`**
   - Update to mention that admin panel installer handles remote access configuration
   - Note that core installer keeps MySQL localhost-only

3. **`docs/INSTALLATION.md`**
   - Add section about admin panel installation
   - Note that remote MySQL access is handled by admin panel installer

## Implementation Order

1. ✅ Create plan document (this file)
2. ✅ Decision: Remote access handled by admin panel installer (not core installer)
3. ⏳ Update `verify_installation()` function with admin panel installation instructions
4. ⏳ Update documentation files
5. ⏳ Test core installer (verify database creation and output messages)

## Notes

- **Admin Panel Installation Strategy**: ✅ **Decision made** - Admin panel will be installed on the same host system after core OpenSIPS installation. This simplifies setup and keeps MySQL secure by default (localhost-only).

- **Remote Access Handling**: ✅ **Decision made** - MySQL remote access configuration (bind-address, UFW rules, MySQL grants) will be handled by the admin panel installer, not the core installer. This keeps the core installer simple and focused.

- **Laravel Database**: The admin panel uses the same `opensips` database. Laravel migrations create application tables (users, cache, etc.) in that database. The admin panel installer handles running migrations.

- **Core Installer Responsibilities**: 
  - Create `opensips` database ✅
  - Create `opensips` MySQL user ✅
  - Keep MySQL localhost-only (default) ✅
  - Guide users to admin panel installer ✅

- **Admin Panel Installer Responsibilities**:
  - Handle MySQL remote access configuration (if admin panel on different server)
  - Run Laravel migrations
  - Configure admin panel application

- **Backward Compatibility**: Core installer behavior remains unchanged (localhost only, no remote access configuration).
