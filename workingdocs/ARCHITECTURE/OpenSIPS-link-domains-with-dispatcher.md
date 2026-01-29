# Traditional OpenSIPS Domain-Dispatcher Linking

## Overview

Traditional OpenSIPS links domains with dispatcher rows using **partitions** and database tables. Each partition acts as a logical grouping (like a domain or carrier) for dispatcher sets, and you define specific sets (rows) of destinations within those partitions, often loaded from a database (like MySQL) via the database module to route calls to different gateways or services based on domain rules, prefixes, or weights.

## Step-by-Step Process

### 1. Load the Modules

Ensure dispatcher and a database module (e.g., mysql) are loaded in your `opensips.cfg`:

```opensips
loadmodule "dispatcher.so"
loadmodule "db_mysql.so"
```

### 2. Define Partitions

Use `modparam("dispatcher", "partition", ...)` to create distinct routing areas, often named after domains or services:

```opensips
modparam("dispatcher", "partition", "voip_domain_a")
```

Partitions associate dispatcher sets with specific database tables or configurations, allowing separation for different domains, carriers, or routing scenarios.

### 3. Configure Database Tables

Set `table_name` for each partition to point to a specific database table where your destination sets (rows) are stored:

```opensips
modparam("dispatcher", "table_name", "voip_dest_table_a")
```

### 4. Populate Database

Insert destination records (IPs, ports, weights, etc.) into these database tables, each with a `setid` that links them to a specific partition and routing logic:

```sql
INSERT INTO voip_dest_table_a (setid, destination, weight, priority) 
VALUES (1, 'sip:gateway1.example.com:5060', 10, 0);
```

### 5. Use in Routing Script

In your OpenSIPS routing logic (e.g., `route[]`), use dispatcher functions like `ds_select()` to pick a destination from a specific partition and setid:

```opensips
route[DOMAIN_ROUTING] {
    if ($rd == "domain-a.com") {
        ds_select("voip_domain_a", "1", "0");
        route(RELAY);
    }
}
```

This effectively routes calls based on the domain or incoming criteria.

## Key Concepts

### Partitions

Logical containers for dispatcher sets, allowing separation for different domains, carriers, or routing scenarios. Each partition can have its own database table and routing logic.

### Sets (Rows)

A collection of destination addresses (gateways/proxies) within a partition, often defined by a `setid` and weighted for load balancing. Multiple destinations can share the same `setid` for redundancy and load distribution.

### Hashing

The dispatcher uses hash values from the SIP request (like R-URI username/host) to select a destination from the set. This ensures consistent routing for the same call while distributing load across multiple destinations.

## How It Works

By assigning different partitions and sets to different domains or call types within your routing script, you achieve:

- **Domain-specific routing:** Each domain can have its own partition with dedicated destinations
- **Load balancing:** Multiple destinations per setid distribute load
- **Carrier separation:** Different carriers can use different partitions
- **Flexible routing:** Routing logic can select partitions based on domain, prefix, or other criteria

## Comparison with Our Approach

**Traditional Approach:**
- Uses partitions to separate domains
- Each partition has its own database table
- Routing selects partition based on domain
- More complex configuration

**Our Approach:**
- Uses `domain.setid` to link domains directly to dispatcher sets
- Single dispatcher table with setid-based routing
- Simpler configuration and maintenance
- Direct domain-to-setid mapping in database

## Related Documentation

- [OpenSIPS Dispatcher Module Documentation](https://opensips.org/docs/modules/3.4.x/dispatcher.html)
- [Domain Configuration](../scripts/add-domain.sh)
- [Dispatcher Configuration](../scripts/add-dispatcher.sh)
