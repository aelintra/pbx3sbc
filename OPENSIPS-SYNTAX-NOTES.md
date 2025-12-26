# OpenSIPS Syntax Translation Notes

This document provides a quick reference for translating Kamailio syntax to OpenSIPS syntax, based on the configuration translation done for this project.

## Critical Syntax Differences

### Pseudo-Variables

| Description | Kamailio | OpenSIPS | Notes |
|-------------|----------|----------|-------|
| To header username | `$(tu{uri.user})` | `$tU` | Capital U |
| To header domain | `$td` | `$tD` | Capital D |
| To header full URI | `$tu` | `$tu` | Same |
| Request-URI username | `$(ru{uri.user})` | `$rU` | Capital U |
| Request-URI domain | `$rd` | `$rD` | Capital D |
| Request-URI full | `$ru` | `$ru` | Same |
| From username | `$(fu{uri.user})` | `$fU` | Capital U |
| From domain | `$fd` | `$fD` | Capital D |
| Source IP | `$si` | `$si` | Same |
| Source port | `$sp` | `$sp` | Same |
| Destination URI | `$du` | `$du` | Same |
| Method | `$rm` | `$rm` | Same |
| Response code | `$rs` | `$rs` | Same |
| Response reason | `$rr` | `$rr` | Same |

### String Concatenation

Both use `+` operator:
```opensips
$var(result) = $tU + "@" + $tD;
```

### Regex Matching

Both use similar syntax:
```opensips
if ($hdr(Contact) =~ "@([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})") {
    $var(ip) = $re;
}
```

### SQL Operations

**Kamailio:**
```kamailio
if (sql_query("cb", "SELECT ...", "result_name")) {
    if ($dbr(result_name=>rows) > 0) {
        $var(value) = $dbr(result_name=>[0,0]);
    }
    sql_result_free("result_name");
}
```

**OpenSIPS:**
```opensips
# Syntax is the same, but verify module compatibility
if (sql_query("cb", "SELECT ...", "result_name")) {
    if ($dbr(result_name=>rows) > 0) {
        $var(value) = $dbr(result_name=>[0,0]);
    }
    sql_result_free("result_name");
}
```

**Note:** Verify that your OpenSIPS version's SQL module supports this syntax. Some versions may use different function names.

### Module Loading

Both use similar syntax:
```opensips
loadmodule "tm.so"
loadmodule "dispatcher.so"
```

### Module Parameters

Both use similar syntax:
```opensips
modparam("tm", "fr_timer", 30)
modparam("dispatcher", "db_url", "sqlite:///path/to/db")
```

### Route Definitions

**Kamailio:**
```kamailio
request_route {
    # main routing logic
}

route[DOMAIN_CHECK] {
    # route logic
}
```

**OpenSIPS:**
```opensips
route {
    # main routing logic
}

route[DOMAIN_CHECK] {
    # route logic
}
```

### Response Handling

**Both use:**
```opensips
onreply_route {
    # response handling
}

failure_route {
    # failure handling
}
```

### Transaction Functions

Both use similar functions:
- `t_relay()` - relay request transactionally
- `t_check_trans()` - check for matching transaction
- `loose_route()` - check for Record-Route

### Dispatcher Functions

Both use:
- `ds_select_dst(setid, flags)` - select destination from dispatcher set

### Event Routes

**Kamailio:**
```kamailio
event_route[dispatcher:dst-up] {
    # handler
}
```

**OpenSIPS:**
```opensips
# May vary by version - check documentation
event_route[dispatcher:dst-up] {
    # handler
}
# OR
event_route[E_DISPATCHER_DST_UP] {
    # handler
}
```

## Common Pitfalls

### 1. Pseudo-Variable Case Sensitivity

**Wrong:**
```opensips
$var(aor) = $tu + "@" + $td;  # $td is wrong, should be $tD
```

**Correct:**
```opensips
$var(aor) = $tU + "@" + $tD;  # Capital U and D
```

### 2. Domain Extraction

**Wrong:**
```opensips
$var(domain) = $rd;  # $rd is wrong, should be $rD
```

**Correct:**
```opensips
$var(domain) = $rD;  # Capital D
```

### 3. SQL Module Name

**Kamailio:**
```kamailio
loadmodule "sqlops.so"
modparam("sqlops", "sqlcon", "...")
```

**OpenSIPS:**
```opensips
loadmodule "sql.so"  # Note: "sql" not "sqlops"
modparam("sql", "sqlcon", "...")
```

### 4. Null Checks

Both handle null checks similarly:
```opensips
if ($var(value) == $null || $var(value) == "") {
    # handle empty
}
```

## Testing Syntax

After making changes, always test:

```bash
# Check syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Common error messages:
# - "unknown pseudo-variable" → Check case (U vs u, D vs d)
# - "module not found" → Install missing module or check name
# - "unknown parameter" → Check modparam syntax for your OpenSIPS version
```

## Version-Specific Notes

OpenSIPS versions may have slight differences:

- **OpenSIPS 3.x**: Current stable, uses syntax shown above
- **OpenSIPS 2.x**: May have some differences in event route names
- **OpenSIPS 1.x**: Older syntax, may need more adjustments

Always check your specific version's documentation:
- https://www.opensips.org/Documentation

## Quick Translation Checklist

When translating Kamailio config to OpenSIPS:

- [ ] Replace `$(tu{uri.user})` with `$tU`
- [ ] Replace `$td` with `$tD`
- [ ] Replace `$(ru{uri.user})` with `$rU`
- [ ] Replace `$rd` with `$rD`
- [ ] Replace `sqlops` module with `sql` module
- [ ] Update `modparam("sqlops", ...)` to `modparam("sql", ...)`
- [ ] Verify event route names match your OpenSIPS version
- [ ] Test configuration syntax with `opensips -C`
- [ ] Verify all modules are available in your OpenSIPS installation

