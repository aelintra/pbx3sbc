# Phase 0: Permissions Module Research

**Date:** January 2026  
**Branch:** `permissions-test` (to be created)  
**Status:** 🔍 Researching  
**Module:** Permissions (IP-based access control)

---

## Documentation Review

**Official Documentation URL:** https://opensips.org/html/docs/modules/3.6.x/permissions.html

### Research Questions

#### Modparam Parameters
- [x] What modparam parameters does the module support? ✅ Verified
- [x] Is `db_url` parameter required? ✅ Yes (for database-backed ACLs)
- [x] Is `db_table` parameter required? ✅ No - uses `address_table` instead!
- [x] What is the default table name? ✅ `address`
- [x] Does it support file-based ACLs (allow_file/deny_file)? ✅ Yes
- [x] What is the default allow/deny behavior? ✅ Deny if no match (address permissions)

#### Functions
- [x] What functions are available? ✅ Verified
- [x] What is the correct syntax for `allow_source_address()`? ✅ It's `check_source_address()`!
- [x] What parameters does it take? ✅ `check_source_address(group_id, [context_info], [pattern], [partition])`
- [x] Are there other functions like `allow_address()`, `allow_trusted()`? ✅ `check_address()` exists
- [x] How do groups work? ✅ Group ID determines which group to check

#### Database Schema
- [x] What is the required database table schema? ✅ Verified
- [x] What columns are required? ✅ `grp`, `ip_addr`, `mask`, `port`, `proto`, `pattern`, `info`
- [x] What are the column types and constraints? ✅ Verified
- [x] Are indexes required? ✅ Recommended for performance
- [x] What does the `grp` column represent? ✅ Group identifier (unsigned integer)

#### Behavior
- [x] Default behavior: allow all or deny all? ✅ Deny if no match (address permissions)
- [x] How does whitelisting work? ✅ Add IPs to database table with group ID
- [x] How does blacklisting work? ✅ Don't add IPs to table (default deny)
- [x] Can it support multi-tenant scenarios? ✅ Yes, via `partition` parameter
- [x] Performance considerations? ✅ Addresses cached in memory, two cache tables

---

## Findings

**Documentation Reviewed:** ✅ https://opensips.org/html/docs/modules/3.6.x/permissions.html

### Modparam Parameters
**Status:** ✅ **VERIFIED FROM DOCUMENTATION**

**Key Parameters:**
- `db_url` (string) - Database URL for ACL storage
- `address_table` (string) - Database table name (default: `address`) ⚠️ **NOT `db_table`!**
- `default_allow_file` (string) - File-based allow list (optional)
- `default_deny_file` (string) - File-based deny list (optional)
- `check_all_branches` (integer) - Check all branches when forking
- `allow_suffix` (string) - Suffix for allow files
- `deny_suffix` (string) - Suffix for deny files
- `partition` (string) - Partition name for multi-tenant support
- `grp_col` (string) - Group column name (default: `grp`)
- `ip_col` (string) - IP address column name (default: `ip_addr`)
- `mask_col` (string) - Mask column name (default: `mask`)
- `port_col` (string) - Port column name (default: `port`)
- `proto_col` (string) - Protocol column name (default: `proto`)
- `pattern_col` (string) - Pattern column name (default: `pattern`)
- `info_col` (string) - Info column name (default: `info`)

**Key Finding:** Table parameter is `address_table`, NOT `db_table`!

### Functions
**Status:** ✅ **VERIFIED FROM DOCUMENTATION**

**Address Permission Functions:**
- `check_address(group_id, ip, port, proto [, context_info], [pattern], [partition])` - Check specific address
- `check_source_address(group_id , [context_info], [pattern], [partition])` - Check source IP from request ⚠️ **NOT `allow_source_address()`!**
- `get_source_group(var,[partition])` - Get group ID for source address

**Routing Permission Functions:**
- `allow_routing()` - Check routing permissions (uses default files)
- `allow_routing(basename)` - Check routing permissions (uses specified files)
- `allow_register(basename)` - Check registration permissions
- `allow_uri(basename, uri)` - Check URI permissions

**Key Finding:** Function is `check_source_address()`, NOT `allow_source_address()`!

### Database Schema
**Status:** ✅ **VERIFIED FROM DOCUMENTATION**

**Table Name:** `address` (default, configurable via `address_table` parameter)

**Required Columns (with defaults):**
- `grp` (unsigned integer) - Group identifier
- `ip_addr` (string) - IP address
- `mask` (integer) - Network mask (0-32)
- `port` (integer) - Port number (0 = any port)
- `proto` (string) - Protocol (udp/tcp/tls/sctp, NULL = any)
- `pattern` (string) - Pattern matching (optional)
- `info` (string) - Additional info (optional)

**Key Features:**
- Addresses are cached in memory for performance
- Supports subnet matching (mask < 32)
- Port 0 matches any port
- Group-based access control
- Multi-tenant support via partitions

### Behavior
**Status:** ✅ **VERIFIED FROM DOCUMENTATION**

**Address Permissions:**
- Checks if IP address matches cached database entries
- Group ID determines which group to check
- Returns TRUE if address matches group, FALSE otherwise
- If no match found, request is rejected (default deny)

**File-based Permissions:**
- Uses `hosts.allow`/`hosts.deny` style files
- Supports regular expressions
- First match wins
- Non-existing files treated as empty (allows all)

**Performance:**
- Database entries cached in memory
- Two cache tables: address table (mask=32) and subnet table (mask<32)
- Can reload cache via MI command `address_reload`

**Multi-tenant Support:**
- ✅ Yes - via `partition` parameter
- Each partition has separate cache
- Partition name passed to functions

---

## Next Steps

1. Complete documentation review
2. Create test branch
3. Configure module based on actual API
4. Test functionality
5. Document results

---

**Last Updated:** January 2026  
**Status:** 🔍 **RESEARCHING** - Reviewing official documentation
