# SIP Edge Router Overview

**System Flow:**

![System Architecture Diagram](assets/images/SystemDiagramSBC.svg)

1. **SIP Traffic** flows from Internet endpoints through PBX3sbc (SIP Edge Router)
2. **PBX3sbc** performs domain validation, attack mitigation, and health checks
3. **SQLite Database** provides local routing lookups (sub-millisecond queries)
4. **Litestream** continuously replicates database changes to S3/MinIO
5. **SIP Signaling** is routed to healthy Asterisk/PBX3 backend nodes
6. **RTP Media** bypasses the SBC and flows directly between endpoints and Asterisk

> **Quick Installation:** This system includes an automated installer script. See [INSTALL.md](../INSTALL.md) for installation instructions, or run `sudo ./install.sh` after cloning the repository.

## What This Configuration Provides

### Core Features

- ✅ **Asterisk Protection**: Completely shielded from SIP scans
- ✅ **Tenant Routing**: Domain-based routing with multi-tenancy support
- ✅ **High Availability**: Automatic health checks and failover
- ✅ **RTP Bypass**: No RTP handling at the edge (by design)
- ✅ **Attack Mitigation**: Stateless drops for attackers
- ✅ **Scalability**: Horizontally scalable edge tier

### Installation

For installation instructions, see [INSTALL.md](../INSTALL.md). The automated installer (`install.sh`) handles all setup including dependencies, configuration, and service startup.

### Target Use Cases

This is a carrier-grade SIP edge suitable for:

- Hosted PBX services
- Multi-tenant VoIP platforms
- Internet-facing deployments
- Large Asterisk fleets

## Operational Requirements

### Asterisk Configuration

Make sure Asterisk:

- Responds to SIP OPTIONS probes
- Advertises correct public RTP IP addresses

### Firewall Configuration

- Allow SIP traffic only from Kamailio to Asterisk
- Allow RTP traffic from endpoints to Asterisk directly

### Logging

- Rate-limit logs externally if exposed to heavy attack traffic

## Future Enhancement Options

When ready for additional hardening:

- TLS-only SIP at the edge
- SRTP with selective media relay
- Active-active Kamailio with VRRP/Anycast
- Per-tenant rate limiting


## Cloud Storage Integration (S3/MinIO)

### The Core Challenge

Kamailio cannot query S3 or MinIO directly like it would MySQL/PostgreSQL because:

- S3/MinIO are object stores, not databases
- They lack low-latency query interfaces
- They don't provide transactional semantics
- Kamailio's routing logic must be extremely fast and deterministic

The design must be **read-mostly**, **cached**, and **local at runtime**.

### Architecture Pattern

**Object Store → Local Cache → Kamailio**

Think of S3/MinIO as backup store, not runtime datastore. Litestream replicates FROM local SQLite TO S3 (backup), and can restore FROM S3 TO local (recovery).



**Important:** Litestream replicates local database changes TO cloud storage (backup). Restore operations pull FROM cloud storage TO local (recovery). This is a proven carrier-grade pattern that ensures your routing database is always backed up and can be restored instantly.

## Storage Implementation

### S3/MinIO → SQLite

This is the cleanest and safest solution.

#### How It Works

1. **Store routing database as**: SQLite file (`routing.db`) with WAL mode enabled
2. **Litestream continuously replicates** WAL files to S3 or MinIO bucket
3. **Kamailio nodes**:
   - Query SQLite locally using `db_sqlite` or `sqlops`
   - Litestream runs as a background service, replicating changes in real-time
   - On restore, Litestream reconstructs the database from replicated WAL files

#### Benefits

- ✅ **Single file management** - One SQLite file contains all routing data
- ✅ **ACID transaction semantics** - Database consistency guaranteed
- ✅ **Fast local queries** - Sub-millisecond lookups, no network latency
- ✅ **Continuous, real-time backup** - Litestream replicates WAL files automatically
- ✅ **Point-in-time recovery** - Restore to any point in replication history
- ✅ **Works offline** - Routing continues even if S3/MinIO is unavailable
- ✅ **Automatic replication** - Minimal overhead, no manual intervention needed

For more information about Litestream, see the [Litestream documentation](https://litestream.io/).


## Health Check Considerations

Regardless of storage backend:

- `dispatcher` table must be local
- Health state is runtime, not persisted

**Solution:**

- Store dispatcher destinations in SQLite
- Let Kamailio manage health state in memory

## Recommended Architecture

For typical deployments (simplicity, protection, scale):

- S3 or MinIO as authoritative backup store
- SQLite DB file as runtime cache
- Litestream for continuous replication
- Dispatcher module for health-aware routing

This provides cloud-native config distribution, no live DB dependencies, extremely fast SIP routing, and predictable failure behavior.

## Failure Mode Analysis

| Failure Scenario | Result | Recovery |
|-----------------|---------|----------|
| S3 unavailable | Existing routing continues | Litestream automatically resumes replication when S3 returns |
| Bad DB pushed | Current routing unaffected | Instant restore from Litestream backup |
| Kamailio restart | Uses last known good DB | No manual intervention |
| Network outage | No routing impact | Continues with cached data, replication resumes automatically |
| Database corruption | Routing may fail | Restore from Litestream backup (point-in-time recovery available) |
| Node failure | New node can restore | Restore database from Litestream replica on new node |

This is exactly the behavior you want at the SIP edge. Litestream provides robust backup and recovery capabilities that exceed manual sync approaches.

## Critical Warning ⚠️

**Do NOT:**

- Query S3/MinIO per SIP request
- Use HTTP calls inside `request_route`
- Make Kamailio dependent on external services

*This will collapse under load.*

## SQLite Implementation Details

### Database Schema

The SQLite database uses two main tables:

#### sip_domains Table

```sql
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);

CREATE INDEX idx_sip_domains_enabled
ON sip_domains(enabled);
```

**Example data:**
- `tenant1.example.com` → `setid 10`
- `tenant2.example.com` → `setid 20`

#### dispatcher Table (Kamailio-native)

```sql
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER NOT NULL,
    destination TEXT NOT NULL,
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT
);

CREATE INDEX idx_dispatcher_setid
ON dispatcher(setid);
```

**Example destinations:**

- `setid=10` → `sip:10.0.1.10:5060` (primary Asterisk)
- `setid=10` → `sip:10.0.1.11:5060` (secondary Asterisk, same tenant)
- `setid=20` → `sip:10.0.2.20:5060` (different tenant)

*Note: Health status is not stored here - dispatcher marks nodes up/down dynamically.*

#### Performance Optimizations

Recommended SQLite PRAGMA settings for optimal performance:

```sql
-- Enable Write-Ahead Logging (required for Litestream)
PRAGMA journal_mode = WAL;

-- Balance between safety and performance
PRAGMA synchronous = NORMAL;

-- Optimize for read-heavy workloads
PRAGMA cache_size = -64000;  -- 64MB cache (adjust based on available RAM)

-- Reduce checkpoint frequency for better write performance
PRAGMA wal_autocheckpoint = 1000;

-- Optimize query planner
PRAGMA optimize;
```

**Performance considerations:**
- WAL mode enables concurrent reads while writes occur
- `NORMAL` synchronous mode provides good balance (vs `FULL` which is safer but slower)
- Cache size should be adjusted based on available memory and database size
- For more information, see [SQLite WAL documentation](https://www.sqlite.org/wal.html)

### File Layout on Kamailio Node

```
/var/lib/kamailio/
├── routing.db          # Active database (WAL mode enabled)
├── routing.db-wal      # Write-Ahead Log (replicated by Litestream)
└── routing.db-shm      # Shared memory file

/etc/
└── litestream.yml      # Litestream configuration
```

Litestream manages the replication metadata automatically. The WAL file is continuously streamed to your cloud storage backend.

### Installing Litestream

**Automated Installation (Recommended):**

If you're using the provided installer script (`install.sh`), Litestream installation is handled automatically. The installer will:
- Detect your system architecture
- Download the latest Litestream release
- Install it to `/usr/local/bin/litestream`
- Verify the installation

**Manual Installation:**

If installing manually or on macOS:

**macOS:**
```bash
# Install via Homebrew
brew install litestream

# Verify installation
litestream version
```

**Linux (Manual):**
```bash
# Check if already installed
which litestream

# Download latest release from GitHub
# Visit https://github.com/benbjohnson/litestream/releases for latest version
VERSION="v0.5.0"  # Update to latest version
ARCH="amd64"      # or "arm64"
wget https://github.com/benbjohnson/litestream/releases/download/${VERSION}/litestream-${VERSION}-linux-${ARCH}.tar.gz
tar -xzf litestream-${VERSION}-linux-${ARCH}.tar.gz
sudo mv litestream /usr/local/bin/

# Verify installation and location
litestream version
which litestream
```

**Docker:**
```bash
# Run Litestream in a container
docker run -v /var/lib/kamailio:/data \
  -v /etc/litestream.yml:/etc/litestream.yml \
  litestream/litestream:latest replicate
```

**Build from source:**
```bash
# Requires Go 1.21+
git clone https://github.com/benbjohnson/litestream.git
cd litestream
make install
```

For detailed installation instructions, see the [Litestream installation guide](https://litestream.io/install/) or use the automated installer included in this repository.

### Litestream Configuration

Create a Litestream configuration file at `/etc/litestream.yml`:

```yaml
# Litestream configuration for Kamailio routing database
# See https://litestream.io/reference/config/ for full documentation

dbs:
  - path: /var/lib/kamailio/routing.db
    replicas:
      # AWS S3 configuration
      - type: s3
        bucket: sip-routing                    # Your S3 bucket name
        path: routing.db                       # Path within bucket
        region: us-east-1                      # AWS region
        # Credentials via environment variables (recommended) or config:
        # access-key-id: YOUR_ACCESS_KEY
        # secret-access-key: YOUR_SECRET_KEY
        
      # MinIO or S3-compatible storage (uncomment and configure as needed)
      # - type: s3
      #   bucket: sip-routing
      #   path: routing.db
      #   endpoint: http://minio:9000           # MinIO endpoint
      #   access-key-id: YOUR_MINIO_ACCESS_KEY
      #   secret-access-key: YOUR_MINIO_SECRET_KEY
      #   skip-verify: true                     # Only for HTTP/self-signed certs
```

**Using environment variables** (recommended for security):

```bash
# Set AWS credentials (preferred over config file)
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_REGION=us-east-1

# Or use IAM roles (best practice on EC2)
# No environment variables needed if using IAM role
```

**Secure the configuration file:**

```bash
# Protect config file containing credentials
chmod 600 /etc/litestream.yml
chown root:root /etc/litestream.yml
```

**Note:** For production, prefer IAM roles (AWS) or environment variables over hardcoded credentials in the config file.

### Database Initialization

**Automated Initialization:**

If you're using the installer script, database initialization is handled automatically. The installer creates the database with the proper schema and permissions.

You can also use the provided helper script:

```bash
sudo ./scripts/init-database.sh
```

**Manual Initialization:**

Before starting Litestream, ensure your SQLite database exists and has WAL mode enabled:

```bash
# Create database if it doesn't exist
sqlite3 /var/lib/kamailio/routing.db <<EOF
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
-- Your schema here
CREATE TABLE sip_domains (
    domain TEXT PRIMARY KEY,
    dispatcher_setid INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    comment TEXT
);
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setid INTEGER NOT NULL,
    destination TEXT NOT NULL,
    flags INTEGER DEFAULT 0,
    priority INTEGER DEFAULT 0,
    attrs TEXT
);
EOF

# Set proper permissions
chown kamailio:kamailio /var/lib/kamailio/routing.db
chmod 644 /var/lib/kamailio/routing.db
```

### Database Update Workflow

**Important:** The routing database is typically read-only on Kamailio nodes. Updates should be made on a management/admin node to ensure consistency.

#### Recommended: Centralized Updates

This is the safest approach for production deployments:

**Using Helper Scripts:**

The repository includes helper scripts to simplify database updates:

```bash
# Add a domain
sudo ./scripts/add-domain.sh example.com 10 1 "Example tenant"

# Add dispatcher destinations
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060 0 0
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060 0 0
```

**Manual Update Process:**

1. **Update on management node:**
   ```bash
   # Create updated database (start from existing or create new)
   sqlite3 /tmp/routing.db.new <<EOF
   PRAGMA journal_mode = WAL;
   PRAGMA synchronous = NORMAL;
   
   -- Your updates here (example)
   UPDATE sip_domains SET dispatcher_setid=20 WHERE domain='example.com';
   INSERT INTO dispatcher (setid, destination, priority) 
     VALUES (20, 'sip:10.0.2.20:5060', 0);
   EOF
   ```

2. **Validate database integrity:**
   ```bash
   # Check integrity
   sqlite3 /tmp/routing.db.new "PRAGMA integrity_check;"
   
   # Verify schema
   sqlite3 /tmp/routing.db.new ".schema"
   
   # Check data counts
   sqlite3 /tmp/routing.db.new "SELECT COUNT(*) FROM sip_domains; SELECT COUNT(*) FROM dispatcher;"
   ```

3. **Deploy to nodes (atomic update):**
   ```bash
   # Copy to each Kamailio node
   for node in kamailio-node1 kamailio-node2 kamailio-node3; do
       scp /tmp/routing.db.new ${node}:/var/lib/kamailio/routing.db.new
       
       # On each node: atomic swap (no downtime)
       ssh ${node} "mv /var/lib/kamailio/routing.db.new /var/lib/kamailio/routing.db"
       
       echo "Updated ${node}"
   done
   
   # Litestream will automatically replicate the changes to S3
   ```

#### Alternative: Direct Updates (if writes are allowed)

If your setup allows writes on Kamailio nodes (not recommended for production):
- Updates happen locally via SQLite commands
- Litestream automatically replicates changes to S3
- Other nodes can restore from S3 when needed
- **Risk:** Concurrent updates can cause conflicts

#### Update via S3 (Advanced)

For cloud-native deployments, you can update via S3:

```bash
# 1. Upload updated database to S3
aws s3 cp /tmp/routing.db.new s3://sip-routing/routing.db.new

# 2. On each node, restore from S3
litestream restore -o /var/lib/kamailio/routing.db.new \
  s3://sip-routing/routing.db.new

# 3. Atomic swap
mv /var/lib/kamailio/routing.db.new /var/lib/kamailio/routing.db
```

### Restore from Backup

To restore the database from a Litestream replica (for recovery scenarios):

```bash
# Stop Litestream replication service
systemctl stop litestream

# Restore to latest (using config file - recommended)
litestream restore /var/lib/kamailio/routing.db

# Or restore from replica URL directly
litestream restore -o /var/lib/kamailio/routing.db \
  s3://sip-routing/routing.db

# Restart Litestream
systemctl start litestream
```

**Point-in-time recovery:**

```bash
# List available LTX files (generations/snapshots)
litestream ltx /var/lib/kamailio/routing.db

# Restore to specific point in time (ISO 8601 format)
litestream restore -timestamp "2024-01-15T10:30:00Z" \
  /var/lib/kamailio/routing.db

# Restore to specific generation (from ltx output)
litestream restore -generation GENERATION_ID \
  /var/lib/kamailio/routing.db
```

**Important:** Always stop Litestream before restoring, then restart it after restore completes.

*Litestream provides instant restore capabilities with point-in-time recovery. For more details, see the [Litestream restore documentation](https://litestream.io/reference/restore/).*

### Running Litestream

#### systemd Service (Recommended)

Litestream runs as a continuous service, not a periodic timer. 

**Automated Setup:**

If you're using the installer script, the systemd service is created and enabled automatically. The installer creates `/etc/systemd/system/litestream.service` with the proper configuration.

**Manual Setup:**

Create a systemd service file:

**Service configuration** (`/etc/systemd/system/litestream.service`):

```ini
[Unit]
Description=Litestream replication service for Kamailio routing database
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=kamailio
ExecStart=/usr/local/bin/litestream replicate -config /etc/litestream.yml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Environment variables (if not using config file)
# Environment="AWS_ACCESS_KEY_ID=your_access_key"
# Environment="AWS_SECRET_ACCESS_KEY=your_secret_key"
# Environment="AWS_REGION=us-east-1"

[Install]
WantedBy=multi-user.target
```

**Enable and start the service:**

```bash
# Reload systemd to recognize new service
systemctl daemon-reload

# Enable service to start on boot
systemctl enable litestream

# Start the service now
systemctl start litestream
```

**Check service status:**

```bash
# Check current status
systemctl status litestream

# View recent logs
journalctl -u litestream -n 50

# Follow logs in real-time
journalctl -u litestream -f
```

#### Manual Operation

You can also run Litestream manually for testing:

```bash
litestream replicate
```

This will run continuously until interrupted. Press `Ctrl+C` to stop.

#### Verification

Verify replication is working:

```bash
# Check replication status (should show your database)
litestream databases

# Expected output:
# /var/lib/kamailio/routing.db
#   s3://sip-routing/routing.db (replicating)

# View replication metrics (run in foreground to see activity)
# Press Ctrl+C to stop
litestream replicate -config /etc/litestream.yml

# Check that WAL files are being created
ls -lh /var/lib/kamailio/routing.db-wal
```

## Troubleshooting

### Litestream not replicating

- **Check service status:** `systemctl status litestream`
- **Verify S3 credentials and permissions:** Ensure IAM/user has write access to bucket
- **Check logs:** `journalctl -u litestream -f`
- **Verify database path matches config:** Path in `/etc/litestream.yml` must match actual database location
- **Check network connectivity:** Ensure node can reach S3/MinIO endpoint

### Database restore fails

- **Ensure database path is correct:** Use absolute paths
- **Check S3 bucket permissions:** Verify read access to replica
- **Verify replica exists:** `litestream databases` should show your database
- **Check disk space:** Ensure sufficient space for restore operation

### Kamailio can't read database

- **Check file permissions:** Kamailio user needs read access
  ```bash
  ls -l /var/lib/kamailio/routing.db
  chown kamailio:kamailio /var/lib/kamailio/routing.db
  ```
- **Verify database exists and is valid:**
  ```bash
  sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"
  ```
- **Ensure WAL mode is enabled:** Check with `sqlite3 routing.db "PRAGMA journal_mode;"`
- **Check Kamailio logs:** `journalctl -u kamailio -f` for database-related errors

### Replication lag or delays

- **Check Litestream logs** for errors or warnings
- **Verify network bandwidth** to S3/MinIO
- **Monitor WAL file size:** Large WAL files may indicate high write activity
- **Check S3/MinIO performance:** Ensure backend can handle replication rate

## Operational Guarantees

This architecture provides the following guarantees under various failure scenarios:

**Availability:**
- ✅ **No live database dependency** - Routing works offline, independent of S3/MinIO availability
- ✅ **Safe under load** - All queries are local, no network calls during SIP processing
- ✅ **Kamailio restart-safe** - Persistent local storage survives restarts

**Backup & Recovery:**
- ✅ **Continuous backup** - Real-time WAL replication via Litestream (no manual intervention)
- ✅ **Point-in-time recovery** - Restore to any point in replication history
- ✅ **Automatic replication** - Changes replicate automatically, no scheduled jobs needed

**Operational:**
- ✅ **Zero-downtime updates** - Database changes replicated automatically without service interruption
- ✅ **Cloud-native** - S3/MinIO integration for distributed backup storage
- ✅ **Resilient** - Replication resumes automatically after network outages

Designed for SIP edge routing with enterprise-grade backup and recovery capabilities. See the [Failure Mode Analysis](#failure-mode-analysis) section for detailed failure scenarios.

## Operational Best Practices

### Critical Guidelines

⚠️ **Never** edit the SQLite file in place on the Kamailio node  
⚠️ **Always** generate database elsewhere and publish it  
⚠️ **Always** ensure WAL mode is enabled (`PRAGMA journal_mode = WAL`)  
⚠️ **Always** validate before publishing changes  
⚠️ **Always** keep Litestream service running for continuous backup  

### Litestream Best Practices

- **Monitor replication**: Use `litestream databases` to verify replication status
- **Test restores**: Periodically test restore procedures to ensure backups are valid
- **Point-in-time recovery**: Litestream maintains full history, use it for recovery scenarios
- **Multiple replicas**: Configure multiple replicas for redundancy (different regions/buckets)

### Next Level Enhancements

When ready for advanced features:

- Database version table + compatibility checks
- Blue/green database promotion
- Per-tenant rate limits stored in SQLite
- Signed database files for tamper protection
- Multiple Litestream replicas for geographic redundancy
- Automated restore testing

*This design scales extremely well for enterprise deployments with Litestream providing production-grade backup and recovery.*

## Monitoring

### Key Metrics to Monitor

- **Litestream replication lag:** Check `litestream databases` output
- **Database file size:** Monitor growth over time
- **Replication errors:** Check Litestream logs regularly
- **Kamailio dispatcher health:** Monitor node availability

### Health Checks

**Using Helper Script:**

```bash
# View comprehensive status
sudo ./scripts/view-status.sh
```

**Manual Checks:**

```bash
# Check replication status
litestream databases

# Verify database integrity
sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"

# Check Kamailio dispatcher status (if kamcmd available)
kamcmd dispatcher.list

# Monitor Litestream service
systemctl status litestream
```

### Recommended Monitoring Setup

- Set up log aggregation for Litestream and Kamailio logs
- Alert on Litestream service failures
- Alert on database integrity check failures
- Monitor S3/MinIO bucket access metrics
- Track replication lag over time

## Security Considerations

- **Database permissions:** Ensure only kamailio user can read database
  ```bash
  chmod 644 /var/lib/kamailio/routing.db
  chown kamailio:kamailio /var/lib/kamailio/routing.db
  ```
- **S3 credentials:** Use IAM roles when possible (preferred over access keys)
- **Network security:** Encrypt S3/MinIO traffic (always use HTTPS/TLS)
- **Config file permissions:** Protect Litestream config containing credentials
  ```bash
  chmod 600 /etc/litestream.yml
  chown root:root /etc/litestream.yml
  ```
- **Access control:** Limit who can update the routing database
- **Database encryption:** Consider SQLite encryption extensions for sensitive routing data

## Deployment Checklist

**Quick Deployment (Using Installer):**

If using the automated installer (`install.sh`), most of these steps are handled automatically:

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
sudo ./install.sh
```

The installer will handle:
- ✅ Dependency installation
- ✅ Litestream installation
- ✅ User and directory creation
- ✅ Firewall configuration
- ✅ Litestream configuration (interactive prompts)
- ✅ Systemd service creation
- ✅ Kamailio configuration
- ✅ Database initialization
- ✅ Service startup and verification

After installation, you only need to:
- [ ] Add domains and dispatcher entries to the database
- [ ] Verify replication is working (`litestream databases`)
- [ ] Test SIP connectivity
- [ ] Configure monitoring

**Manual Deployment Checklist:**

If deploying manually, use this checklist. Complete each section before moving to the next:

### Prerequisites
- [ ] S3 bucket or MinIO bucket created
- [ ] S3/MinIO credentials configured (IAM role preferred)
- [ ] Network access to S3/MinIO endpoint verified
- [ ] Kamailio installed and configured
- [ ] SQLite3 installed (`sqlite3` command available)

### Litestream Setup
- [ ] Litestream installed (`litestream version` works)
- [ ] Litestream binary location verified (`which litestream`)
- [ ] Litestream configuration file created (`/etc/litestream.yml`)
- [ ] Configuration file permissions set (`chmod 600`)
- [ ] S3 credentials configured (environment variables or config)

### Database Setup
- [ ] SQLite database created with schema (use `scripts/init-database.sh` or manual)
- [ ] WAL mode enabled (`PRAGMA journal_mode = WAL`)
- [ ] Database permissions set (kamailio user can read)
- [ ] Database integrity verified (`PRAGMA integrity_check`)
- [ ] Initial data loaded (domains and dispatcher entries)

### Service Configuration
- [ ] Litestream systemd service file created
- [ ] Service enabled (`systemctl enable litestream`)
- [ ] Service started (`systemctl start litestream`)
- [ ] Service status verified (`systemctl status litestream`)
- [ ] Replication verified (`litestream databases`)

### Kamailio Configuration
- [ ] Kamailio configured to use SQLite database
- [ ] Database path matches Litestream config
- [ ] Dispatcher module configured
- [ ] Routing logic tested
- [ ] Kamailio service started

### Testing & Validation
- [ ] Database queries work in Kamailio
- [ ] Domain lookups function correctly
- [ ] Dispatcher routing works
- [ ] Health checks operational
- [ ] Restore procedure tested
- [ ] Monitoring configured

### Documentation
- [ ] Restore procedures documented
- [ ] Update procedures documented
- [ ] Monitoring alerts configured
- [ ] Team trained on procedures

## Multi-Node Deployment

### Deployment Architecture

For multiple Kamailio nodes, each node maintains its own local SQLite database and replicates independently to S3/MinIO:

```
Management Node          Kamailio Node 1      Kamailio Node 2      Kamailio Node N
     │                        │                    │                    │
     │ (update)               │ (read-only)         │ (read-only)         │ (read-only)
     ▼                        │                    │                    │
Local SQLite ────────────────┼────────────────────┼────────────────────┼─── Local SQLite
     │                        │                    │                    │
     │ (Litestream)           │ (Litestream)        │ (Litestream)        │ (Litestream)
     ▼                        ▼                    ▼                    ▼
  S3/MinIO ←─────────────────┴────────────────────┴────────────────────┘
  (shared backup store)
```

### Deployment Strategy

**Each Kamailio node:**
- Has its own local SQLite database (`/var/lib/kamailio/routing.db`)
- Runs Litestream independently, replicating to the same S3 bucket
- Can restore from S3 independently if needed
- Operates autonomously - no coordination required between nodes

**Database updates:**
1. Update database on management node (or any node with write access)
2. Deploy updated database to all Kamailio nodes
3. Each node's Litestream automatically replicates changes to S3
4. Nodes can restore from S3 if they miss updates

**Benefits of this approach:**
- ✅ No single point of failure
- ✅ Each node operates independently
- ✅ Automatic replication to shared backup store
- ✅ Easy to add/remove nodes
- ✅ No coordination overhead

### Node-Specific Configuration

Each node can use the same Litestream configuration, but you may want node-specific paths:

```yaml
# /etc/litestream.yml (same on all nodes)
dbs:
  - path: /var/lib/kamailio/routing.db
    replicas:
      - type: s3
        bucket: sip-routing
        path: routing.db  # Same path for all nodes (shared backup)
        region: us-east-1
```

**Alternative:** Use node-specific paths in S3 for easier tracking:

```yaml
# Node-specific S3 paths
path: routing-${HOSTNAME}.db  # Requires environment variable substitution
# Or use different configs per node
path: routing-node1.db
```

### Coordinated Updates

For coordinated database updates across all nodes:

```bash
#!/bin/bash
# deploy-routing-db.sh - Deploy updated database to all nodes

NODES=("kamailio-node1" "kamailio-node2" "kamailio-node3")
DB_FILE="/tmp/routing.db.new"

# Validate database
sqlite3 "$DB_FILE" "PRAGMA integrity_check;" | grep -q "ok" || exit 1

# Deploy to each node
for node in "${NODES[@]}"; do
    echo "Deploying to $node..."
    scp "$DB_FILE" "$node:/var/lib/kamailio/routing.db.new"
    ssh "$node" "mv /var/lib/kamailio/routing.db.new /var/lib/kamailio/routing.db"
    echo "Deployed to $node"
done

echo "Deployment complete. Litestream will replicate changes automatically."
```

## Performance Tuning

### SQLite Optimization

For high-traffic deployments, consider these optimizations:

```sql
-- Set appropriate cache size (adjust based on RAM)
PRAGMA cache_size = -128000;  -- 128MB cache

-- Optimize for read-heavy workload
PRAGMA mmap_size = 268435456;  -- 256MB memory-mapped I/O

-- Reduce checkpoint frequency
PRAGMA wal_autocheckpoint = 2000;

-- Analyze tables periodically for query optimization
ANALYZE;
```

### Litestream Tuning

Configure replication intervals in `/etc/litestream.yml`:

```yaml
dbs:
  - path: /var/lib/kamailio/routing.db
    replicas:
      - type: s3
        bucket: sip-routing
        path: routing.db
        # Replication settings
        sync-interval: 1s          # How often to sync WAL (default: 1s)
        retention: 24h             # How long to keep WAL files (default: 24h)
        retention-check-interval: 1h  # How often to check retention
```

**Tuning guidelines:**
- **sync-interval**: Lower values (1s) provide more frequent backups but more S3 API calls
- **retention**: Longer retention enables more point-in-time recovery options but uses more storage
- For read-only databases, longer sync intervals (10s-30s) are acceptable

### Database Size Considerations

- SQLite performs well up to several GB
- Monitor database growth and plan for periodic cleanup if needed
- Consider partitioning by tenant if database grows very large
- Use `VACUUM` periodically to reclaim space (requires downtime)

### Monitoring Performance

```bash
# Check database size
du -h /var/lib/kamailio/routing.db*

# Monitor WAL file size (should be small for read-only workloads)
ls -lh /var/lib/kamailio/routing.db-wal

# Check replication lag
litestream databases
```

## Final Kamailio Configuration

**Note:** If you're using the installer script, this configuration is automatically created at `/etc/kamailio/kamailio.cfg`. You can also use the template from `config/kamailio.cfg.template`.

Here's the complete, production-ready Kamailio configuration:

```kamailio
#!KAMAILIO

####### Global Parameters #########

debug=2
log_stderror=no
fork=yes
children=4

listen=udp:0.0.0.0:5060

####### Modules ########

loadmodule "sl.so"
loadmodule "tm.so"
loadmodule "rr.so"
loadmodule "pv.so"
loadmodule "xlog.so"
loadmodule "siputils.so"
loadmodule "maxfwd.so"
loadmodule "textops.so"
loadmodule "sanity.so"
loadmodule "dispatcher.so"
loadmodule "sqlops.so"
loadmodule "db_sqlite.so"

####### Module Parameters ########

# --- SQLite routing database ---
modparam("sqlops", "sqlcon",
    "cb=>sqlite:///var/lib/kamailio/routing.db")

# --- Dispatcher (health checks via SIP OPTIONS) ---
modparam("dispatcher", "db_url",
    "sqlite:///var/lib/kamailio/routing.db")

modparam("dispatcher", "ds_ping_method", "OPTIONS")
modparam("dispatcher", "ds_ping_interval", 30)
modparam("dispatcher", "ds_probing_threshold", 2)
modparam("dispatcher", "ds_inactive_threshold", 2)
modparam("dispatcher", "ds_ping_reply_codes", "200")

# --- Transaction timers ---
modparam("tm", "fr_timer", 5)
modparam("tm", "fr_inv_timer", 30)

####### Routing Logic ########

request_route {

    # ---- Basic hygiene ----
    if (!mf_process_maxfwd_header("10")) {
        sl_send_reply("483", "Too Many Hops");
        exit;
    }

    if (!sanity_check("1511", "7")) {
        xlog("L_WARN", "Malformed SIP from $si\n");
        exit;
    }

    # ---- Drop known scanners ----
    if ($ua =~ "(?i)sipvicious|friendly-scanner|sipcli|nmap") {
        exit;
    }

    # ---- In-dialog requests ----
    if (has_totag()) {
        route(WITHINDLG);
        exit;
    }

    # ---- Allowed methods only ----
    if (!is_method("REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS")) {
        sl_send_reply("405", "Method Not Allowed");
        exit;
    }

    route(DOMAIN_CHECK);
}

####### Domain validation / door-knocker protection ########

route[DOMAIN_CHECK] {

    $var(domain) = $rd;

    if ($var(domain) == "") {
        exit;
    }

    # Optional extra hardening: domain consistency
    if ($rd != $td) {
        xlog("L_WARN",
             "R-URI / To mismatch domain=$rd src=$si\n");
        exit;
    }

    # Lookup dispatcher set for this domain
    if (!sql_query("cb",
        "SELECT dispatcher_setid \
         FROM sip_domains \
         WHERE domain='$var(domain)' AND enabled=1")) {

        xlog("L_NOTICE",
             "Door-knock blocked: domain=$var(domain) src=$si\n");
        exit;
    }

    sql_result("cb", "dispatcher_setid", "$var(setid)");

    route(TO_DISPATCHER);
}

####### Health-aware routing ########

route[TO_DISPATCHER] {

    # Select a healthy Asterisk from the dispatcher set
    if (!ds_select_dst($var(setid), "4")) {
        xlog("L_ERR",
             "No healthy Asterisk nodes for domain=$rd\n");
        sl_send_reply("503", "Service Unavailable");
        exit;
    }

    record_route();

    if (!t_relay()) {
        sl_reply_error();
    }

    exit;
}

####### In-dialog handling ########

route[WITHINDLG] {

    if (loose_route()) {
        route(RELAY);
        exit;
    }

    sl_send_reply("404", "Not Here");
    exit;
}

route[RELAY] {
    if (!t_relay()) {
        sl_reply_error();
    }
    exit;
}

####### Dispatcher events (visibility) ########

event_route[dispatcher:dst-up] {
    xlog("L_INFO", "Asterisk UP: $du\n");
}

event_route[dispatcher:dst-down] {
    xlog("L_WARN", "Asterisk DOWN: $du\n");
}
```

## What This Configuration Guarantees

- ✅ **SQLite-backed routing** (safe, fast, offline-capable)
- ✅ **Litestream continuous replication** to S3/MinIO for backup and recovery
- ✅ **Door-knocker protection** stops attacks cold
- ✅ **Automatic failover** across Asterisk nodes
- ✅ **Zero RTP handling** at the edge
- ✅ **No runtime dependency** on external services
- ✅ **Horizontally scalable** SIP edge
- ✅ **Enterprise-grade backup** with point-in-time recovery via Litestream

## Additional Resources

### Installation and Setup

- **[INSTALL.md](../INSTALL.md)** - Complete installation guide with manual and automated options
- **[QUICKSTART.md](../QUICKSTART.md)** - Quick reference for common tasks
- **[README.md](../README.md)** - Project overview and quick start

### Helper Scripts

The repository includes several helper scripts in the `scripts/` directory:

- `init-database.sh` - Initialize or reset the routing database
- `add-domain.sh` - Add a domain to the routing table
- `add-dispatcher.sh` - Add a dispatcher destination
- `restore-database.sh` - Restore database from Litestream backup
- `view-status.sh` - View status of all services

### Documentation Links

- **Litestream:**
  - [Official Documentation](https://litestream.io/)
  - [Configuration Reference](https://litestream.io/reference/config/)
  - [Restore Command](https://litestream.io/reference/restore/)
  - [Installation Guide](https://litestream.io/install/)

- **Kamailio:**
  - [Dispatcher Module Documentation](https://www.kamailio.org/docs/modules/stable/modules/dispatcher.html)
  - [SQLOps Module Documentation](https://www.kamailio.org/docs/modules/stable/modules/sqlops.html)
  - [db_sqlite Module Documentation](https://www.kamailio.org/docs/modules/stable/modules/db_sqlite.html)

- **SQLite:**
  - [WAL Mode Documentation](https://www.sqlite.org/wal.html)
  - [PRAGMA Statements](https://www.sqlite.org/pragma.html)
  - [Performance Tuning](https://www.sqlite.org/performance.html)

### Getting Help

- **Litestream Issues:** [GitHub Issues](https://github.com/benbjohnson/litestream/issues)
- **Kamailio Support:** [Kamailio Community](https://www.kamailio.org/community/)
- **SQLite Support:** [SQLite Forum](https://sqlite.org/forum/)