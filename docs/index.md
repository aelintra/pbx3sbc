# PBX3sbc

## Overview

PBX3sbc is a SIP Edge Router built on OpenSIPS, designed to protect and route traffic to PBX3 backend nodes. It provides enterprise-grade security, high availability, and scalable multi-tenant routing with cloud-native backup capabilities.

## Key Features

- ✅ **Asterisk Protection** - Shields backend servers from SIP scans and attacks
- ✅ **Tenant Routing** - Domain-based routing with multi-tenancy support
- ✅ **High Availability** - Automatic health checks and failover
- ✅ **Horizontally Scalable** - Carrier-grade edge tier

## Quick Start

```bash
git clone https://github.com/your-org/PBX3sbc.git
cd PBX3sbc
sudo ./install.sh
```

See [Installation Guide](03-Install_notes.md) for details.

## Documentation

- **[Project Context](PROJECT-CONTEXT.md)** - ⭐ **Start here!** Quick guide to understand the project architecture, key decisions, and current state
- **[Installation Guide](03-Install_notes.md)** - Step-by-step installation instructions
- **[Quick Start Guide](02-QUICKSTART.md)** - Quick reference for common tasks
- **[User Guide](USER-GUIDE.md)** - Control Panel User Guide (Domain Management, Dispatcher, etc.)

## Architecture

Uses OpenSIPS with MySQL routing database for reliable multi-tenant SIP edge routing.

![System Architecture Diagram](assets/images/SystemDiagramSBC.svg)


## Use Cases

Suitable for hosted PBX services, multi-tenant VoIP platforms, internet-facing deployments, and large Asterisk fleets.

