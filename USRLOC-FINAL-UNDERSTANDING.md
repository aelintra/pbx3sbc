# usrloc Module - Final Understanding

**Date:** January 2026  
**Reference:** [OpenSIPS usrloc Documentation](https://opensips.org/docs/modules/2.4.x/usrloc.html)

## Key Finding from Documentation

From the [OpenSIPS usrloc documentation](https://opensips.org/docs/modules/2.4.x/usrloc.html):

> **"The module exports no functions that could be directly used from the OpenSIPS script."**

This confirms that usrloc module itself does **not** provide script functions like `lookup()` or `save()`.

## How It Actually Works

### usrloc Module Role
- **Purpose:** Manages the location table structure and data storage
- **Provides:** Database schema, in-memory caching, expiration handling
- **Does NOT provide:** Script functions for use in OpenSIPS configuration

### registrar Module Role
- **Purpose:** Provides script functions that use usrloc's API internally
- **Provides:** `lookup()` function for querying location table
- **Provides:** `save()` function for storing registrations (if acting as registrar)

### Our Implementation

Since we're **not** acting as a full registrar (Asterisk is), we:

1. **Load both modules:**
   - `usrloc.so` - Manages location table structure
   - `registrar.so` - Provides `lookup()` function for routing

2. **Use `lookup()` for queries:**
   - `lookup("location")` comes from registrar module
   - Uses usrloc's API internally to query location table
   - Works even if we're not acting as registrar

3. **Use SQL for storage:**
   - We manually INSERT into location table via SQL
   - We don't use `save()` because we're not processing REGISTER as registrar
   - We just track endpoints for routing OPTIONS/NOTIFY back to them

## Configuration

### Modules Loaded
```opensips
loadmodule "usrloc.so"      # Manages location table
loadmodule "registrar.so"   # Provides lookup() function
```

### usrloc Parameters
```opensips
modparam("usrloc", "db_url", "sqlite:///etc/opensips/opensips.db")
modparam("usrloc", "db_mode", 2)  # Write-back mode
modparam("usrloc", "db_table", "location")
modparam("usrloc", "timer_interval", 60)
```

### registrar Parameters
```opensips
modparam("registrar", "default_expires", 3600)
modparam("registrar", "min_expires", 60)
modparam("registrar", "max_expires", 7200)
```

## How lookup() Works

1. **Set Request-URI:**
   ```opensips
   $ru = "sip:user@domain";
   ```

2. **Call lookup():**
   ```opensips
   if (lookup("location")) {
       # $du is set with contact URI (e.g., sip:user@192.168.1.100:5060)
   }
   ```

3. **Extract contact info:**
   - `$du` contains the contact URI from location table
   - Extract IP and port using regex

## Storage Approach

We use **SQL INSERT** directly to location table because:
- We're not using registrar's `save()` function
- We manually track endpoints for routing OPTIONS/NOTIFY
- SQL gives us direct control over what gets stored
- usrloc manages the table structure and expiration

## Benefits

1. **Standard Table Structure:** Uses OpenSIPS standard location table
2. **Standard Lookup Function:** Uses registrar's `lookup()` function
3. **Automatic Expiration:** usrloc handles expired entries
4. **Performance:** usrloc may cache lookups in memory
5. **Flexibility:** We control storage via SQL, use standard lookup

## References

- [OpenSIPS usrloc Module Documentation](https://opensips.org/docs/modules/2.4.x/usrloc.html)
- usrloc: Manages location table, no script functions
- registrar: Provides `lookup()` function using usrloc's API

