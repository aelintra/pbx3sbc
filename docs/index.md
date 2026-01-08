# PBX3sbc

## Overview

PBX3sbc is a SIP Edge Router built on Kamailio, designed to protect and route traffic to PBX3 backend nodes. It provides enterprise-grade security, high availability, and scalable multi-tenant routing with cloud-native backup capabilities.

## Key Features

- ✅ **Asterisk Protection** - Shields backend servers from SIP scans and attacks
- ✅ **Tenant Routing** - Domain-based routing with multi-tenancy support
- ✅ **High Availability** - Automatic health checks and failover
- ✅ **Cloud Backup** - Litestream replication to S3/MinIO
- ✅ **Horizontally Scalable** - Carrier-grade edge tier

## Quick Start

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
sudo ./install.sh
```

See [Installation Guide](03-Install_notes.md) for details.

## Documentation

- **[SIP Edge Router Overview](01-overview.md)** - Complete architecture and configuration guide
- **[Installation Guide](03-Install_notes.md)** - Step-by-step installation instructions
- **[Quick Start Guide](02-QUICKSTART.md)** - Quick reference for common tasks
- **[User Guide](USER-GUIDE.md)** - Control Panel User Guide (Domain Management, Dispatcher, etc.)

## Architecture

Uses a proven **Object Store → Local Cache → Kamailio** pattern with SQLite for local routing and Litestream for cloud backup.

![System Architecture Diagram](assets/images/SystemDiagramSBC.svg)

See the [Overview](01-overview.md) for detailed architecture documentation.

## Use Cases

Suitable for hosted PBX services, multi-tenant VoIP platforms, internet-facing deployments, and large Asterisk fleets. See [Overview](01-overview.md#target-use-cases) for details.

