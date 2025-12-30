# Cloud Deployment Checklist

## Overview
This document identifies issues and recommendations for deploying OpenSIPS and Asterisk in the cloud while phones remain on-premises.

## Issues Found

### 1. Hardcoded IP Addresses in Configuration

#### Critical: `advertised_address` in `opensips.cfg.template`
- **Location:** Line 29
- **Current:** `advertised_address="198.51.100.1"`
- **Issue:** Hardcoded private IP address will not work in cloud
- **Impact:** Via headers will show incorrect address, causing routing issues
- **Fix Required:** Must be set to the cloud server's public IP address

#### Critical: Asterisk IP Check in `opensips.cfg.template`
- **Location:** Lines 663-674
- **Current:** Hardcoded check `if ($si == "10.0.1.100")`
- **Issue:** Will fail when Asterisk is in cloud with different IP
- **Impact:** SDP logging and diagnostics for Asterisk-originated calls will not work
- **Fix Required:** Make configurable or use domain-based detection

### 2. Firewall Configuration

#### Current State: `install.sh` lines 194-218
- Uses UFW (Ubuntu Firewall) which is appropriate for cloud VMs
- Opens ports: 22 (SSH), 5060 (SIP UDP/TCP), 5061 (SIP TLS), 10000-20000 (RTP)
- **Issue:** Cloud providers use Security Groups/Firewall Rules separately
- **Impact:** UFW rules alone may not be sufficient; cloud security groups must also be configured
- **Recommendation:** Document cloud security group requirements

### 3. Network Assumptions

#### Socket Binding
- **Current:** `socket=udp:0.0.0.0:5060` (line 25)
- **Status:** ✅ Correct - listens on all interfaces, works in cloud

#### NAT Traversal
- **Current:** Configuration handles NAT scenarios for endpoints
- **Issue:** When OpenSIPS is in cloud and phones are on-premises, NAT traversal becomes critical
- **Status:** Configuration already handles Contact header extraction for NAT, but may need tuning

### 4. Database Paths
- **Current:** Uses `/var/lib/opensips/routing.db`
- **Status:** ✅ No changes needed - works in cloud

## Required Changes

### Priority 1: Must Fix Before Cloud Deployment

1. **Update `advertised_address` in `opensips.cfg.template`**
   - Change from hardcoded `198.51.100.1` to configurable value
   - Options:
     a. Use environment variable substitution in install.sh
     b. Add post-install configuration step
     c. Document manual edit requirement

2. **Make Asterisk IP check configurable**
   - Remove hardcoded `10.0.1.100` check
   - Options:
     a. Use domain-based detection (check if source is from dispatcher)
     b. Make it configurable via modparam or variable
     c. Remove if not critical (it's only for logging)

### Priority 2: Documentation and Best Practices

3. **Document Cloud Security Group Requirements**
   - Create guide for AWS/Azure/GCP security group configuration
   - Document required ports and protocols

4. **Add Cloud Deployment Notes**
   - Document public IP configuration
   - Document NAT traversal considerations
   - Document firewall/security group setup

## Recommendations

### For `install.sh`:

1. **Add `--advertised-ip` parameter**
   ```bash
   --advertised-ip <IP>    Set advertised_address in OpenSIPS config
   ```

2. **Add cloud detection and warnings**
   - Detect if running in cloud (check metadata services)
   - Warn if `advertised_address` is still set to private IP
   - Provide guidance on setting public IP

3. **Add post-install verification**
   - Check if `advertised_address` is set correctly
   - Verify firewall rules are applied
   - Test SIP connectivity

### For `opensips.cfg.template`:

1. **Replace hardcoded `advertised_address`**
   - Use placeholder: `advertised_address="CHANGE_ME"`
   - Or use variable substitution: `advertised_address="${OPENSIPS_PUBLIC_IP}"`

2. **Remove or make configurable Asterisk IP check**
   - Option A: Remove entirely (logging only, not critical)
   - Option B: Use dispatcher check instead: `if (ds_is_from_list())`
   - Option C: Make configurable via modparam

3. **Add comments for cloud deployment**
   - Document that `advertised_address` must be public IP
   - Document NAT traversal considerations

## Cloud Provider Specific Considerations

### AWS EC2
- Security Groups must allow:
  - Inbound: 22/tcp (SSH), 5060/udp (SIP), 5060/tcp (SIP), 10000-20000/udp (RTP)
- Elastic IP recommended for consistent public IP
- Consider using Application Load Balancer for high availability

### Azure
- Network Security Groups must allow same ports
- Public IP address must be assigned
- Consider Azure Load Balancer for HA

### Google Cloud Platform
- Firewall rules must allow same ports
- Static external IP recommended
- Consider Cloud Load Balancing for HA

## Testing Checklist

After cloud deployment, verify:

- [ ] OpenSIPS starts successfully
- [ ] `advertised_address` is set to public IP
- [ ] Firewall/security groups allow SIP traffic
- [ ] Phones can REGISTER from on-premises
- [ ] OPTIONS messages from Asterisk reach endpoints
- [ ] INVITE messages route correctly
- [ ] RTP media flows (check NAT traversal)
- [ ] Logs show correct source IPs (not 0.0.0.0)

## Next Steps

1. Update `opensips.cfg.template` to remove hardcoded IPs
2. Update `install.sh` to support `--advertised-ip` parameter
3. Create cloud deployment guide
4. Test in cloud environment

