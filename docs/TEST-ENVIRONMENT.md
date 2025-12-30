# Test Environment Documentation

## Overview
This document describes the cloud-based test environment for OpenSIPS and Asterisk deployment, with phones located on-premises behind NAT.

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    On-Premises Network                      │
│                    NAT Gateway: 74.83.23.44                 │
│                                                             │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  Snom Phone  │         │ Yealink Phone│                  │
│  │   Extension  │         │  Extension   │                  │
│  │    40004     │         │    40005     │                  │
│  └──────────────┘         └──────────────┘                  │
│         │                          │                        │
│         └──────────┬─────────────────┘                      │
│                    │                                        │
│              [NAT Router]                                   │
│           74.83.23.44 (Public IP)                           │
└────────────────────┼────────────────────────────────────────┘
                     │
                     │ Internet
                     │
┌────────────────────┼─────────────────────────────────────────┐
│                    Cloud Environment                          │
│                                                               │
│  ┌──────────────────────────────────────────────┐            │
│  │         OpenSIPS SBC Server                  │            │
│  │  Hostname: pbx3sbc.vcloudpbx.com             │            │
│  │  Public IP: 34.205.252.186                   │            │
│  │  Port: 5060 (SIP UDP/TCP)                    │            │
│  └──────────────────────────────────────────────┘            │
│                    │                                          │
│                    │                                          │
│  ┌──────────────────────────────────────────────┐            │
│  │         Asterisk PBX Server                   │            │
│  │  Hostname: ael.vcloudpbx.com                  │            │
│  │  Public IP: 3.93.253.1                        │            │
│  │  Private IP: 172.31.20.123                    │            │
│  │  Port: 5060 (SIP UDP/TCP)                      │            │
│  └──────────────────────────────────────────────┘            │
└───────────────────────────────────────────────────────────────┘
```

## Component Details

### Phones (On-Premises, Behind NAT)

| Component | Extension | Type | Location | NAT Gateway |
|-----------|-----------|------|----------|-------------|
| Phone 1 | 40004 | Snom | On-Premises | 74.83.23.44 |
| Phone 2 | 40005 | Yealink | On-Premises | 74.83.23.44 |

**Network Configuration:**
- Both phones are behind the same NAT gateway
- Public NAT IP: `74.83.23.44`
- Phones register with OpenSIPS using their private IPs
- OpenSIPS tracks endpoint locations for routing

### OpenSIPS SBC Server (Cloud)

| Property | Value |
|----------|-------|
| Hostname | `pbx3sbc.vcloudpbx.com` |
| Public IP | `34.205.252.186` |
| Service | OpenSIPS SIP Edge Router |
| Ports | 5060 (SIP UDP/TCP), 5061 (SIP TLS) |
| Database | SQLite at `/var/lib/opensips/routing.db` |

**Configuration:**
- `advertised_address` must be set to: `34.205.252.186`
- Listens on all interfaces (`0.0.0.0:5060`)
- Routes SIP traffic between phones and Asterisk
- Tracks endpoint locations for direct phone-to-phone routing

**Installation:**
```bash
sudo ./install.sh --advertised-ip 34.205.252.186
```

### Asterisk PBX Server (Cloud)

| Property | Value |
|----------|-------|
| Hostname | `ael.vcloudpbx.com` |
| Public IP | `3.93.253.1` |
| Private IP | `172.31.20.123` |
| Service | Asterisk PBX |
| Port | 5060 (SIP UDP/TCP) |

**Network Configuration:**
- Has both public and private IP addresses
- Public IP: `3.93.253.1` (for external access)
- Private IP: `172.31.20.123` (for internal cloud network)
- OpenSIPS dispatcher should use the private IP for routing within cloud

**Dispatcher Configuration:**
The dispatcher entry in OpenSIPS database should use the private IP:
```sql
INSERT INTO dispatcher (setid, destination, state, weight, priority) 
VALUES (10, 'sip:172.31.20.123:5060', 0, '1', 0);
```

**Asterisk NAT Configuration:**
As documented in `docs/ASTERISK-NAT-WITH-PROXY.md`, Asterisk should use:
```
nat=force_rport
localnet=172.31.0.0/16
```

## Traffic Flows

### 1. Phone Registration (REGISTER)
```
Phone (40004/40005) → NAT (74.83.23.44) → Internet → OpenSIPS (34.205.252.186)
```
- Phone sends REGISTER to OpenSIPS
- OpenSIPS extracts Contact header and source IP
- Stores endpoint location in `endpoint_locations` table
- Forwards REGISTER to Asterisk (if needed)

### 2. Phone-to-Phone Call (Direct Routing)
```
Phone 40004 → OpenSIPS → Phone 40005
```
- OpenSIPS looks up both endpoints in `endpoint_locations` table
- Routes INVITE directly between phones (bypassing Asterisk)
- RTP flows directly between phones through NAT

### 3. Phone-to-Asterisk Call
```
Phone (40004/40005) → OpenSIPS → Asterisk (172.31.20.123)
```
- Phone sends INVITE to OpenSIPS
- OpenSIPS routes to Asterisk using dispatcher
- Asterisk processes call and routes back through OpenSIPS

### 4. Asterisk-to-Phone Call
```
Asterisk (172.31.20.123) → OpenSIPS → Phone (40004/40005)
```
- Asterisk sends INVITE to OpenSIPS
- OpenSIPS looks up endpoint location in database
- Routes to phone's registered IP (behind NAT at 74.83.23.44)

### 5. OPTIONS/NOTIFY from Asterisk
```
Asterisk (172.31.20.123) → OpenSIPS → Phone (40004/40005)
```
- Asterisk sends OPTIONS for health checks
- OpenSIPS detects Request-URI contains endpoint identifier
- Looks up endpoint location and routes to phone

## Database Configuration

### Domain Configuration
```sql
INSERT INTO sip_domains (domain, dispatcher_setid, enabled, comment) 
VALUES ('vcloudpbx.com', 10, 1, 'Cloud PBX domain');
```

### Dispatcher Configuration
```sql
INSERT INTO dispatcher (setid, destination, state, weight, priority, description) 
VALUES (10, 'sip:172.31.20.123:5060', 0, '1', 0, 'Asterisk PBX - Private IP');
```

**Note:** Use private IP (`172.31.20.123`) for dispatcher since OpenSIPS and Asterisk are in the same cloud network.

## NAT Considerations

### Phone NAT (74.83.23.44)
- Phones are behind NAT, so Contact headers may contain private IPs
- OpenSIPS uses source IP (`$si`) as primary, Contact header as fallback
- RTP must traverse NAT - phones need proper NAT traversal configuration

### Cloud Network
- OpenSIPS and Asterisk are in cloud (likely AWS based on IP ranges)
- Asterisk has both public and private IPs
- Use private IP for dispatcher (faster, no external routing)
- Public IP available for external access if needed

## Testing Scenarios

### 1. Registration Test
- Phone 40004 registers → Verify in `endpoint_locations` table
- Phone 40005 registers → Verify in `endpoint_locations` table
- Check OpenSIPS logs for successful registration

### 2. Direct Phone-to-Phone Call
- Call from 40004 to 40005
- Verify OpenSIPS routes directly (bypasses Asterisk)
- Verify audio flows in both directions

### 3. Phone-to-Asterisk Call
- Call from phone to Asterisk extension
- Verify routing through dispatcher
- Verify Asterisk processes call

### 4. Asterisk-to-Phone Call
- Call from Asterisk to phone extension
- Verify OpenSIPS looks up endpoint location
- Verify call reaches phone behind NAT

### 5. OPTIONS Health Check
- Asterisk sends OPTIONS to phone
- Verify OpenSIPS routes to phone
- Verify phone responds

## Troubleshooting

### Common Issues

1. **Registration Fails**
   - Check firewall rules (port 5060 UDP)
   - Verify `advertised_address` is set to `34.205.252.186`
   - Check OpenSIPS logs: `journalctl -u opensips -f`

2. **No Audio (One Direction)**
   - Check NAT traversal configuration in Asterisk (`nat=force_rport`)
   - Verify RTP ports are open (10000-20000 UDP)
   - Check phone NAT settings (see `docs/SNOM-AUDIO-TROUBLESHOOTING.md`)

3. **Asterisk Not Reachable**
   - Verify dispatcher entry uses correct IP (`172.31.20.123`)
   - Check cloud security groups allow traffic between OpenSIPS and Asterisk
   - Verify Asterisk is listening on port 5060

4. **Endpoint Lookup Fails**
   - Check `endpoint_locations` table has entries
   - Verify AoR format matches (user@domain)
   - Check expires timestamps are valid

## Network Security

### Firewall Rules Required

**OpenSIPS Server (34.205.252.186):**
- Inbound: 22/tcp (SSH), 5060/udp (SIP), 5060/tcp (SIP), 5061/tcp (SIP TLS)
- Outbound: All (for routing)

**Asterisk Server (3.93.253.1 / 172.31.20.123):**
- Inbound: 22/tcp (SSH), 5060/udp (SIP), 5060/tcp (SIP)
- Cloud Security Group: Allow traffic from OpenSIPS (34.205.252.186)

**Phone NAT (74.83.23.44):**
- Outbound: 5060/udp (SIP), 10000-20000/udp (RTP)
- NAT must allow return traffic

## DNS Configuration

| Hostname | IP Address | Purpose |
|----------|------------|---------|
| `pbx3sbc.vcloudpbx.com` | 34.205.252.186 | OpenSIPS SBC |
| `ael.vcloudpbx.com` | 3.93.253.1 | Asterisk PBX (public) |

**Note:** Phones should register to `pbx3sbc.vcloudpbx.com` or `34.205.252.186`

## References

- Cloud Deployment Checklist: `docs/CLOUD-DEPLOYMENT-CHECKLIST.md`
- Asterisk NAT Configuration: `docs/ASTERISK-NAT-WITH-PROXY.md`
- Snom Phone Troubleshooting: `docs/SNOM-AUDIO-TROUBLESHOOTING.md`

