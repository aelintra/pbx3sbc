# PBX3sbc

OpenSIPS SIP Edge Router with MySQL routing database for PBX3 nodes.

## Quick Start

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
sudo ./install.sh
```

See [03-Install_notes.md](03-Install_notes.md) for detailed installation instructions.

## Features

- ✅ **Asterisk Protection**: Completely shielded from SIP scans
- ✅ **Tenant Routing**: Domain-based routing with multi-tenancy support
- ✅ **High Availability**: Automatic health checks and failover
- ✅ **RTP Bypass**: No RTP handling at the edge (by design)
- ✅ **Attack Mitigation**: Stateless drops for attackers
- ✅ **Scalability**: Horizontally scalable edge tier

## Documentation

- **[Project Context](docs/PROJECT-CONTEXT.md)** - Quick start guide for understanding the project (start here!)
- [Installation Guide](03-Install_notes.md) - Complete installation instructions
- [Testing Guide](docs/TESTING.md) - How to test the installation

## Project Structure

```
PBX3sbc/
├── install.sh              # Main installation script
├── test-installation.sh    # Automated test suite
├── 03-Install_notes.md              # Installation guide
├── TESTING.md              # Testing guide
├── scripts/                # Helper scripts
│   ├── init-database.sh    # Initialize database
│   ├── add-domain.sh       # Add domain to routing
│   ├── add-dispatcher.sh   # Add dispatcher destination
│   ├── restore-database.sh # Restore from backup
│   └── view-status.sh      # View service status
├── config/                 # Configuration templates
│   └── opensips.cfg.template
└── docs/                   # Documentation
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

### Test Installation

```bash
# Run automated test suite
sudo ./test-installation.sh

# Or follow the manual testing guide
# See TESTING.md for detailed testing procedures
```

## Requirements

- Ubuntu 24.04 LTS
- Root/sudo access
- MySQL/MariaDB database server

## License

See [LICENSE](LICENSE) file.

## Support

For issues and questions, see the documentation in `docs/` directory.
