# Session Summary: nat_uac_test() Implementation

## Date
January 25, 2025

## Branch
`natuactest`

## Objective
Implement `nat_uac_test()` from OpenSIPS nathelper module to replace or complement manual NAT detection using `CHECK_PRIVATE_IP` route.

## Problem
Manual NAT detection using `CHECK_PRIVATE_IP` route works but is:
- Less efficient (script-based regex vs C code)
- Less comprehensive (only checks RFC 1918 private IP ranges)
- Doesn't detect NAT scenarios with public IPs (port mismatches, received parameter mismatches)

## Solution: nat_uac_test() Implementation

### OpenSIPS 3.6.3 Syntax Requirements
**Critical Discovery**: Flags must be passed as **variables containing strings**, not raw numbers or quoted strings directly.

**Correct Syntax:**
```opensips
$var(nat_test_flags) = "31";
if (nat_uac_test($var(nat_test_flags))) {
    # NAT detected
}
```

**Incorrect Syntax (causes errors):**
- `nat_uac_test(31)` → Error: "Param [1] expected to be a string or variable"
- `nat_uac_test("31")` → Error: "Unknown flag: 31"
- `nat_uac_test("1")` → Error: "Unknown flag: 1"

### Flag Values
- **Flag 1**: Check Contact header for private IP addresses
- **Flag 2**: Check if `received` IP differs from source IP
- **Flag 4**: Check Via header for private IP addresses
- **Flag 8**: Check SDP for private IP addresses
- **Flag 16**: Check if source port differs from Via port

### Common Flag Combinations
- `"1"` = Contact header check only
- `"19"` = Contact (1) + received mismatch (2) + port mismatch (16)
- `"31"` = All checks (1+2+4+8+16) - comprehensive detection

## Implementation Locations

### 1. REGISTER Route (line ~561)
```opensips
# Detect NAT using nat_uac_test() - comprehensive test (flags 1+2+4+8+16 = 31)
$var(nat_test_flags) = "31";
if (nat_uac_test($var(nat_test_flags))) {
    xlog("REGISTER: NAT detected via nat_uac_test() - endpoint is behind NAT\n");
}
```
- Uses flag `31` for comprehensive NAT detection
- Detects NAT during registration for logging/diagnostics

### 2. CHECK_NAT_ENVIRONMENT Route (line ~1119)
```opensips
# Use nat_uac_test() for comprehensive NAT detection
# Flag 19 = 1 (Contact) + 2 (received mismatch) + 16 (port mismatch)
$var(nat_test_flags) = "19";
if (nat_uac_test($var(nat_test_flags))) {
    $var(enable_nat_fixes) = 1;
    xlog("NAT environment detected via nat_uac_test(): endpoint is behind NAT, enabling NAT fixes\n");
} else {
    # Fallback: Check source IP manually
    $var(check_ip) = $si;
    route(CHECK_PRIVATE_IP);
    if ($var(is_private) == 1) {
        $var(enable_nat_fixes) = 1;
    }
}
```
- Uses flag `19` for Contact + received mismatch + port mismatch
- Falls back to manual `CHECK_PRIVATE_IP` if `nat_uac_test()` doesn't detect NAT

### 3. Contact Header Fixing (onreply_route, line ~1520)
```opensips
# Use nat_uac_test() to detect NAT in Contact header (flag 1 = check Contact header)
if (!is_method("REGISTER") && $hdr(Contact) != "") {
    $var(nat_test_flags) = "1";
    if (nat_uac_test($var(nat_test_flags))) {
        # Fix Contact header using received field from location table
        ...
    }
}
```
- Uses flag `1` for Contact header check only
- More efficient than manual regex extraction

## Benefits

1. **Performance**: C-based detection is faster than script-based regex
2. **Comprehensiveness**: Detects NAT via port/received mismatches, not just private IPs
3. **Standard Approach**: Uses OpenSIPS's built-in NAT detection
4. **Hybrid Strategy**: `nat_uac_test()` for initial detection, `CHECK_PRIVATE_IP` as fallback

## Testing Status
✅ **Syntactically correct** - Configuration loads without errors
⏳ **Functional testing in progress** - User performing additional testing

## Commits

1. `62dcaae` - Add findings on Path headers, keepalives, and nat_uac_test()
2. `5c54041` - Implement nat_uac_test() for NAT detection optimization
3. `0447d02` - Fix parse error: correct indentation and closing brace
4. `f25ce59` - Fix nat_uac_test() flag syntax: use individual flags instead of combined
5. `adae32a` - Revert nat_uac_test() - doesn't work in OpenSIPS 3.6.3
6. `133d385` - Re-implement nat_uac_test() with numeric flags (no quotes)
7. `4391260` - Fix nat_uac_test() to use variables for flag values
8. `9685cab` - Update documentation: nat_uac_test() successfully implemented

## Key Learnings

1. **OpenSIPS 3.6.3 requires variables for flag values** - Not raw numbers or quoted strings
2. **Error messages can be misleading** - "Unknown flag" suggested named flags, but the real issue was parameter type
3. **Trial and error was necessary** - Documentation examples showed quoted strings, but actual implementation required variables
4. **Hybrid approach works best** - `nat_uac_test()` for detection, `CHECK_PRIVATE_IP` as fallback

## Related Documentation

- `ARCHITECTURE-PROXY-REGISTRAR-NAT.md` - Updated with implementation details
- OpenSIPS nathelper module documentation: https://opensips.org/docs/modules/3.6.x/nathelper.html

## Next Steps

1. Complete functional testing
2. Monitor logs for NAT detection accuracy
3. Compare performance with previous manual detection
4. Consider additional flag combinations if needed

## Notes for Next Session

- Branch: `natuactest`
- All changes committed and pushed
- Configuration is syntactically correct
- Ready for functional testing and validation
- Documentation updated in `ARCHITECTURE-PROXY-REGISTRAR-NAT.md`
