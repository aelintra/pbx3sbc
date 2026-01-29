# Admin Panel Security Management Requirements

**Date:** January 2026  
**Status:** 📋 Requirements Definition  
**Target Repository:** `pbx3sbc-admin` (Laravel + Filament)

## Overview

This document outlines the security management features that need to be added to the pbx3sbc-admin web interface. These features will allow administrators to view, manage, and monitor the security elements implemented in Phase 1.1 and Phase 2.2 of the Security Implementation Plan.

## Security Features to Implement

### 1. Failed Registrations Management

**Database Table:** `failed_registrations`

**Features:**
- **View Failed Registrations** - Read-only list of failed registration attempts
- **Filtering & Search:**
  - Filter by username, domain, source IP, response code
  - Date range filtering
  - Search by username or IP address
- **Statistics:**
  - Total failed registrations (count)
  - Failed registrations by IP (top offenders)
  - Failed registrations by domain
  - Failed registrations by response code (403, 4xx, 5xx)
  - Time-based trends (last 24 hours, 7 days, 30 days)
- **Export:** CSV export of filtered results

**Filament Resource:** `FailedRegistrationResource`
- Model: `FailedRegistration` (Laravel model)
- Table: `failed_registrations`
- Actions: View, Filter, Export
- No create/edit/delete (read-only, data comes from OpenSIPS)

**Key Fields:**
- `id` - Primary key
- `username` - Username that failed
- `domain` - Domain of failed registration
- `source_ip` - Source IP address
- `source_port` - Source port
- `user_agent` - User agent string
- `response_code` - HTTP response code (403, 4xx, 5xx)
- `response_reason` - Response reason phrase
- `attempt_time` - Timestamp of attempt
- `expires_header` - Expires header value (if present)

**UI Components:**
- Table view with sortable columns
- Filters panel (username, domain, IP, date range, response code)
- Statistics cards/widgets on dashboard
- Detail view (modal or page)

---

### 2. Door-Knock Attempts Management

**Database Table:** `door_knock_attempts`

**Features:**
- **View Door-Knock Attempts** - Read-only list of door-knock attempts
- **Filtering & Search:**
  - Filter by domain, source IP, reason, method
  - Date range filtering
  - Search by domain or IP address
- **Statistics:**
  - Total door-knock attempts (count)
  - Door-knock attempts by IP (top offenders)
  - Door-knock attempts by reason (scanner_detected, domain_not_found, query_failed, etc.)
  - Door-knock attempts by method (INVITE, REGISTER, etc.)
  - Time-based trends
- **Export:** CSV export of filtered results

**Filament Resource:** `DoorKnockAttemptResource`
- Model: `DoorKnockAttempt` (Laravel model)
- Table: `door_knock_attempts`
- Actions: View, Filter, Export
- No create/edit/delete (read-only, data comes from OpenSIPS)

**Key Fields:**
- `id` - Primary key
- `domain` - Domain attempted (may be NULL)
- `source_ip` - Source IP address
- `source_port` - Source port
- `user_agent` - User agent string
- `method` - SIP method (INVITE, REGISTER, etc.)
- `request_uri` - Request URI
- `reason` - Reason for door-knock (scanner_detected, domain_not_found, query_failed, domain_mismatch, method_not_allowed, max_forwards_exceeded)
- `attempt_time` - Timestamp of attempt

**UI Components:**
- Table view with sortable columns
- Filters panel (domain, IP, reason, method, date range)
- Statistics cards/widgets on dashboard
- Detail view (modal or page)

---

### 3. Fail2ban Whitelist Management

**Configuration File:** `/etc/fail2ban/jail.d/opensips-brute-force.conf`

**Features:**
- **View Whitelist** - List of currently whitelisted IPs and CIDR ranges
- **Add to Whitelist:**
  - Add single IP address
  - Add CIDR range
  - Add comment/description for each entry
- **Remove from Whitelist:**
  - Remove IP or CIDR range
  - Confirmation dialog before removal
- **Bulk Operations:**
  - Import from CSV
  - Export to CSV
- **Validation:**
  - Validate IP address format (IPv4 and IPv6)
  - Validate CIDR notation
  - Prevent duplicates

**Implementation Approach:**
- **Option A:** Direct file manipulation (read/write `/etc/fail2ban/jail.d/opensips-brute-force.conf`)
  - Requires sudo/root access or proper permissions
  - Use Laravel's `Process` facade to execute `manage-fail2ban-whitelist.sh` script
- **Option B:** Database-backed whitelist (recommended)
  - Create `fail2ban_whitelist` table in database
  - Admin panel manages database table
  - Cron job or systemd service syncs database to Fail2ban config file
  - More secure (no direct file access needed)

**Recommended: Option B (Database-Backed)**

**Database Table:** `fail2ban_whitelist`
```sql
CREATE TABLE fail2ban_whitelist (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_or_cidr VARCHAR(45) NOT NULL,
    comment VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_by INT DEFAULT NULL,  -- Foreign key to users table
    UNIQUE KEY unique_ip_cidr (ip_or_cidr),
    INDEX idx_ip_cidr (ip_or_cidr)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**Filament Resource:** `Fail2banWhitelistResource`
- Model: `Fail2banWhitelist` (Laravel model)
- Table: `fail2ban_whitelist`
- Actions: Create, Edit, Delete, View
- Form validation for IP/CIDR format

**UI Components:**
- Table view with IP/CIDR, comment, created date
- Create form (IP/CIDR input, comment textarea)
- Edit form (update comment)
- Delete action with confirmation
- Bulk import/export buttons

**Sync Script:** Create `scripts/sync-fail2ban-whitelist.sh` that:
1. Reads from `fail2ban_whitelist` table
2. Updates `/etc/fail2ban/jail.d/opensips-brute-force.conf`
3. Restarts Fail2ban service
4. Can be run via cron or triggered from admin panel

---

### 4. Fail2ban Status & Monitoring

**Features:**
- **Jail Status** - View Fail2ban jail status (enabled, banned IPs, etc.)
- **Banned IPs List** - View currently banned IP addresses
- **Manual Actions:**
  - Ban IP manually
  - Unban IP manually
  - Unban all IPs
- **Statistics:**
  - Total banned IPs
  - Currently banned IPs count
  - Bans in last 24 hours
  - Top banned IPs (if history tracked)

**Implementation:**
- Use Laravel's `Process` facade to execute `fail2ban-client` commands
- Requires sudo access or proper permissions
- Consider using `sudoers` file to allow specific commands without password

**Commands to Execute:**
```bash
# Get jail status
fail2ban-client status opensips-brute-force

# Get banned IPs
fail2ban-client status opensips-brute-force | grep "Banned IP"

# Ban IP
fail2ban-client set opensips-brute-force banip <IP>

# Unban IP
fail2ban-client set opensips-brute-force unbanip <IP>

# Unban all
fail2ban-client set opensips-brute-force unban --all
```

**Filament Resource:** `Fail2banStatusResource`
- Not a database resource (no model)
- Custom Filament page or widget
- Real-time status display
- Action buttons for manual ban/unban

**UI Components:**
- Status card showing jail status
- Table of banned IPs with unban action
- Manual ban form (IP input, ban button)
- Statistics widgets

---

### 5. Security Statistics & Reporting (Phase 3.3)

**Objective:** Provide comprehensive security statistics and reporting

**Note:** This replaces Phase 3.3 from the Security Implementation Plan - statistics and reporting belong in the admin panel, not core OpenSIPS.

**Features:**

#### 5.1 Security Dashboard Widgets

- **Failed Registrations Widget:**
  - Count of failed registrations in last 24 hours
  - Chart showing trend over time (hourly/daily)
  - Top 5 source IPs
  - Failed registrations by domain
  - Failed registrations by response code
- **Door-Knock Attempts Widget:**
  - Count of door-knock attempts in last 24 hours
  - Chart showing trend over time (hourly/daily)
  - Top 5 source IPs
  - Door-knock attempts by reason
  - Door-knock attempts by method
- **Fail2ban Status Widget:**
  - Currently banned IPs count
  - Jail status (enabled/disabled)
  - Recent bans (last 10)
  - Bans in last 24 hours
- **Security Alerts Widget:**
  - High-risk IPs (many failures)
  - Recent security events
  - Recommendations (e.g., "Consider banning IP X")

**Filament Widgets:**
- `FailedRegistrationsStatsWidget`
- `DoorKnockAttemptsStatsWidget`
- `Fail2banStatusWidget`
- `SecurityAlertsWidget`

#### 5.2 Security Statistics Views

**Database Queries/Views (computed via Laravel, not SQL views):**
- `security_stats_hourly` - Hourly event counts (computed via Eloquent)
- `top_attacking_ips` - Top attacking IPs (computed via Eloquent)
- `registration_failure_stats` - Registration failure trends (computed via Eloquent)
- `door_knock_stats_by_reason` - Door-knock statistics by reason
- `security_trends_daily` - Daily security event trends

**Note:** Statistics can be computed via Laravel Eloquent queries. SQL views are optional optimization but not required.

#### 5.3 Reporting Features

- **Generate Security Reports:**
  - Date range selection
  - Filter by event type, IP, domain
  - Export to CSV/PDF
  - Email reports (optional)
- **Report Types:**
  - Failed registrations report
  - Door-knock attempts report
  - Combined security report
  - Top attacking IPs report
  - Security trends report

**Filament Resources:**
- `SecurityReportResource` (custom page for report generation)
- Export actions on FailedRegistrationResource and DoorKnockAttemptResource

---

## Database Schema Updates

### New Tables Needed

1. **`fail2ban_whitelist`** (for whitelist management)
   - See schema above

2. **Optional: `fail2ban_bans`** (for ban history tracking)
   ```sql
   CREATE TABLE fail2ban_bans (
       id INT AUTO_INCREMENT PRIMARY KEY,
       ip_address VARCHAR(45) NOT NULL,
       banned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
       unbanned_at TIMESTAMP NULL,
       reason VARCHAR(255) DEFAULT NULL,
       INDEX idx_ip (ip_address),
       INDEX idx_banned_at (banned_at)
   ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
   ```
   - Track ban history for reporting
   - Can be populated by monitoring Fail2ban logs or via API

---

## Laravel Models

### Models to Create

1. **`FailedRegistration`**
   ```php
   namespace App\Models;
   
   use Illuminate\Database\Eloquent\Model;
   
   class FailedRegistration extends Model
   {
       protected $table = 'failed_registrations';
       public $timestamps = false; // Table doesn't have created_at/updated_at
       
       protected $fillable = [
           'username', 'domain', 'source_ip', 'source_port',
           'user_agent', 'response_code', 'response_reason',
           'attempt_time', 'expires_header'
       ];
       
       protected $casts = [
           'attempt_time' => 'datetime',
           'source_port' => 'integer',
           'response_code' => 'integer',
           'expires_header' => 'integer',
       ];
   }
   ```

2. **`DoorKnockAttempt`**
   ```php
   namespace App\Models;
   
   use Illuminate\Database\Eloquent\Model;
   
   class DoorKnockAttempt extends Model
   {
       protected $table = 'door_knock_attempts';
       public $timestamps = false;
       
       protected $fillable = [
           'domain', 'source_ip', 'source_port', 'user_agent',
           'method', 'request_uri', 'reason', 'attempt_time'
       ];
       
       protected $casts = [
           'attempt_time' => 'datetime',
           'source_port' => 'integer',
       ];
   }
   ```

3. **`Fail2banWhitelist`**
   ```php
   namespace App\Models;
   
   use Illuminate\Database\Eloquent\Model;
   
   class Fail2banWhitelist extends Model
   {
       protected $table = 'fail2ban_whitelist';
       
       protected $fillable = [
           'ip_or_cidr', 'comment', 'created_by'
       ];
       
       public function creator()
       {
           return $this->belongsTo(User::class, 'created_by');
       }
   }
   ```

---

## Filament Resources

### Resources to Create

1. **`FailedRegistrationResource`**
   - Location: `app/Filament/Resources/FailedRegistrationResource.php`
   - Table view with filters
   - Export action
   - Read-only (no create/edit/delete)

2. **`DoorKnockAttemptResource`**
   - Location: `app/Filament/Resources/DoorKnockAttemptResource.php`
   - Table view with filters
   - Export action
   - Read-only (no create/edit/delete)

3. **`Fail2banWhitelistResource`**
   - Location: `app/Filament/Resources/Fail2banWhitelistResource.php`
   - Full CRUD (create, read, update, delete)
   - IP/CIDR validation
   - Sync action (syncs to Fail2ban config)

4. **`Fail2banStatusResource`** (Custom Page)
   - Location: `app/Filament/Pages/Fail2banStatus.php`
   - Custom page (not a resource)
   - Real-time status display
   - Manual ban/unban actions

---

## Permissions & Security

### Required Permissions

1. **File System Access:**
   - Read `/etc/fail2ban/jail.d/opensips-brute-force.conf` (for whitelist sync)
   - Write `/etc/fail2ban/jail.d/opensips-brute-force.conf` (for whitelist sync)
   - Execute `fail2ban-client` commands (for status/ban/unban)

2. **Sudo Configuration:**
   - Create `/etc/sudoers.d/pbx3sbc-admin` file:
     ```
     www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client status opensips-brute-force
     www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force banip *
     www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unbanip *
     www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unban --all
     www-data ALL=(ALL) NOPASSWD: /home/*/pbx3sbc/scripts/sync-fail2ban-whitelist.sh
     ```
   - Or use a dedicated service account with limited permissions

3. **Database Access:**
   - Read access to `failed_registrations` table
   - Read access to `door_knock_attempts` table
   - Full access to `fail2ban_whitelist` table

---

## Implementation Priority

### Phase 1: Viewing & Monitoring (High Priority)
1. ✅ Failed Registrations Resource (read-only)
2. ✅ Door-Knock Attempts Resource (read-only)
3. ✅ Security Dashboard Widgets

### Phase 2: Fail2ban Management (High Priority)
4. ✅ Fail2ban Whitelist Resource (CRUD)
5. ✅ Whitelist sync script
6. ✅ Fail2ban Status Page

### Phase 3: Advanced Features (Medium Priority)
7. ⏸️ Manual ban/unban actions
8. ⏸️ Ban history tracking
9. ⏸️ Security alerts/recommendations

---

## Related Documentation

- [Security Implementation Plan](../SECURITY-IMPLEMENTATION-PLAN.md) - Overall security project plan
- [Failed Registration Tracking](FAILED-REGISTRATION-TRACKING-COMPARISON.md) - Details on failed registration logging
- [Fail2ban Configuration](../config/fail2ban/README.md) - Fail2ban setup and configuration

---

## Notes

- All security data is read-only (comes from OpenSIPS logs/database)
- Only Fail2ban whitelist is editable (managed by admin panel)
- Consider rate limiting on ban/unban actions to prevent abuse
- Log all admin actions (who banned/unbanned what, when)
- Consider adding audit trail for whitelist changes
