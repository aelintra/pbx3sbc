# Prometheus Installation Guide - Ubuntu 24.04 AMD64

**Date:** January 2026  
**Purpose:** Step-by-step installation and configuration of Prometheus using Debian package on Ubuntu 24.04 AMD64

## Overview

This guide covers installing Prometheus from the official Debian package repository for Ubuntu 24.04 on AMD64 processors, configuring it to scrape OpenSIPS metrics, and setting it up as a systemd service.

---

## Prerequisites

- Ubuntu 24.04 LTS (AMD64)
- Root or sudo access
- OpenSIPS with Prometheus module configured (see `PROMETHEUS-GRAFANA-PLAN.md`)
- Network access to download packages

---

## Installation Steps

### Step 1: Add Prometheus Repository

The official Prometheus Debian packages are available from the Prometheus repository.

```bash
# Update package list
sudo apt-get update

# Install prerequisites
sudo apt-get install -y wget curl gnupg2 software-properties-common

# Add Prometheus repository GPG key
wget -q -O - https://prometheus.io/downloads/prometheus/release.gpg | sudo apt-key add -

# Add Prometheus repository
# Note: Prometheus doesn't have official Ubuntu 24.04 packages yet
# We'll use the Debian repository or download directly
```

**Alternative: Direct Download (Recommended for Ubuntu 24.04)**

Since Prometheus may not have official Ubuntu 24.04 packages, we'll download the Debian package directly:

```bash
# Create Prometheus user and directories
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

# Download Prometheus (check latest version at https://prometheus.io/download/)
cd /tmp
PROMETHEUS_VERSION="2.51.2"  # Update to latest version
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

# Extract
tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
cd prometheus-${PROMETHEUS_VERSION}.linux-amd64

# Copy binaries
sudo cp prometheus /usr/local/bin/
sudo cp promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool

# Copy configuration files
sudo cp -r consoles /etc/prometheus
sudo cp -r console_libraries /etc/prometheus
sudo chown -R prometheus:prometheus /etc/prometheus/consoles
sudo chown -R prometheus:prometheus /etc/prometheus/console_libraries
```

### Step 2: Create Prometheus Configuration

**File:** `/etc/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s      # Scrape targets every 15 seconds
  evaluation_interval: 15s   # Evaluate rules every 15 seconds
  external_labels:
    cluster: 'pbx3sbc'
    environment: 'production'

# Alertmanager configuration (optional - configure if using Alertmanager)
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load alert rules
rule_files:
  - "alerts.yml"

# Scrape configurations
scrape_configs:
  # OpenSIPS statistics (from Prometheus module)
  - job_name: 'opensips'
    static_configs:
      - targets: ['localhost:8888']  # OpenSIPS HTTP endpoint (Prometheus module)
    scrape_interval: 15s
    metrics_path: '/metrics'
    scrape_timeout: 10s
    # Optional: Add labels
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: 'opensips-sbc'

  # Node Exporter (system metrics - CPU, memory, disk, network)
  # Required for Grafana OpenSIPS dashboard template
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']  # Node Exporter default port
    scrape_interval: 15s
    metrics_path: '/metrics'
    scrape_timeout: 10s

  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

**File:** `/etc/prometheus/alerts.yml`

```yaml
groups:
  - name: opensips_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(opensips_core_drop_requests[5m]) / rate(opensips_core_rcv_requests[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      - alert: NoActiveDestinations
        expr: opensips_dispatcher_active_destinations == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "No active dispatcher destinations"
          description: "All Asterisk backends are down"

      - alert: HighActiveTransactions
        expr: opensips_tm_active_transactions > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of active transactions"
          description: "Active transactions: {{ $value }}"

      - alert: HighActiveDialogs
        expr: opensips_dialog_active_dialogs > 500
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of active dialogs"
          description: "Active dialogs: {{ $value }}"
```

**Set permissions:**
```bash
sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
sudo chown prometheus:prometheus /etc/prometheus/alerts.yml
```

### Step 3: Create Systemd Service

**File:** `/etc/systemd/system/prometheus.service`

```ini
[Unit]
Description=Prometheus Monitoring System
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --storage.tsdb.retention.time=30d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.enable-lifecycle

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Service Configuration Notes:**
- `--storage.tsdb.retention.time=30d` - Keep data for 30 days (adjust as needed)
- `--web.listen-address=0.0.0.0:9090` - Listen on all interfaces
- `--web.enable-lifecycle` - Enable reload API endpoint

**Enable and start service:**
```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable Prometheus to start on boot
sudo systemctl enable prometheus

# Start Prometheus
sudo systemctl start prometheus

# Check status
sudo systemctl status prometheus
```

### Step 4: Configure Firewall (if using UFW)

```bash
# Allow Prometheus web UI (port 9090)
sudo ufw allow 9090/tcp comment 'Prometheus web UI'

# Verify
sudo ufw status
```

### Step 5: Verify Installation

**1. Check Service Status:**
```bash
sudo systemctl status prometheus
```

**2. Check Prometheus Web UI:**
```bash
# Access in browser
http://localhost:9090

# Or via curl
curl http://localhost:9090/-/healthy
```

**3. Verify Metrics Collection:**
```bash
# Check if Prometheus can scrape OpenSIPS
# In Prometheus UI, go to Status → Targets
# Should show opensips target as UP

# Or query via API
curl http://localhost:9090/api/v1/targets
```

**4. Test Query:**
```bash
# Query OpenSIPS metrics
curl 'http://localhost:9090/api/v1/query?query=opensips_core_rcv_requests'

# Should return JSON with metric values
```

### Step 6: Configure Logging

**Optional: Configure log rotation**

**File:** `/etc/logrotate.d/prometheus`

```
/var/log/prometheus/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 prometheus prometheus
    sharedscripts
    postrotate
        systemctl reload prometheus > /dev/null 2>&1 || true
    endscript
}
```

---

## Node Exporter Installation

**Purpose:** Node Exporter provides system-level metrics (CPU, memory, disk, network) required by Grafana OpenSIPS dashboard templates.

**Why Needed:**
- Grafana OpenSIPS dashboard templates (e.g., Dashboard ID 6935) expect node_exporter metrics
- Provides system resource monitoring (CPU, memory, disk I/O, network)
- Complements OpenSIPS application metrics with host-level metrics

### Step 1: Install Node Exporter

```bash
# Create node_exporter user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Download Node Exporter (check latest version at https://prometheus.io/download/)
cd /tmp
NODE_EXPORTER_VERSION="1.7.0"  # Update to latest version
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Extract
tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
cd node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64

# Copy binary
sudo cp node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

### Step 2: Create Systemd Service

**File:** `/etc/systemd/system/node_exporter.service`

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=0.0.0.0:9100 \
    --collector.filesystem.mount-points-exclude="^/(sys|proc|dev|host|etc)($$|/)"

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable and start service:**
```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable Node Exporter to start on boot
sudo systemctl enable node_exporter

# Start Node Exporter
sudo systemctl start node_exporter

# Check status
sudo systemctl status node_exporter
```

### Step 3: Configure Firewall

```bash
# Allow Node Exporter (port 9100)
sudo ufw allow 9100/tcp comment 'Node Exporter metrics'

# Verify
sudo ufw status
```

### Step 4: Verify Node Exporter

```bash
# Test metrics endpoint
curl http://localhost:9100/metrics

# Should return Prometheus format metrics:
# node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
# node_memory_MemTotal_bytes 8589934592
# node_filesystem_size_bytes{device="/dev/sda1",fstype="ext4",mountpoint="/"} 107374182400
# etc.
```

### Step 5: Update Prometheus Configuration

The Prometheus configuration already includes node_exporter scrape target (see Step 2 above).

**Verify Prometheus can scrape:**
```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="node")'

# Should show node_exporter as UP
```

### Node Exporter Metrics Provided

**CPU Metrics:**
- `node_cpu_seconds_total` - CPU time spent in each mode (user, system, idle, etc.)
- `node_load1`, `node_load5`, `node_load15` - System load averages

**Memory Metrics:**
- `node_memory_MemTotal_bytes` - Total memory
- `node_memory_MemAvailable_bytes` - Available memory
- `node_memory_MemFree_bytes` - Free memory
- `node_memory_Cached_bytes` - Cached memory

**Disk Metrics:**
- `node_filesystem_size_bytes` - Filesystem size
- `node_filesystem_avail_bytes` - Available space
- `node_filesystem_used_bytes` - Used space
- `node_disk_io_time_seconds_total` - Disk I/O time
- `node_disk_read_bytes_total` - Disk read bytes
- `node_disk_written_bytes_total` - Disk written bytes

**Network Metrics:**
- `node_network_receive_bytes_total` - Network bytes received
- `node_network_transmit_bytes_total` - Network bytes transmitted
- `node_network_receive_packets_total` - Network packets received
- `node_network_transmit_packets_total` - Network packets transmitted

**Process Metrics:**
- `node_processes_total` - Total processes
- `node_procs_running` - Running processes
- `node_procs_blocked` - Blocked processes

**System Metrics:**
- `node_boot_time_seconds` - System boot time
- `node_time_seconds` - Current time
- `node_uname_info` - System information

### Why Node Exporter is Required

**Grafana OpenSIPS Dashboard Requirements:**
- **System Resource Panels:** CPU usage, memory usage, disk I/O
- **Network Traffic:** Network bytes in/out, packet rates
- **Host Health:** System load, process counts
- **Capacity Planning:** Disk usage, memory trends

**Without Node Exporter:**
- Grafana dashboard panels for system metrics will be empty
- Cannot monitor host-level resource usage
- Cannot correlate OpenSIPS performance with system resources

---

## Configuration Details

### Data Retention

**Default:** 30 days (configured in systemd service)

**To change retention:**
1. Edit `/etc/systemd/system/prometheus.service`
2. Modify `--storage.tsdb.retention.time=30d` (e.g., `15d`, `90d`, `1y`)
3. Reload: `sudo systemctl daemon-reload && sudo systemctl restart prometheus`

**Storage Calculation:**
- Approximately 1-2 bytes per sample
- With 15s scrape interval: ~5,760 samples/day/metric
- Estimate: ~1-2 GB per 1000 metrics for 30 days

### Reload Configuration Without Restart

Prometheus supports configuration reload via API:

```bash
# Reload configuration
curl -X POST http://localhost:9090/-/reload

# Note: Requires --web.enable-lifecycle flag (already enabled)
```

**To reload after editing config:**
```bash
# Edit /etc/prometheus/prometheus.yml
sudo nano /etc/prometheus/prometheus.yml

# Reload (no restart needed)
curl -X POST http://localhost:9090/-/reload
```

### Backup Configuration

**Backup Prometheus configuration:**
```bash
# Create backup directory
sudo mkdir -p /backup/prometheus

# Backup config
sudo cp /etc/prometheus/prometheus.yml /backup/prometheus/prometheus.yml.$(date +%Y%m%d)
sudo cp /etc/prometheus/alerts.yml /backup/prometheus/alerts.yml.$(date +%Y%m%d)
```

---

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u prometheus -n 50
```

**Common issues:**
1. **Permission errors:** Ensure `/var/lib/prometheus` owned by prometheus user
2. **Port already in use:** Check if port 9090 is available: `sudo netstat -tlnp | grep 9090`
3. **Config syntax error:** Validate config: `promtool check config /etc/prometheus/prometheus.yml`

### Prometheus Can't Scrape OpenSIPS

**Verify OpenSIPS metrics endpoint:**
```bash
# Test OpenSIPS metrics endpoint
curl http://localhost:8888/metrics

# Should return Prometheus format metrics
```

**Check Prometheus targets:**
```bash
# In Prometheus UI: Status → Targets
# Or via API
curl http://localhost:9090/api/v1/targets | jq
```

**Common issues:**
1. **OpenSIPS not running:** Check OpenSIPS status
2. **Wrong port:** Verify OpenSIPS httpd port (default: 8888)
3. **Firewall blocking:** Check firewall rules
4. **Prometheus module not enabled:** Verify OpenSIPS config

### High Memory Usage

**Monitor Prometheus resource usage:**
```bash
# Check memory
ps aux | grep prometheus

# Check disk usage
du -sh /var/lib/prometheus
```

**Reduce retention if needed:**
- Edit systemd service: `--storage.tsdb.retention.time=15d`
- Restart: `sudo systemctl restart prometheus`

---

## Integration with OpenSIPS and Node Exporter

### Verify OpenSIPS Configuration

Ensure OpenSIPS Prometheus module is configured (see `docs/PROMETHEUS-GRAFANA-PLAN.md`):

```opensips
# In opensips.cfg.template
loadmodule "httpd.so"
modparam("httpd", "socket", "http:0.0.0.0:8888")

loadmodule "prometheus.so"
modparam("prometheus", "root", "metrics")
modparam("prometheus", "prefix", "opensips")
modparam("prometheus", "group_mode", 1)
modparam("prometheus", "statistics", "core:")
modparam("prometheus", "statistics", "tm:")
modparam("prometheus", "statistics", "dialog:")
modparam("prometheus", "statistics", "dispatcher:")
```

### Test Integration

```bash
# 1. Verify OpenSIPS metrics endpoint
curl http://localhost:8888/metrics | head -20

# 2. Verify Node Exporter metrics endpoint
curl http://localhost:9100/metrics | head -20

# 3. Verify Prometheus can scrape both
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job=="opensips" or .job=="node")'

# 4. Query OpenSIPS metrics in Prometheus
curl 'http://localhost:9090/api/v1/query?query=opensips_core_rcv_requests'

# 5. Query Node Exporter metrics in Prometheus
curl 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total'
curl 'http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes'
```

---

## Security Considerations

### 1. Restrict Web UI Access

**Option A: Firewall Rules**
```bash
# Only allow localhost access
sudo ufw delete allow 9090/tcp
sudo ufw allow from 127.0.0.1 to any port 9090
```

**Option B: Reverse Proxy (Recommended)**
- Use Nginx/Apache as reverse proxy
- Add authentication
- Use HTTPS

**Option C: Change Listen Address**
```ini
# In /etc/systemd/system/prometheus.service
--web.listen-address=127.0.0.1:9090  # Only localhost
```

### 2. File Permissions

```bash
# Ensure proper ownership
sudo chown -R prometheus:prometheus /etc/prometheus
sudo chown -R prometheus:prometheus /var/lib/prometheus
sudo chmod 640 /etc/prometheus/prometheus.yml
sudo chmod 640 /etc/prometheus/alerts.yml
```

### 3. Network Security

- Don't expose Prometheus to public internet
- Use firewall rules to restrict access
- Consider VPN or SSH tunnel for remote access

---

## Maintenance

### Regular Tasks

**1. Monitor Disk Usage:**
```bash
# Check Prometheus data directory
du -sh /var/lib/prometheus

# Check system disk usage
df -h
```

**2. Review Logs:**
```bash
# Check recent logs
sudo journalctl -u prometheus -n 100

# Check for errors
sudo journalctl -u prometheus -p err
```

**3. Update Prometheus:**
```bash
# Download new version
cd /tmp
PROMETHEUS_VERSION="2.52.0"  # Update version
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

# Stop service
sudo systemctl stop prometheus

# Backup current binary
sudo cp /usr/local/bin/prometheus /usr/local/bin/prometheus.backup

# Extract and copy new binary
tar xvf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
sudo cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus

# Start service
sudo systemctl start prometheus

# Verify
sudo systemctl status prometheus
```

---

## Quick Reference

### Service Management

```bash
# Start
sudo systemctl start prometheus

# Stop
sudo systemctl stop prometheus

# Restart
sudo systemctl restart prometheus

# Status
sudo systemctl status prometheus

# Enable on boot
sudo systemctl enable prometheus

# Disable on boot
sudo systemctl disable prometheus

# Reload config (no restart)
curl -X POST http://localhost:9090/-/reload
```

### Configuration Files

**Prometheus:**
- **Main Config:** `/etc/prometheus/prometheus.yml`
- **Alert Rules:** `/etc/prometheus/alerts.yml`
- **Service File:** `/etc/systemd/system/prometheus.service`
- **Data Directory:** `/var/lib/prometheus/`
- **Logs:** `journalctl -u prometheus`

**Node Exporter:**
- **Service File:** `/etc/systemd/system/node_exporter.service`
- **Binary:** `/usr/local/bin/node_exporter`
- **Logs:** `journalctl -u node_exporter`

### Useful Commands

```bash
# Validate config
promtool check config /etc/prometheus/prometheus.yml

# Check Prometheus health
curl http://localhost:9090/-/healthy

# List targets (should show opensips and node)
curl http://localhost:9090/api/v1/targets | jq

# Query OpenSIPS metrics
curl 'http://localhost:9090/api/v1/query?query=opensips_core_rcv_requests' | jq

# Query Node Exporter metrics
curl 'http://localhost:9090/api/v1/query?query=node_cpu_seconds_total' | jq
curl 'http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes' | jq

# Check versions
prometheus --version
node_exporter --version
```

### Node Exporter Service Management

```bash
# Start
sudo systemctl start node_exporter

# Stop
sudo systemctl stop node_exporter

# Restart
sudo systemctl restart node_exporter

# Status
sudo systemctl status node_exporter

# Enable on boot
sudo systemctl enable node_exporter

# Disable on boot
sudo systemctl disable node_exporter
```

---

## Next Steps

After Prometheus and Node Exporter are installed and configured:

1. **Verify OpenSIPS Integration** - Ensure OpenSIPS metrics are being collected
2. **Verify Node Exporter Integration** - Ensure system metrics are being collected
3. **Install Grafana** - See `PROMETHEUS-GRAFANA-PLAN.md` for Grafana setup
4. **Import Grafana Dashboard** - Use OpenSIPS dashboard template (ID 6935) which requires both OpenSIPS and Node Exporter metrics
5. **Create Custom Dashboards** - Build additional visualization dashboards
6. **Configure Alerting** - Set up Alertmanager (optional)

---

## References

- **Prometheus Documentation:** https://prometheus.io/docs/
- **Prometheus Downloads:** https://prometheus.io/download/
- **Node Exporter Documentation:** https://github.com/prometheus/node_exporter
- **Node Exporter Downloads:** https://prometheus.io/download/#node_exporter
- **OpenSIPS Prometheus Module:** https://opensips.org/docs/modules/3.6.x/prometheus.html
- **Prometheus Configuration:** https://prometheus.io/docs/prometheus/latest/configuration/configuration/
- **Grafana OpenSIPS Dashboard:** https://grafana.com/grafana/dashboards/6935-opensips/

---

**Last Updated:** January 2026  
**Tested On:** Ubuntu 24.04 LTS (AMD64)  
**Prometheus Version:** 2.51.2 (update to latest as needed)  
**Node Exporter Version:** 1.7.0 (update to latest as needed)

## Summary

This guide covers:
- ✅ Prometheus installation and configuration
- ✅ Node Exporter installation and configuration (required for Grafana dashboards)
- ✅ Integration with OpenSIPS Prometheus module
- ✅ Systemd service setup for both services
- ✅ Firewall configuration
- ✅ Verification and troubleshooting

**Both Prometheus and Node Exporter are required** for complete monitoring:
- **Prometheus:** Collects and stores metrics
- **OpenSIPS Prometheus Module:** Provides OpenSIPS application metrics
- **Node Exporter:** Provides system-level metrics (CPU, memory, disk, network)
- **Grafana:** Visualizes metrics from both sources
