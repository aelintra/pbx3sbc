# Installation Guide

This guide will help you install and configure the Kamailio SIP Edge Router with SQLite routing database and Litestream replication.

## Prerequisites

- Ubuntu 20.04 LTS or later (other Debian-based distributions may work)
- Root or sudo access
- Internet connectivity
- S3 bucket or MinIO instance for backups (optional but recommended)

## Quick Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-org/PBX3sbc.git
   cd PBX3sbc
   ```

2. **Run the installer:**
   ```bash
   sudo ./install.sh
   ```

The installer will:
- Install all required dependencies (Kamailio, SQLite, Litestream, etc.)
- Create necessary users and directories
- Configure firewall rules
- Set up Litestream for database replication
- Create and initialize the routing database
- Configure and start all services

## Installation Options

The installer supports several options:

```bash
# Skip dependency installation (if already installed)
sudo ./install.sh --skip-deps

# Skip firewall configuration
sudo ./install.sh --skip-firewall

# Skip database initialization
sudo ./install.sh --skip-db

# Combine options
sudo ./install.sh --skip-deps --skip-firewall
```

## Manual Installation Steps

If you prefer to install manually or need to customize the installation:

### 1. Install Dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
    kamailio \
    kamailio-sqlite-modules \
    sqlite3 \
    curl \
    wget \
    ufw \
    jq
```

### 2. Install Litestream

```bash
# Download latest version
VERSION="0.5.0"  # Update to latest
ARCH="amd64"     # or "arm64"
wget https://github.com/benbjohnson/litestream/releases/download/v${VERSION}/litestream-v${VERSION}-linux-${ARCH}.tar.gz
tar -xzf litestream-v${VERSION}-linux-${ARCH}.tar.gz
sudo mv litestream /usr/local/bin/
chmod +x /usr/local/bin/litestream
```

### 3. Create User and Directories

```bash
sudo useradd -r -s /bin/false -d /var/run/kamailio -c "Kamailio SIP Server" kamailio
sudo mkdir -p /var/lib/kamailio /var/log/kamailio /var/run/kamailio
sudo chown -R kamailio:kamailio /var/lib/kamailio /var/log/kamailio /var/run/kamailio
```

### 4. Configure Litestream

Create `/etc/litestream.yml`:

```yaml
dbs:
  - path: /var/lib/kamailio/routing.db
    replicas:
      - type: s3
        bucket: your-bucket-name
        path: routing.db
        region: us-east-1
        # Or use IAM role (recommended)
```

### 5. Initialize Database

```bash
sudo ./scripts/init-database.sh
```

### 6. Configure Kamailio

Copy the configuration template:

```bash
sudo cp config/kamailio.cfg.template /etc/kamailio/kamailio.cfg
```

### 7. Start Services

```bash
sudo systemctl enable litestream
sudo systemctl enable kamailio
sudo systemctl start litestream
sudo systemctl start kamailio
```

## Post-Installation Configuration

### 1. Add Domains and Dispatcher Entries

Use the provided scripts or SQLite directly:

```bash
# Add a domain
sudo ./scripts/add-domain.sh example.com 10 1 "Example tenant"

# Add dispatcher destinations
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060 0 0
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060 0 0
```

Or use SQLite directly:

```bash
sudo sqlite3 /var/lib/kamailio/routing.db
```

```sql
-- Add domain
INSERT INTO sip_domains (domain, dispatcher_setid, enabled, comment)
VALUES ('example.com', 10, 1, 'Example tenant');

-- Add dispatcher destinations
INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.10:5060', 0, 0);

INSERT INTO dispatcher (setid, destination, flags, priority)
VALUES (10, 'sip:10.0.1.11:5060', 0, 0);
```

### 2. Verify Installation

Check service status:

```bash
sudo ./scripts/view-status.sh
```

Or manually:

```bash
sudo systemctl status kamailio
sudo systemctl status litestream
sudo litestream databases
```

### 3. Test SIP Connectivity

Use a SIP client tool to test (optional):

```bash
# Install a SIP testing tool (choose one):
# Option 1: sipsak (recommended)
sudo apt-get install sipsak
sipsak -s sip:your-domain.com -H your-domain.com

# Option 2: sipp (for more advanced testing)
sudo apt-get install sipp
sipp -sf uac.xml your-domain.com

# Option 3: sip-tester (if available in your repository)
# sudo apt-get install sip-tester
```

## Firewall Configuration

The installer automatically configures UFW with:
- SSH (port 22)
- SIP UDP/TCP (port 5060)
- SIP TLS (port 5061)
- RTP range (ports 10000-20000)

To manually configure:

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 5060/udp  # SIP UDP
sudo ufw allow 5060/tcp  # SIP TCP
sudo ufw allow 5061/tcp  # SIP TLS
sudo ufw allow 10000:20000/udp  # RTP range
sudo ufw enable
```

## S3/MinIO Configuration

### AWS S3

1. Create an S3 bucket
2. Configure IAM role (recommended) or access keys
3. Update `/etc/litestream.yml` with bucket name and region

### MinIO

1. Set up MinIO instance
2. Create bucket
3. Update `/etc/litestream.yml`:

```yaml
dbs:
  - path: /var/lib/kamailio/routing.db
    replicas:
      - type: s3
        bucket: sip-routing
        path: routing.db
        endpoint: http://minio:9000
        access-key-id: YOUR_ACCESS_KEY
        secret-access-key: YOUR_SECRET_KEY
        skip-verify: true  # For HTTP
```

## Troubleshooting

### Services Not Starting

Check logs:

```bash
sudo journalctl -u kamailio -f
sudo journalctl -u litestream -f
```

### Database Issues

Verify database integrity:

```bash
sudo sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"
```

### Replication Not Working

Check Litestream status:

```bash
sudo litestream databases
sudo journalctl -u litestream -n 50
```

Verify S3/MinIO connectivity and credentials.

### Kamailio Not Routing

Check configuration:

```bash
sudo kamailio -c  # Check config syntax
sudo kamailio -C -f /etc/kamailio/kamailio.cfg  # Dry run
```

View logs:

```bash
sudo tail -f /var/log/kamailio/kamailio.log
```

## Helper Scripts

The repository includes several helper scripts in the `scripts/` directory:

- `init-database.sh` - Initialize or reset the database
- `add-domain.sh` - Add a domain to the routing table
- `add-dispatcher.sh` - Add a dispatcher destination
- `restore-database.sh` - Restore database from Litestream backup
- `view-status.sh` - View status of all services

## Uninstallation

To remove the installation:

```bash
# Stop services
sudo systemctl stop kamailio
sudo systemctl stop litestream

# Disable services
sudo systemctl disable kamailio
sudo systemctl disable litestream

# Remove services
sudo rm /etc/systemd/system/litestream.service

# Remove configuration (optional)
sudo rm -rf /etc/kamailio
sudo rm /etc/litestream.yml

# Remove data (WARNING: This deletes your database!)
sudo rm -rf /var/lib/kamailio

# Remove user (optional)
sudo userdel kamailio

# Uninstall packages (optional)
sudo apt-get remove kamailio kamailio-* sqlite3
```

## Support

For issues and questions:
- Check the documentation in `docs/01-overview.md`
- Review logs: `journalctl -u kamailio` and `journalctl -u litestream`
- Check the [Kamailio documentation](https://www.kamailio.org/docs/)
- Check the [Litestream documentation](https://litestream.io/)
