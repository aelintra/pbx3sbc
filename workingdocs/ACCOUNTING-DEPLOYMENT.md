# Accounting (CDR) Feature - Deployment Checklist

## Overview
Deployment checklist for Feature 1: Accounting (CDR) functionality.

## Prerequisites

### Database Tables
✅ **Already Deployed** - Tables exist from `standard-create.sql`:
- `acc` - Call Detail Records
- `missed_calls` - Missed call logging

**Verification:**
```bash
mysql -u opensips -p opensips -e "SHOW TABLES LIKE 'acc';"
mysql -u opensips -p opensips -e "SHOW TABLES LIKE 'missed_calls';"
```

### OpenSIPS Packages
✅ **Already Installed** - `acc` module is included in base `opensips` package

**Verification:**
```bash
opensips -m | grep acc
# Should show: acc.so
```

If not found, verify OpenSIPS installation:
```bash
dpkg -l | grep opensips
# Should show: opensips, opensips-mysql-module, opensips-mysql-dbschema
```

## Deployment Steps

### 1. OpenSIPS Configuration Changes

#### 1.1 Load `acc` Module
**File:** `config/opensips.cfg.template`

**Add after existing modules:**
```opensips
loadmodule "acc.so"
```

**Location:** After line 52 (after nathelper.so)

#### 1.2 Configure `acc` Module Parameters
**File:** `config/opensips.cfg.template`

**Add after module parameters section:**
```opensips
# --- Accounting (CDR) ---
modparam("acc", "db_url", "mysql://opensips:your-password@localhost/opensips")
modparam("acc", "db_flag", 1)
modparam("acc", "log_flag", 1)
modparam("acc", "failed_transaction_flag", 2)
modparam("acc", "early_media", 0)
modparam("acc", "report_cancels", 1)
modparam("acc", "detect_direction", 1)
```

**Location:** After dispatcher module parameters (around line 68)

**Parameters Explained:**
- `db_url`: MySQL connection string (use same credentials as other modules)
- `db_flag`: Flag to enable database accounting (flag 1)
- `log_flag`: Flag to enable syslog accounting (flag 1) - optional
- `failed_transaction_flag`: Flag for failed transactions (flag 2)
- `early_media`: Track early media (0 = disabled)
- `report_cancels`: Log CANCEL requests (1 = enabled)
- `detect_direction`: Auto-detect call direction (1 = enabled)

#### 1.3 Add Accounting Calls in Routing Logic
**File:** `config/opensips.cfg.template`

**Add accounting for INVITE requests:**
In the INVITE handling section (around line 120-150), add:
```opensips
if (is_method("INVITE")) {
    setflag(1);  # Enable accounting for this transaction
    acc_log_request("200");
}
```

**Add accounting for BYE requests:**
In the BYE handling section, add:
```opensips
if (is_method("BYE")) {
    setflag(1);  # Enable accounting for this transaction
    acc_log_request("200");
}
```

**Add accounting for responses:**
In the response handling section (if exists), or add to main route:
```opensips
# Log accounting for responses
if (has_totag()) {
    acc_log_response("200");
}
```

**Alternative Approach (Using Flags):**
Instead of explicit `acc_log_request` calls, you can use flags:
```opensips
# Set accounting flag for INVITE
if (is_method("INVITE")) {
    setflag(1);
}

# Set accounting flag for BYE
if (is_method("BYE")) {
    setflag(1);
}
```

The `acc` module will automatically log when flags match `db_flag` parameter.

### 2. Update Install Script (Optional)

**File:** `install.sh`

**No changes needed** - `acc` module is part of base OpenSIPS package.

**Optional:** Add verification step to check `acc` module is available:
```bash
# Verify acc module is available
if opensips -m 2>/dev/null | grep -q "acc"; then
    log_success "Accounting module (acc) is available"
else
    log_warn "Accounting module (acc) not found - check OpenSIPS installation"
fi
```

### 3. Database Verification

**Verify tables exist:**
```bash
mysql -u opensips -p opensips <<EOF
DESCRIBE acc;
DESCRIBE missed_calls;
EOF
```

**Expected `acc` table columns:**
- `id` (auto-increment primary key)
- `method` (SIP method)
- `from_tag`, `to_tag` (SIP tags)
- `callid` (Call-ID header)
- `sip_code`, `sip_reason` (response code/reason)
- `time` (timestamp)
- `duration` (call duration in seconds)
- `ms_duration` (duration in milliseconds)
- `setuptime` (setup time)
- `created` (record creation time)

### 4. Testing

#### 4.1 Configuration Test
```bash
# Test OpenSIPS configuration syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Should show no errors
```

#### 4.2 Restart OpenSIPS
```bash
sudo systemctl restart opensips
sudo systemctl status opensips
```

#### 4.3 Generate Test Traffic
- Make a test call (INVITE)
- Hang up (BYE)
- Check database for records

#### 4.4 Verify Accounting Data
```bash
# Check for accounting records
mysql -u opensips -p opensips -e "SELECT * FROM acc ORDER BY time DESC LIMIT 10;"

# Check for missed calls
mysql -u opensips -p opensips -e "SELECT * FROM missed_calls ORDER BY time DESC LIMIT 10;"
```

### 5. Admin Panel Integration (Future)

**TODO:** Create admin panel interface for viewing CDRs
- List CDRs with filtering
- View call details
- Export CDRs
- Statistics dashboard

## Deployment Summary

**What Needs to be Deployed:**

1. ✅ **Database Tables** - Already exist (from standard-create.sql)
2. ✅ **OpenSIPS Package** - Already installed (acc module in base package)
3. ⚠️ **Configuration Changes** - Need to add:
   - Load `acc` module
   - Configure `acc` module parameters
   - Add accounting calls/flags in routing logic
4. ⚠️ **Testing** - Verify accounting data collection

**No Additional Packages Required** - Everything needed is already installed.

## Rollback Plan

If issues occur:
1. Comment out `loadmodule "acc.so"` in config
2. Comment out `modparam("acc", ...)` lines
3. Remove accounting calls from routing logic
4. Restart OpenSIPS: `sudo systemctl restart opensips`

## Next Steps After Deployment

1. Monitor accounting data collection
2. Verify data accuracy
3. Create admin panel interface for CDR viewing
4. Document accounting configuration
5. Proceed to Feature 2: Statistics Gathering
