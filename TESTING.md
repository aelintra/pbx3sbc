# Testing Guide

This guide explains how to test the PBX3sbc SIP Edge Router installation and functionality.

## Prerequisites for Testing

- Ubuntu 20.04+ VM or container (recommended for isolated testing)
- Root/sudo access
- Internet connectivity
- S3 bucket or MinIO instance (for Litestream testing)
- SIP client tool (optional, for SIP testing)

## Testing Methods

### 1. Automated Testing Script

Run the provided test script to verify installation:

```bash
sudo ./test-installation.sh
```

This script checks:
- All dependencies are installed
- Services are running
- Database is accessible
- Litestream replication is working
- Configuration files are correct

### 2. Manual Testing Checklist

#### Pre-Installation Testing

**Test 1: Verify Prerequisites**
```bash
# Check Ubuntu version
lsb_release -a

# Check if running as root/sudo
sudo whoami

# Check internet connectivity
ping -c 3 8.8.8.8
```

**Test 2: Test Installer Script (Dry Run)**
```bash
# Review the installer script
cat install.sh

# Check script syntax
bash -n install.sh
```

#### Installation Testing

**Test 3: Run Installation**
```bash
# Clone the repository (if testing from scratch)
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc

# Run installer
sudo ./install.sh
```

**Test 4: Verify Installation Output**
```bash
# Check if all services are running
sudo systemctl status litestream
sudo systemctl status kamailio

# Verify Litestream installation
litestream version

# Verify Kamailio installation
kamailio -V

# Check database exists
ls -lh /var/lib/kamailio/routing.db
```

#### Post-Installation Testing

**Test 5: Database Operations**
```bash
# Test database initialization script
sudo ./scripts/init-database.sh

# Test adding a domain
sudo ./scripts/add-domain.sh test.example.com 10 1 "Test domain"

# Test adding dispatcher
sudo ./scripts/add-dispatcher.sh 10 sip:127.0.0.1:5060 0 0

# Verify data was added
sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM sip_domains;"
sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM dispatcher;"
```

**Test 6: Litestream Replication**
```bash
# Check replication status
litestream databases

# Verify replication is active
sudo journalctl -u litestream -n 20 | grep -i replicat

# Test by making a database change and checking S3
sudo sqlite3 /var/lib/kamailio/routing.db "INSERT INTO sip_domains VALUES ('test2.com', 20, 1, 'Test');"
sleep 5
litestream databases  # Should show updated replication
```

**Test 7: Service Status**
```bash
# Use the status script
sudo ./scripts/view-status.sh

# Manual service checks
sudo systemctl is-active litestream
sudo systemctl is-active kamailio
sudo systemctl is-enabled litestream
sudo systemctl is-enabled kamailio
```

**Test 8: Configuration Validation**
```bash
# Test Kamailio configuration syntax
sudo kamailio -c -f /etc/kamailio/kamailio.cfg

# Test Litestream configuration
litestream replicate -config /etc/litestream.yml -dry-run 2>&1 | head -20
```

**Test 9: Database Restore**
```bash
# Test restore functionality
sudo ./scripts/restore-database.sh

# Or test restore to specific timestamp
sudo ./scripts/restore-database.sh "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Test 10: Firewall Rules**
```bash
# Check firewall status
sudo ufw status verbose

# Verify SIP ports are open
sudo ufw status | grep 5060
sudo ufw status | grep 5061
```

#### Functional Testing

**Test 11: SIP Connectivity (if SIP client available)**
```bash
# Install SIP client (optional)
sudo apt-get install -y sip-tester

# Test SIP OPTIONS to localhost
sip_client -s sip:localhost:5060 -m OPTIONS

# Test with domain (if configured)
sip_client -s sip:test.example.com:5060 -m OPTIONS
```

**Test 12: Database Integrity**
```bash
# Check database integrity
sudo sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"

# Should return: ok
```

**Test 13: Log Verification**
```bash
# Check Kamailio logs
sudo journalctl -u kamailio -n 50

# Check Litestream logs
sudo journalctl -u litestream -n 50

# Look for errors
sudo journalctl -u kamailio --since "1 hour ago" | grep -i error
sudo journalctl -u litestream --since "1 hour ago" | grep -i error
```

### 3. Integration Testing

**Test 14: End-to-End Flow**
1. Add a test domain: `sudo ./scripts/add-domain.sh test.example.com 10 1 "Test"`
2. Add a test dispatcher: `sudo ./scripts/add-dispatcher.sh 10 sip:127.0.0.1:5060 0 0`
3. Restart Kamailio: `sudo systemctl restart kamailio`
4. Verify domain lookup works in Kamailio logs
5. Verify Litestream replicates the change

**Test 15: Failure Scenarios**
```bash
# Test service restart
sudo systemctl restart litestream
sudo systemctl restart kamailio

# Test database restore after corruption simulation
sudo cp /var/lib/kamailio/routing.db /var/lib/kamailio/routing.db.backup
sudo rm /var/lib/kamailio/routing.db
sudo ./scripts/restore-database.sh
```

### 4. Performance Testing

**Test 16: Database Query Performance**
```bash
# Time a database query
time sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM sip_domains WHERE enabled=1;"

# Should be sub-millisecond
```

**Test 17: Service Resource Usage**
```bash
# Check resource usage
systemctl status litestream | grep -A 5 "Memory\|CPU"
systemctl status kamailio | grep -A 5 "Memory\|CPU"

# Or use top/htop
top -p $(pgrep -f litestream) -p $(pgrep -f kamailio)
```

## Testing in Different Environments

### Local Development Testing

```bash
# Use a local MinIO instance
docker run -d -p 9000:9000 -p 9001:9001 \
  --name minio \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  minio/minio server /data --console-address ":9001"

# Configure Litestream to use local MinIO
# Edit /etc/litestream.yml to use endpoint: http://localhost:9000
```

### Production-Like Testing

- Use actual S3 bucket
- Test with multiple nodes
- Test failover scenarios
- Test restore procedures

## Common Issues and Solutions

### Issue: Services won't start
```bash
# Check logs
sudo journalctl -u litestream -n 50
sudo journalctl -u kamailio -n 50

# Check configuration
sudo kamailio -c -f /etc/kamailio/kamailio.cfg
litestream databases
```

### Issue: Database not accessible
```bash
# Check permissions
ls -l /var/lib/kamailio/routing.db
sudo chown kamailio:kamailio /var/lib/kamailio/routing.db

# Check integrity
sudo sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"
```

### Issue: Replication not working
```bash
# Verify S3/MinIO connectivity
# Check credentials in /etc/litestream.yml
# Test network connectivity
curl -I https://s3.amazonaws.com  # For AWS S3
```

## Automated Test Script

See `test-installation.sh` for an automated test suite that runs many of these tests.

## Next Steps After Testing

Once testing is complete:
1. Document any issues found
2. Update configuration if needed
3. Test restore procedures
4. Verify monitoring is working
5. Prepare for production deployment
