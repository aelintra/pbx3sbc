# OpenSIPS Control Panel User Guide

## Table of Contents
1. [Domain Management](#domain-management)
2. [Dispatcher Management](#dispatcher-management) *(coming soon)*
3. [System Configuration](#system-configuration) *(coming soon)*

---

## Domain Management

### Overview

Domain management allows you to configure SIP domains that OpenSIPS recognizes as local. Each domain is associated with a **Set ID** that links it to dispatcher routing rules for backend servers.

### Key Concepts

- **Domain ID**: Auto-incrementing primary key (read-only, for reference)
- **Domain Name**: The SIP domain (FQDN or IP address)
- **Set ID**: Dispatcher set identifier for routing to backend servers
  - **Default Behavior**: If not explicitly set, Set ID defaults to match the Domain ID
  - **Explicit Setting**: Can be set to any integer value for custom routing configurations
  - This allows multiple domains to share the same dispatcher set, or to have explicit routing configurations

### Accessing Domain Management

1. Log into the OpenSIPS Control Panel
2. Navigate to: **System → Domains → Admin**

### Creating a Domain

#### Via Control Panel

1. Click the **"Add New Domain"** button
2. Fill in the form:
   - **SIP Domain**: Enter the domain name (e.g., `example.com` or `192.168.1.100`)
     - Must be a valid FQDN or IP address
   - **Set ID**: (Optional) Enter the dispatcher set ID
     - If left empty, will default to the auto-generated Domain ID
     - Use this to link multiple domains to the same dispatcher set
3. Click **"Add New Domain"** to save

#### Via Command Line

```bash
# Add domain with default Set ID (will match Domain ID)
./scripts/add-domain.sh example.com

# Add domain with explicit Set ID
./scripts/add-domain.sh example.com 10
```

#### Via MySQL

```sql
-- Add domain with explicit Set ID
INSERT INTO domain (domain, setid) VALUES ('example.com', 10);

-- Add domain with default Set ID (will match auto-generated ID)
-- Note: Set ID will be automatically set to the Domain ID after insertion
INSERT INTO domain (domain, setid) VALUES ('example.com', 0);
```

### Viewing Domains

The domain list displays:
- **ID**: Domain ID (auto-incrementing, read-only)
- **Domain Name**: The SIP domain
- **Set ID**: Dispatcher set identifier (editable)
- **Attributes**: (if enabled) Domain attributes
- **Last Modified**: Timestamp of last modification
- **Edit/Delete**: Action buttons

### Editing a Domain

1. Click the **Edit** icon (pencil) next to the domain you want to modify
2. Update the fields:
   - **SIP Domain**: Can be changed to a different domain name
   - **Set ID**: Can be changed to any integer value
     - Changing Set ID will change which dispatcher set is used for routing
   - **Attributes**: (if enabled) Can be modified
3. Click **"Save Domain"** to apply changes

**Note**: Changing the Set ID will immediately affect routing - ensure dispatcher entries exist for the new Set ID before making changes in production.

### Deleting a Domain

1. Click the **Delete** icon (trash) next to the domain you want to remove
2. Confirm the deletion
3. The domain and its routing configuration will be removed

**Warning**: Deleting a domain will break routing for that domain. Ensure you have updated all dispatcher entries and routing rules before deleting.

### Set ID Behavior

#### Default Behavior (Fallback)

When adding a domain without explicitly setting the Set ID:
- Set ID is initially set to `0`
- The system automatically updates it to match the Domain ID
- This provides backward compatibility and a sensible default

**Example:**
```sql
-- Domain created with ID = 5
-- If Set ID not provided, it becomes 5 (matches Domain ID)
```

#### Explicit Set ID

You can explicitly set the Set ID to:
- Link multiple domains to the same dispatcher set
- Use custom numbering schemes
- Maintain stable Set IDs even if Domain IDs change

**Example:**
```sql
-- Multiple domains sharing Set ID 10
INSERT INTO domain (domain, setid) VALUES ('domain1.com', 10);
INSERT INTO domain (domain, setid) VALUES ('domain2.com', 10);
INSERT INTO domain (domain, setid) VALUES ('domain3.com', 10);

-- All three domains will use dispatcher entries with setid = 10
```

### Best Practices

1. **Use Explicit Set IDs**: For production systems, explicitly set Set IDs to ensure consistent routing even if domains are recreated
2. **Document Set IDs**: Keep track of which Set IDs map to which backend server groups
3. **Test Before Production**: Always test domain and Set ID changes in a test environment first
4. **Reload After Changes**: After adding/modifying domains via MySQL or scripts, use the **"Reload on Server"** button in the control panel to refresh OpenSIPS routing tables

### Common Tasks

#### Linking Multiple Domains to One Backend

1. Create dispatcher entries with a specific Set ID (e.g., `10`)
2. Add multiple domains, all with Set ID `10`
3. All domains will route to the same backend servers

#### Changing Domain Routing

1. Edit the domain
2. Change the Set ID to point to a different dispatcher set
3. Save the changes
4. Click **"Reload on Server"** to apply changes immediately

#### Migrating Domain Routing

1. Create new dispatcher entries with a new Set ID
2. Test the new routing configuration
3. Update domain Set ID to the new value
4. Verify routing works correctly
5. Remove old dispatcher entries if no longer needed

### Troubleshooting

#### Domain Not Routing Correctly

- Verify the Set ID matches an existing dispatcher set
- Check dispatcher entries: `SELECT * FROM dispatcher WHERE setid = <your-setid>;`
- Use **"Reload on Server"** button to refresh OpenSIPS routing tables
- Check OpenSIPS logs: `journalctl -u opensips -f`

#### Set ID Not Showing Correct Value

- If Set ID shows `0`, it should automatically update to match Domain ID
- Refresh the page to see updated values
- Check database directly: `SELECT id, domain, setid FROM domain;`

#### Cannot Edit Domain

- Ensure you're logged in with appropriate permissions
- Check that the domain exists in the database
- Verify database connectivity from the control panel

### Related Operations

After configuring domains, you'll typically need to:
1. Configure dispatcher entries for each Set ID (see Dispatcher Management)
2. Reload OpenSIPS domain table: Use **"Reload on Server"** button
3. Test routing with SIP clients or test tools

---

## Dispatcher Management

*Coming soon - documentation for configuring backend servers and routing destinations*

---

## System Configuration

*Coming soon - documentation for system-level configuration and settings*

