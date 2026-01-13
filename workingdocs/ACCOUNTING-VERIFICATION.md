# Accounting Module Verification

## Documentation Reference
Based on: https://opensips.org/docs/modules/3.6.x/acc.html

## Implementation Verification

### ✅ Module Loading
- **Location:** Line 54
- **Code:** `loadmodule "acc.so"`
- **Status:** Correct

### ✅ Dependencies and Load Order

**Required Dependencies:**
1. **`tm` module** (Transaction Management)
   - **Location:** Line 40
   - **Status:** ✅ Loaded before `acc.so`
   - **Required for:** Transaction-based accounting

2. **`db_mysql` module** (MySQL Database Backend)
   - **Location:** Line 46
   - **Status:** ✅ Loaded before `acc.so`
   - **Required for:** Database accounting backend

**Load Order:** ✅ Correct
- `tm.so` (line 40) → `db_mysql.so` (line 46) → `acc.so` (line 54)

### ✅ Module Parameters

**Implemented Parameters:**
1. **`db_url`** (string)
   - **Location:** Line 73
   - **Value:** `mysql://opensips:your-password@localhost/opensips`
   - **Status:** ✅ Correct - Required for database backend

2. **`early_media`** (integer)
   - **Location:** Line 74
   - **Value:** `0` (disabled)
   - **Status:** ✅ Valid parameter - Controls early media accounting

3. **`report_cancels`** (integer)
   - **Location:** Line 75
   - **Value:** `1` (enabled)
   - **Status:** ✅ Valid parameter - Log CANCEL requests

4. **`detect_direction`** (integer)
   - **Location:** Line 76
   - **Value:** `1` (enabled)
   - **Status:** ✅ Valid parameter - Auto-detect call direction

**Removed Invalid Parameters:**
- ❌ `db_flag` - Not in documentation
- ❌ `log_flag` - Not in documentation
- ❌ `failed_transaction_flag` - Not in documentation

### ✅ Function Usage

**Implementation:**
- **Function:** `do_accounting("db")`
- **Location:** INVITE (line 501), BYE (line 795)
- **Status:** ✅ Correct - Preferred method per documentation

**Documentation Reference:**
> "Since version 2.2, all flags used for accounting have been replaced with the do_accounting() function. No need to worry anymore whether you have set the flags or not, or be confused by various flag names, now you only have to call the function and it will do all the work for you."

**Function Details:**
- `do_accounting(type, [flags], [table])` - Marks transaction for accounting
- Type: `"db"` - Database backend
- Automatically handles both request and response accounting
- No need for separate response logging

**Removed Functions:**
- ❌ `acc_log_request()` - Logs to syslog, not database
- ❌ `acc_log_response()` - Not needed, `do_accounting()` handles responses automatically

### ✅ Response Handling

**Implementation:**
- **Location:** `onreply_route` (line 850)
- **Status:** ✅ Correct - No explicit response logging needed
- **Reason:** `do_accounting("db")` automatically accounts responses when transaction completes

## Summary

**✅ All aspects verified against OpenSIPS 3.6 documentation:**
- Module loading: Correct
- Dependencies: Correct (tm, db_mysql loaded before acc)
- Load order: Correct
- Parameters: All valid per documentation
- Function usage: Using preferred `do_accounting("db")` method
- Response handling: Automatic via `do_accounting()`

**Implementation matches OpenSIPS 3.6 acc module documentation.**
