# Two-Repository Strategy: PBX3sbc + Admin Panel

**Date:** January 2026  
**Status:** Planning

## Overview

We have two separate repositories with different purposes:

1. **`pbx3sbc`** - OpenSIPS SIP Edge Router configuration and deployment
2. **`pbx3sbc-admin`** (or similar name) - Laravel + Filament admin panel application

## Repository Separation

### Repository 1: `pbx3sbc` (Current Repo)
**Purpose:** OpenSIPS SBC configuration and deployment

**Contains:**
- OpenSIPS configuration files (`config/opensips.cfg.template`)
- Database initialization scripts (`scripts/init-database.sh`)
- OpenSIPS installation scripts (`install.sh`)
- Helper scripts (`add-domain.sh`, `add-dispatcher.sh`, etc.)
- Documentation

**Key Point:** Sets up and manages the MySQL database that both OpenSIPS and the admin panel use.

### Repository 2: `pbx3sbc-admin` (New Repo)
**Purpose:** Web-based admin panel application

**Contains:**
- Laravel + Filament application code
- Eloquent models (`Domain`, `Dispatcher`, etc.)
- Filament Resources
- Services (`OpenSIPSMIService`, etc.)
- Application-specific migrations (users table, etc.)
- Application documentation

**Key Point:** Connects to the same MySQL database that pbx3sbc sets up, but adds application tables (users, roles, etc.).

## Relationship Diagram

```
┌─────────────────────────────────────┐
│   pbx3sbc Repository                │
│                                     │
│   ┌─────────────────────────────┐  │
│   │  install.sh                 │  │
│   │  - Installs OpenSIPS        │  │
│   │  - Sets up MySQL database   │  │
│   └───────────┬─────────────────┘  │
│               │                     │
│   ┌───────────▼─────────────────┐  │
│   │  scripts/init-database.sh   │  │
│   │  - Creates OpenSIPS tables  │  │
│   │    (domain, dispatcher)     │  │
│   └───────────┬─────────────────┘  │
└───────────────┼─────────────────────┘
                │
                │ Creates/Manages
                │
        ┌───────▼────────┐
        │   MySQL DB     │
        │  (opensips)    │
        │                │
        │  Tables:       │
        │  - domain      │ ← Used by both
        │  - dispatcher  │ ← Used by both
        │  - users       │ ← Created by admin panel
        │  - roles       │ ← Created by admin panel
        └───────┬────────┘
                │
                │ Reads/Writes
                │
┌───────────────┼─────────────────────┐
│   pbx3sbc-admin Repository          │
│                                     │
│   ┌─────────────────────────────┐  │
│   │  Laravel Application        │  │
│   │  - Models (Domain, etc.)    │  │
│   │  - Filament Resources       │  │
│   │  - Services                 │  │
│   └─────────────────────────────┘  │
│                                     │
│   ┌─────────────────────────────┐  │
│   │  install.sh or setup.sh     │  │
│   │  - Installs dependencies    │  │
│   │  - Runs migrations          │  │
│   │  - Configures .env          │  │
│   └─────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Installation Options

### Option A: Two Separate Installations (Recommended)

Each repository has its own installation process:

**Step 1: Install OpenSIPS (pbx3sbc repo)**
```bash
git clone https://github.com/your-org/pbx3sbc.git
cd pbx3sbc
sudo ./install.sh
# This creates the MySQL database and OpenSIPS tables
```

**Step 2: Install Admin Panel (pbx3sbc-admin repo)**
```bash
git clone https://github.com/your-org/pbx3sbc-admin.git
cd pbx3sbc-admin
sudo ./install.sh  # or setup.sh, or composer install + manual config
# This installs Laravel, connects to existing MySQL database
```

**Pros:**
- Clear separation of concerns
- Each repo can be installed/updated independently
- Easier to version and release separately
- Cleaner git history

**Cons:**
- Two installation steps for users
- Need to ensure database credentials match

### Option B: pbx3sbc Installer Clones Admin Panel Repo

The `install-admin-panel.sh` script in pbx3sbc repo clones the admin panel repo:

**Modified install-admin-panel.sh:**
```bash
# Instead of: composer create-project laravel/laravel
# Use: git clone the admin panel repo

git clone https://github.com/your-org/pbx3sbc-admin.git "$ADMIN_PANEL_DIR"
cd "$ADMIN_PANEL_DIR"
composer install
cp .env.example .env
# Configure .env with database credentials
php artisan migrate
```

**Pros:**
- Single installation command from pbx3sbc repo
- Ensures versions are compatible

**Cons:**
- Tight coupling between repos
- Admin panel repo must be publicly accessible (or use authentication)
- Less flexible for development

### Option C: Hybrid Approach (Recommended for Development)

**For Development:**
- Clone both repos separately
- Work on them independently
- Test integration locally

**For Production:**
- Option A: Two separate installations
- OR Option B: pbx3sbc installer clones admin panel repo (optional convenience)

## Development Workflow

### Working on OpenSIPS Configuration (pbx3sbc repo)
```bash
cd ~/GiT/pbx3sbc
# Make changes to opensips.cfg.template
# Test with OpenSIPS
git commit -m "Update routing logic"
git push
```

### Working on Admin Panel (pbx3sbc-admin repo)
```bash
cd ~/GiT/pbx3sbc-admin
# Make changes to Filament Resources, Models, etc.
php artisan serve  # Test locally
git commit -m "Add domain filtering"
git push
```

### Integration Testing
```bash
# Ensure both repos are installed on test server
# Test that admin panel can manage OpenSIPS database
# Verify OpenSIPS MI integration works
```

## Database Schema Management

### OpenSIPS Tables (Managed by pbx3sbc)
- `domain` - Created by `scripts/init-database.sh`
- `dispatcher` - Created by `scripts/init-database.sh`
- `endpoint_locations` - Created by `scripts/init-database.sh` (custom table for endpoint tracking)

**Migration Strategy:** Changes to OpenSIPS tables are managed via SQL scripts in pbx3sbc repo.

### Application Tables (Managed by pbx3sbc-admin)
- `users` - Laravel migration
- `password_reset_tokens` - Laravel migration
- `roles`, `permissions` - Filament Shield migrations (if used)
- Any future application-specific tables

**Migration Strategy:** Laravel migrations in `database/migrations/` directory.

### Shared Tables Challenge

**Problem:** Both repos need to work with `domain` and `dispatcher` tables.

**Solution:**
- pbx3sbc: Creates and manages schema (ADD COLUMN setid, etc.)
- pbx3sbc-admin: Reads/writes data via Eloquent models
- Schema changes to OpenSIPS tables: Update pbx3sbc scripts, then admin panel models
- Application tables: Managed entirely by pbx3sbc-admin migrations

## Configuration Management

### Database Credentials

**Current Approach (pbx3sbc):**
- Stores credentials in `/etc/opensips/.mysql_credentials`
- Used by OpenSIPS and scripts

**Admin Panel Approach (pbx3sbc-admin):**
- Uses Laravel `.env` file
- Needs same database credentials

**Options:**
1. **Separate .env files** - Admin panel has its own .env (recommended)
2. **Shared credentials file** - Both read from `/etc/opensips/.mysql_credentials`
3. **Environment variables** - Set system-wide, both read from env

**Recommendation:** Option 1 (separate .env) for flexibility, but installer script can read from shared credentials file to auto-populate.

### OpenSIPS MI Configuration

**Location:** Admin panel `.env` file
```env
OPENSIPS_MI_URL=http://127.0.0.1:8888/mi
```

This is admin-panel-specific configuration (not needed by pbx3sbc repo).

## Version Compatibility

### Dependency Matrix

| Component | Managed By | Version |
|-----------|-----------|---------|
| OpenSIPS | pbx3sbc | 3.6.x |
| MySQL Schema | pbx3sbc | OpenSIPS 3.6 version 9 |
| Laravel | pbx3sbc-admin | 12.x |
| Filament | pbx3sbc-admin | 3.x |
| PHP | Both | 8.2+ |

### Compatibility Notes

- Admin panel must be compatible with OpenSIPS 3.6 database schema
- If OpenSIPS schema changes, admin panel models may need updates
- Document schema versions in both repos

## Recommended Approach

### For Initial Development
1. ✅ Create separate `pbx3sbc-admin` repository
2. ✅ Each repo has its own `install.sh` or setup process
3. ✅ Development: Clone both repos locally, work independently
4. ✅ Installation: Two-step process (install OpenSIPS, then admin panel)

### For Future Convenience (Optional)
- Update `install-admin-panel.sh` in pbx3sbc repo to optionally clone admin panel repo
- Keep as optional feature (--clone-from-repo flag)
- Default can still be manual installation

### Documentation Strategy
- **pbx3sbc README:** Focuses on OpenSIPS installation, mentions admin panel as optional
- **pbx3sbc-admin README:** Focuses on Laravel/Filament setup, mentions pbx3sbc as prerequisite
- **Integration Guide:** Separate doc explaining how to install both together

## Next Steps

1. **Create pbx3sbc-admin repository**
   - Initialize with Laravel + Filament
   - Set up project structure
   - Create initial README explaining dependency on pbx3sbc

2. **Update pbx3sbc documentation**
   - Add section about admin panel installation
   - Update install-admin-panel.sh to optionally clone from repo (or deprecate it)

3. **Create integration documentation**
   - How to install both together
   - Database credential management
   - Version compatibility notes
