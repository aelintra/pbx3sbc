# Testing Setup Guide

Quick guide for testing PBX3sbc installation with MinIO at `10.0.1.173`.

## Pre-Installation Checklist

### 1. Verify MinIO Access

```bash
# Test connectivity
ping -c 3 10.0.1.173

# Test port (if nc is installed)
nc -zv 10.0.1.173 9000

# Or test with curl
curl -I http://10.0.1.173:9000
```

### 2. Prepare MinIO Bucket

You can either:
- **Option A**: Let Litestream create the bucket automatically (if MinIO allows)
- **Option B**: Pre-create the bucket using MinIO console or CLI

To pre-create using MinIO client:
```bash
# Install MinIO client (if not installed)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Configure and create bucket
mc alias set myminio http://10.0.1.173:9000 YOUR_ACCESS_KEY YOUR_SECRET_KEY
mc mb myminio/sip-routing
```

## Installation Steps

### Step 1: Clone Repository

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
```

### Step 2: Run Installer

```bash
sudo ./install.sh
```

**When prompted for Litestream configuration, use:**
- Replica type: `minio`
- Bucket name: `sip-routing` (or your preferred name)
- Path: `routing.db`
- Endpoint: `http://10.0.1.173:9000`
- Access Key ID: (your MinIO access key)
- Secret Access Key: (your MinIO secret key)
- Skip TLS verify: `y` (for HTTP)

### Step 3: Verify Installation

```bash
# Run automated tests
sudo ./test-installation.sh

# Or check manually
sudo systemctl status litestream
sudo systemctl status kamailio
litestream databases
```

### Step 4: Test Database Operations

```bash
# Initialize database (if not done during install)
sudo ./scripts/init-database.sh

# Add test data
sudo ./scripts/add-domain.sh test.example.com 10 1 "Test domain"
sudo ./scripts/add-dispatcher.sh 10 sip:127.0.0.1:5060 0 0

# Verify
sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM sip_domains;"
sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM dispatcher;"
```

### Step 5: Verify Replication

```bash
# Check replication status
litestream databases

# Check Litestream logs
sudo journalctl -u litestream -f

# Make a change and watch it replicate
sudo sqlite3 /var/lib/kamailio/routing.db "INSERT INTO sip_domains VALUES ('test2.com', 20, 1, 'Test 2');"
sleep 3
litestream databases  # Should show updated replication
```

## Quick Test Commands

```bash
# View all status
sudo ./scripts/view-status.sh

# Check services
sudo systemctl status litestream kamailio

# Check logs
sudo journalctl -u litestream -n 20
sudo journalctl -u kamailio -n 20

# Test database integrity
sudo sqlite3 /var/lib/kamailio/routing.db "PRAGMA integrity_check;"

# Test restore (if needed)
sudo ./scripts/restore-database.sh
```

## Troubleshooting

### MinIO Connection Issues

```bash
# Verify network connectivity
ping 10.0.1.173

# Check firewall (if applicable)
sudo ufw status | grep 9000

# Test MinIO endpoint
curl -v http://10.0.1.173:9000
```

### Litestream Not Replicating

1. Check configuration:
   ```bash
   sudo cat /etc/litestream.yml
   ```

2. Check logs:
   ```bash
   sudo journalctl -u litestream -n 50
   ```

3. Test manually:
   ```bash
   sudo -u kamailio litestream replicate -config /etc/litestream.yml
   ```

4. Verify credentials and bucket permissions in MinIO

### Service Issues

```bash
# Restart services
sudo systemctl restart litestream
sudo systemctl restart kamailio

# Check service status
sudo systemctl status litestream
sudo systemctl status kamailio

# View recent logs
sudo journalctl -u litestream --since "5 minutes ago"
sudo journalctl -u kamailio --since "5 minutes ago"
```

## Expected Results

After successful installation:

✅ Litestream service running and enabled  
✅ Kamailio service running and enabled  
✅ Database exists at `/var/lib/kamailio/routing.db`  
✅ Replication active (check with `litestream databases`)  
✅ Helper scripts executable and working  
✅ Configuration files in place with correct permissions  

## Next Steps After Testing

1. Add your actual domains and dispatcher entries
2. Configure real Asterisk/PBX3 backend IPs
3. Test SIP connectivity with actual endpoints
4. Set up monitoring and alerting
5. Document your specific configuration
