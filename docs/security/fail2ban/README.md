# Fail2ban Integration

This directory contains documentation for Fail2ban integration with PBX3sbc.

## Overview

Fail2ban provides brute force detection and IP blocking by monitoring OpenSIPS logs and automatically adding firewall rules.

## Key Documents

- **[Admin Panel Implementation](ADMIN-PANEL-IMPLEMENTATION.md)** - Complete implementation summary
- **[Admin Panel Enhancement](ADMIN-PANEL-ENHANCEMENT.md)** - Feature specifications and enhancements
- **[Deployment Decision](DEPLOYMENT-DECISION.md)** - Colocated vs remote deployment strategy
- **[Remote Management Options](REMOTE-MANAGEMENT-OPTIONS.md)** - Future SSH-based remote architecture
- **[Admin Panel Requirements](ADMIN-PANEL-REQUIREMENTS.md)** - Security requirements and setup
- **[Failed Registration Tracking](FAILED-REGISTRATION-TRACKING.md)** - Registration failure tracking comparison

## Configuration Files

Fail2ban configuration files are located in `config/fail2ban/`:

- `opensips-brute-force.conf` - Jail configuration
- `opensips-combined.conf` - Combined filter (failed registrations + door-knock)
- `opensips-failed-registrations.conf` - Failed registration filter
- `opensips-door-knock.conf` - Door-knock attempt filter

## Scripts

Management scripts are in `scripts/`:

- `sync-fail2ban-whitelist.sh` - Sync whitelist from database to Fail2ban config
- `manage-fail2ban-whitelist.sh` - Manage whitelist entries
- `setup-admin-panel-sudoers.sh` - Configure sudoers for admin panel
- `fix-duplicate-ignoreip.sh` - Fix duplicate ignoreip entries

## Related Documentation

- [Security Implementation Plan](../SECURITY-IMPLEMENTATION-PLAN.md)
- [Security Threat Detection Project](../SECURITY-THREAT-DETECTION-PROJECT.md)
