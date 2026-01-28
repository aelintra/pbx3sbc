# SIPp Setup Guide

**Date:** January 2026  
**Purpose:** Guide for installing and configuring SIPp for OpenSIPS testing

---

## What is SIPp?

SIPp is a free Open Source test tool/traffic generator for the SIP protocol. It's perfect for:
- Testing SIP servers (like OpenSIPS)
- Load testing
- Flood/attack simulation
- Performance testing
- Protocol compliance testing

---

## Installation Options

### Option 1: Install on Ubuntu/Debian (Recommended)

**Quick Install:**
```bash
sudo apt-get update
sudo apt-get install -y sipp
```

**Verify Installation:**
```bash
sipp -v
```

**Expected Output:**
```
SIPp v3.x.x
```

---

### Option 2: Install from Source

**If package not available or need specific version:**

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libncurses5-dev \
    libssl-dev \
    libpcap-dev \
    libsctp-dev

# Download SIPp
cd /tmp
wget https://github.com/SIPp/sipp/releases/download/v3.7.1/sipp-3.7.1.tar.gz
tar -xzf sipp-3.7.1.tar.gz
cd sipp-3.7.1

# Build
./configure --with-pcap --with-sctp
make
sudo make install

# Verify
sipp -v
```

---

### Option 3: Docker Container (Isolated Testing)

**Create Dockerfile:**
```dockerfile
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y sipp && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
CMD ["/bin/bash"]
```

**Build and Run:**
```bash
docker build -t sipp-test .
docker run -it --rm --network host sipp-test
```

**Or use pre-built image:**
```bash
docker run -it --rm --network host ctsi/sipp
```

---

## Quick Test

**Test SIPp Installation:**
```bash
# Send a single OPTIONS request
sipp -sn uac -s 40004 -m 1 <sbc-ip>:5060

# Parameters:
#   -sn uac: Use UAC (User Agent Client) scenario
#   -s 40004: SIP username
#   -m 1: Send 1 message
#   <sbc-ip>:5060: Target SIP server
```

**Expected Output:**
```
SIPp v3.x.x
...
[Success] 1 call(s) successful
```

---

## Common SIPp Commands for Testing

### Basic OPTIONS Request
```bash
sipp -sn uac -s 40004 <sbc-ip>:5060
```

### Send Multiple Requests
```bash
# Send 10 requests
sipp -sn uac -s 40004 -m 10 <sbc-ip>:5060
```

### Rapid Requests (Flood Test)
```bash
# Send 20 requests rapidly (for Pike testing)
sipp -sn uac -s 40004 -m 20 -r 20 -d 1000 <sbc-ip>:5060

# Parameters:
#   -m 20: Send 20 messages
#   -r 20: Rate of 20 messages/second
#   -d 1000: Delay 1000ms between messages
```

### REGISTER Request
```bash
sipp -sf uac/register.xml -s 40004 -m 1 <sbc-ip>:5060
```

### INVITE Request
```bash
sipp -sf uac/invite.xml -s 40004 -m 1 <sbc-ip>:5060
```

### With Authentication
```bash
sipp -sn uac -s 40004 -au 40004 -ap password <sbc-ip>:5060

# Parameters:
#   -au: Authentication username
#   -ap: Authentication password
```

### With Custom Headers
```bash
sipp -sn uac -s 40004 \
  -header "From: <sip:40004@domain.com>" \
  -header "To: <sip:40004@domain.com>" \
  <sbc-ip>:5060
```

---

## Using with Pike Test Script

**The test script (`attackTests/scripts/test-pike-module.sh`) uses SIPp:**

```bash
# Make sure SIPp is installed first
sudo apt-get install -y sipp

# Then run the test script
cd attackTests
./scripts/test-pike-module.sh <sbc-ip> 5060
```

---

## Test Environment Setup

### Option A: Separate Test Machine

**Best for:** Production-like testing

1. Set up Ubuntu VM or server
2. Install SIPp: `sudo apt-get install -y sipp`
3. Ensure network connectivity to SBC
4. Run tests from this machine

**Advantages:**
- Isolated from production
- Can simulate real attack scenarios
- Won't affect SBC performance

### Option B: Docker Container

**Best for:** Quick testing, CI/CD

```bash
# Run SIPp in Docker
docker run -it --rm --network host ctsi/sipp \
  -sn uac -s 40004 -m 20 <sbc-ip>:5060
```

**Advantages:**
- Quick setup
- Isolated environment
- Easy to clean up

### Option C: Same Server (Not Recommended)

**Only if:** No other option available

**Disadvantages:**
- May affect SBC performance
- Network traffic stays local
- Not realistic attack scenario

---

## SIPp Scenarios

SIPp comes with pre-built scenarios in `/usr/share/sipp/`:

**Common Scenarios:**
- `uac.xml` - User Agent Client (outbound calls)
- `uas.xml` - User Agent Server (inbound calls)
- `register.xml` - Registration scenario
- `invite.xml` - INVITE scenario

**Use with -sf flag:**
```bash
sipp -sf /usr/share/sipp/uac.xml -s 40004 <sbc-ip>:5060
```

---

## Advanced Usage

### Rate Limiting Test
```bash
# Send requests at specific rate
sipp -sn uac -s 40004 -m 100 -r 10 -d 100 <sbc-ip>:5060

# Sends 100 messages at 10 messages/second
```

### Burst Test
```bash
# Send burst of requests
sipp -sn uac -s 40004 -m 50 -r 50 -d 20 <sbc-ip>:5060

# Sends 50 messages rapidly (50/sec)
```

### Duration-Based Test
```bash
# Run for specific duration
sipp -sn uac -s 40004 -d 60 -timeout 60 <sbc-ip>:5060

# Runs for 60 seconds
```

### With Statistics
```bash
# Show statistics
sipp -sn uac -s 40004 -m 100 -trace_stat -stf stats.csv <sbc-ip>:5060

# Saves statistics to CSV file
```

---

## Troubleshooting

### SIPp Not Found
```bash
# Check if installed
which sipp

# If not found, install:
sudo apt-get install -y sipp
```

### Permission Denied
```bash
# SIPp may need root for some operations
sudo sipp -sn uac -s 40004 <sbc-ip>:5060
```

### No Response from Server
```bash
# Check network connectivity
ping <sbc-ip>

# Check if port is open
telnet <sbc-ip> 5060

# Check firewall rules
sudo ufw status
```

### SIPp Crashes
```bash
# Check SIPp version
sipp -v

# Try with verbose output
sipp -sn uac -s 40004 -trace_msg -trace_err <sbc-ip>:5060
```

---

## Integration with Test Scripts

**The Pike test script (`attackTests/scripts/test-pike-module.sh`) automatically uses SIPp:**

1. Checks if SIPp is installed
2. Runs automated tests
3. Saves logs for review

**Just ensure SIPp is installed:**
```bash
sudo apt-get install -y sipp
```

---

## Recommended Setup

**For Pike Module Testing:**

1. **Set up separate test machine** (VM or physical)
2. **Install SIPp:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y sipp
   ```
3. **Copy test script:**
   ```bash
   scp attackTests/scripts/test-pike-module.sh test-machine:/tmp/
   ```
4. **Run tests:**
   ```bash
   ./test-pike-module.sh <sbc-ip> 5060
   ```

---

## Alternative: Use SIPVicious

**If SIPp setup is complex, SIPVicious also works:**

```bash
# Install SIPVicious
sudo apt-get install -y sipvicious

# Run attack
svwar -e 100-200 -m INVITE <sbc-ip>:5060
```

**See:** `attackTests/docs/PIKE-TESTING-GUIDE.md` for SIPVicious examples

---

## Next Steps

1. Install SIPp on test machine
2. Verify installation: `sipp -v`
3. Run quick test: `sipp -sn uac -s 40004 -m 1 <sbc-ip>:5060`
4. Use test script: `cd attackTests && ./scripts/test-pike-module.sh <sbc-ip> 5060`
5. Or use SIPVicious if preferred

---

**Last Updated:** January 2026
