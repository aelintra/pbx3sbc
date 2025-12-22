# Quick Installation with MinIO

This guide helps you quickly install PBX3sbc with your MinIO server at `192.168.1.173`.

## Prerequisites

- Ubuntu 20.04+ system
- Root/sudo access
- Network access to MinIO server at `192.168.1.173`
- MinIO access credentials

## Quick Installation Steps

### 1. Clone and Prepare

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
```

### 2. Run Installer

```bash
sudo ./install.sh
```

When prompted for Litestream configuration:

- **Replica type**: `minio`
- **Bucket name**: (your bucket name, e.g., `sip-routing`)
- **Path in bucket**: `routing.db` (or your preferred path)
- **MinIO endpoint**: `http://192.168.1.173:9000` (or `https://192.168.1.173:9000` if using HTTPS)
- **Access Key ID**: (your MinIO access key)
- **Secret Access Key**: (your MinIO secret key)
- **Skip TLS verify**: `y` (if using HTTP) or `n` (if using HTTPS with valid cert)

### 3. Verify Installation

```bash
# Check services
sudo systemctl status litestream
sudo systemctl status kamailio

# Check replication
litestream databases

# View status
sudo ./scripts/view-status.sh
```

### 4. Test Database Operations

```bash
# Add a test domain
sudo ./scripts/add-domain.sh test.example.com 10 1 "Test domain"

# Add a test dispatcher
sudo ./scripts/add-dispatcher.sh 10 sip:127.0.0.1:5060 0 0

# Verify in database
sudo sqlite3 /var/lib/kamailio/routing.db "SELECT * FROM sip_domains;"
```

## MinIO Configuration Details

### Pre-create Bucket (Optional)

If you want to pre-create the bucket in MinIO:

```bash
# Using MinIO client (mc)
mc alias set myminio http://192.168.1.173:9000 ACCESS_KEY SECRET_KEY
mc mb myminio/sip-routing

# Or using curl
curl -X PUT "http://192.168.1.173:9000/sip-routing" \
  -H "Authorization: AWS ACCESS_KEY:SECRET_KEY"
```

### Verify MinIO Connectivity

```bash
# Test connectivity
curl -I http://192.168.1.173:9000

# Test with credentials (if you have them)
curl -X GET "http://192.168.1.173:9000" \
  -H "Authorization: AWS ACCESS_KEY:SECRET_KEY"
```

## Troubleshooting

### MinIO Connection Issues

```bash
# Check network connectivity
ping -c 3 192.168.1.173

# Test port access
telnet 192.168.1.173 9000
# Or
nc -zv 192.168.1.173 9000
```

### Litestream Not Replicating

```bash
# Check Litestream logs
sudo journalctl -u litestream -f

# Verify configuration
cat /etc/litestream.yml

# Test replication manually
litestream replicate -config /etc/litestream.yml
```

### Common Issues

1. **"Access Denied"**: Check MinIO credentials and bucket permissions
2. **"Connection Refused"**: Verify MinIO is running and accessible
3. **"Bucket Not Found"**: Create the bucket first or check bucket name

## Post-Installation

After installation, you should:

1. Add your actual domains and dispatcher entries
2. Configure your Asterisk/PBX3 backend IPs
3. Test SIP connectivity
4. Monitor replication status
5. Set up monitoring and alerts

## Next Steps

- See [INSTALL.md](INSTALL.md) for detailed installation instructions
- See [docs/TESTING.md](docs/TESTING.md) for testing procedures
- See [docs/01-overview.md](docs/01-overview.md) for architecture details
