# PBX3sbc

Kamailio SIP Edge Router with SQLite routing database and Litestream replication for PBX3 nodes.

## Quick Start

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
sudo ./install.sh
```

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

## Features

- ✅ **Asterisk Protection**: Completely shielded from SIP scans
- ✅ **Tenant Routing**: Domain-based routing with multi-tenancy support
- ✅ **High Availability**: Automatic health checks and failover
- ✅ **RTP Bypass**: No RTP handling at the edge (by design)
- ✅ **Attack Mitigation**: Stateless drops for attackers
- ✅ **Scalability**: Horizontally scalable edge tier
- ✅ **Cloud Backup**: Litestream replication to S3/MinIO

## Documentation

- [Installation Guide](INSTALL.md) - Complete installation instructions
- [Overview Documentation](docs/01-overview.md) - Architecture and configuration details

## Project Structure

```
PBX3sbc/
├── install.sh              # Main installation script
├── INSTALL.md              # Installation guide
├── scripts/                # Helper scripts
│   ├── init-database.sh    # Initialize database
│   ├── add-domain.sh       # Add domain to routing
│   ├── add-dispatcher.sh   # Add dispatcher destination
│   ├── restore-database.sh # Restore from backup
│   └── view-status.sh      # View service status
├── config/                 # Configuration templates
│   └── kamailio.cfg.template
└── docs/                   # Documentation
    └── 01-overview.md
```

## Usage

### Add a Domain

```bash
sudo ./scripts/add-domain.sh example.com 10 1 "Example tenant"
```

### Add Dispatcher Destinations

```bash
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.10:5060 0 0
sudo ./scripts/add-dispatcher.sh 10 sip:10.0.1.11:5060 0 0
```

### View Status

```bash
sudo ./scripts/view-status.sh
```

### Restore Database

```bash
sudo ./scripts/restore-database.sh
# Or restore to specific timestamp:
sudo ./scripts/restore-database.sh "2024-01-15T10:30:00Z"
```

## Requirements

- Ubuntu 20.04 LTS or later
- Root/sudo access
- S3 bucket or MinIO instance (for backups)

## License

See [LICENSE](LICENSE) file.

## Support

For issues and questions, see the documentation in `docs/` directory.
