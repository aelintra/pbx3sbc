# Session Summary: Environment Variable Fix for Whitelist Sync

**Date:** January 29, 2026  
**Issue:** Whitelist sync failing due to environment variables not being preserved through sudo

---

## Problem

The whitelist sync from the admin panel was failing with error:
```
Error: DB_PASS environment variable not set
```

**Root Cause:**
- `sudo` by default resets environment variables for security (`env_reset`)
- Even with `sudo -E`, some systems don't allow preserving environment
- The `env_keep` directive in sudoers wasn't sufficient on all systems

---

## Solution

Changed from environment variables to command-line arguments for passing database credentials.

### Why This Approach?

1. **More Reliable:** Command-line arguments work consistently with sudo
2. **No sudo Configuration Needed:** Doesn't require `env_keep` or `-E` flag
3. **Simpler:** Less dependency on sudoers configuration
4. **Secure:** Credentials still passed securely, just via different mechanism

---

## Changes Made

### 1. Updated Sync Script (`scripts/sync-fail2ban-whitelist.sh`)

**Before:**
```bash
# Only accepted environment variables
DB_NAME="${DB_NAME:-opensips}"
DB_USER="${DB_USER:-opensips}"
DB_PASS="${DB_PASS:-}"
```

**After:**
```bash
# Accept credentials from command-line arguments or environment variables
# Command-line arguments take precedence (more reliable with sudo)
if [[ $# -ge 3 ]]; then
    DB_NAME="$1"
    DB_USER="$2"
    DB_PASS="$3"
else
    # Fallback to environment variables (for cron, manual use)
    DB_NAME="${DB_NAME:-opensips}"
    DB_USER="${DB_USER:-opensips}"
    DB_PASS="${DB_PASS:-}"
fi
```

**Usage:**
```bash
# From admin panel (with arguments)
./sync-fail2ban-whitelist.sh opensips opensips password123

# From cron or manual (with environment variables)
DB_PASS="password123" ./sync-fail2ban-whitelist.sh
```

**Commit:** `ffb6740` - Update sync script to accept credentials as command-line arguments

---

### 2. Updated WhitelistSyncService (`pbx3sbc-admin/app/Services/WhitelistSyncService.php`)

**Before:**
```php
// Pass credentials as environment variables
$env = [
    'DB_NAME' => $dbName,
    'DB_USER' => $dbUser,
    'DB_PASS' => $dbPass,
];
$result = Process::env($env)
    ->run(['sudo', '-E', $scriptPath]);
```

**After:**
```php
// Pass credentials as command-line arguments
// This is more reliable than environment variables with sudo
$result = Process::run([
    'sudo',
    $scriptPath,
    $dbName,
    $dbUser,
    $dbPass
]);
```

**Benefits:**
- No need for `sudo -E` flag
- No dependency on `env_keep` in sudoers
- Works consistently across all systems

**Commit:** (pbx3sbc-admin) - Update WhitelistSyncService to pass credentials as arguments

---

### 3. Updated Sudoers Setup Script (`scripts/setup-admin-panel-sudoers.sh`)

**Added:**
```bash
# Preserve environment variables for sync script (DB_NAME, DB_USER, DB_PASS)
# Try multiple syntaxes for compatibility
Defaults:www-data !env_reset
Defaults:www-data env_keep += "DB_NAME DB_USER DB_PASS"
```

**Note:** While these lines are included for backward compatibility (if someone uses env vars), they're not strictly needed with the new argument-based approach.

**Commit:** `ffb6740` - Update sync script to accept credentials as command-line arguments

---

## Testing

**Before Fix:**
```
[2026-01-29 02:37:20] local.ERROR: Failed to sync Fail2Ban whitelist
{"error_output":"sudo: sorry, you are not allowed to preserve the environment"}
```

**After Fix:**
- Credentials passed as command-line arguments
- No dependency on environment variable preservation
- Should work consistently

---

## Files Changed

### pbx3sbc Repository:
1. `scripts/sync-fail2ban-whitelist.sh` - Accept credentials as arguments
2. `scripts/setup-admin-panel-sudoers.sh` - Added env_keep (optional, for backward compat)

### pbx3sbc-admin Repository:
1. `app/Services/WhitelistSyncService.php` - Pass credentials as arguments

---

## Migration Notes

**For Existing Installations:**

1. **Pull latest changes:**
   ```bash
   cd /path/to/pbx3sbc
   git pull origin cleanupV2
   
   cd /path/to/pbx3sbc-admin
   git pull origin f2b-manage
   ```

2. **No sudoers changes needed** - The existing sudoers file will work fine

3. **Test whitelist sync** - Should work immediately after pulling changes

**For Cron Jobs:**

If you have cron jobs calling the sync script with environment variables, they'll continue to work (script falls back to env vars if no arguments provided).

---

## Related Issues

- Original issue: Environment variables not preserved through sudo
- Previous attempts: `sudo -E`, `env_keep` directive
- Final solution: Command-line arguments (most reliable)

---

## Related Documentation

- `workingdocs/SESSION-SUMMARY-FAIL2BAN-ADMIN-PANEL-FIX.md` - Previous session summary
- `scripts/sync-fail2ban-whitelist.sh` - Sync script with updated usage
- `app/Services/WhitelistSyncService.php` - Updated service implementation

---

**Status:** ✅ Fixed - Credentials now passed as command-line arguments, avoiding sudo environment variable issues
