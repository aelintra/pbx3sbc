# Test Deployment Checklist - Prometheus & Node Exporter

**Date:** January 2026  
**Branch:** `stats`  
**Purpose:** Checklist for testing Prometheus and Node Exporter deployment on OpenSIPS servers

---

## Pre-Deployment Verification

### 1. Verify OpenSIPS Module Availability ✅

**Check if Prometheus module is available:**

```bash
# After installation, verify modules are available
opensips -m | grep -E "(httpd|prometheus)"

# Should show:
# httpd.so
# prometheus.so
```

**If modules are missing:**

The `opensips-http-modules` package should include both `httpd` and `prometheus` modules. If not available:

```bash
# Check available OpenSIPS packages
apt-cache search opensips | grep -E "(http|prometheus)"

# May need to install additional package (verify package name)
# apt-get install opensips-prometheus-module  # If separate package exists
```

**Action:** Verify modules are available before proceeding.

---

### 2. Test Server Requirements

**Minimum Requirements:**
- Ubuntu 24.04 LTS (noble)
- AMD64 architecture
- 2GB RAM minimum (4GB recommended)
- 10GB disk space minimum
- Network access for downloading binaries

**Prerequisites:**
- OpenSIPS 3.6 installed
- MySQL/MariaDB configured
- Root/sudo access

---

## Deployment Steps

### Step 1: Run Installer

```bash
# Clone repository (if not already done)
git clone <repository-url>
cd pbx3sbc

# Checkout stats branch
git checkout stats

# Run installer (with Prometheus)
sudo ./install.sh

# Or skip Prometheus if testing separately
sudo ./install.sh --skip-prometheus
```

**Expected Output:**
- ✅ Prometheus downloaded and installed
- ✅ Node Exporter downloaded and installed
- ✅ Configuration files created
- ✅ Systemd services created
- ✅ Services enabled and started

---

### Step 2: Verify OpenSIPS Configuration

**Check OpenSIPS config:**

```bash
# Verify config syntax
sudo opensips -C -f /etc/opensips/opensips.cfg

# Should return: "config check succeeded"
```

**Verify modules are loaded:**

```bash
# Check OpenSIPS logs for module loading
sudo journalctl -u opensips -n 50 | grep -E "(httpd|prometheus)"

# Should see:
# INFO: module httpd loaded
# INFO: module prometheus loaded
```

**If modules fail to load:**

1. Check if modules exist:
   ```bash
   ls -la /usr/lib/x86_64-linux-gnu/opensips/modules/ | grep -E "(httpd|prometheus)"
   ```

2. Check OpenSIPS error logs:
   ```bash
   sudo journalctl -u opensips -n 100 | grep -i error
   ```

3. Verify package installation:
   ```bash
   dpkg -l | grep opensips-http-modules
   ```

---

### Step 3: Verify Prometheus Installation

**Check Prometheus binary:**

```bash
# Verify Prometheus is installed
prometheus --version

# Should show: prometheus, version 2.51.2 (or similar)
```

**Check Prometheus service:**

```bash
# Check service status
sudo systemctl status prometheus

# Should show: active (running)
```

**Check Prometheus configuration:**

```bash
# Validate configuration
sudo promtool check config /etc/prometheus/prometheus.yml

# Should show: SUCCESS: /etc/prometheus/prometheus.yml is valid prometheus config file syntax
```

**Check Prometheus targets:**

```bash
# Check if Prometheus can reach targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Should show:
# {
#   "job": "opensips",
#   "health": "up"
# }
# {
#   "job": "node",
#   "health": "up"
# }
```

---

### Step 4: Verify Node Exporter Installation

**Check Node Exporter binary:**

```bash
# Verify Node Exporter is installed
node_exporter --version

# Should show: node_exporter, version 1.7.0 (or similar)
```

**Check Node Exporter service:**

```bash
# Check service status
sudo systemctl status node_exporter

# Should show: active (running)
```

**Test Node Exporter metrics:**

```bash
# Fetch metrics
curl http://localhost:9100/metrics | head -20

# Should show Prometheus format metrics:
# # HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.
# # TYPE node_cpu_seconds_total counter
# node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
```

---

### Step 5: Verify OpenSIPS Metrics Endpoint

**Test OpenSIPS Prometheus endpoint:**

```bash
# Fetch OpenSIPS metrics
curl http://localhost:8888/metrics | head -30

# Should show Prometheus format metrics:
# # HELP opensips_core_rcv_requests Total requests received
# # TYPE opensips_core_rcv_requests counter
# opensips_core_rcv_requests 12345
# opensips_dialog_active_dialogs 5
# opensips_tm_active_transactions 10
```

**If endpoint is not accessible:**

1. Check OpenSIPS is running:
   ```bash
   sudo systemctl status opensips
   ```

2. Check HTTP server is listening:
   ```bash
   sudo netstat -tlnp | grep 8888
   # Should show: tcp 0.0.0.0:8888 LISTEN opensips
   ```

3. Check OpenSIPS logs:
   ```bash
   sudo journalctl -u opensips -n 50 | grep -i "http\|prometheus\|8888"
   ```

4. Verify firewall:
   ```bash
   sudo ufw status | grep 8888
   ```

---

### Step 6: Verify Prometheus Scraping

**Check Prometheus UI:**

1. Open browser: `http://<server-ip>:9090`
2. Navigate to: **Status → Targets**
3. Verify all targets show **State: UP**:
   - `opensips` (localhost:8888)
   - `node` (localhost:9100)
   - `prometheus` (localhost:9090)

**Test Prometheus queries:**

In Prometheus UI, try these queries:

```promql
# OpenSIPS metrics
opensips_core_rcv_requests
opensips_dialog_active_dialogs
opensips_tm_active_transactions

# Node metrics
node_cpu_seconds_total
node_memory_MemTotal_bytes
node_filesystem_avail_bytes
```

**Expected:** All queries should return data.

---

### Step 7: Verify Firewall Rules

**Check firewall status:**

```bash
# Check UFW status
sudo ufw status verbose

# Should show rules for:
# 9090/tcp (Prometheus)
# 9100/tcp (Node Exporter)
# 8888/tcp (OpenSIPS Prometheus)
```

**If rules are missing:**

```bash
# Add rules manually
sudo ufw allow 9090/tcp comment "Prometheus web UI"
sudo ufw allow 9100/tcp comment "Node Exporter metrics"
sudo ufw allow 8888/tcp comment "OpenSIPS Prometheus metrics"
```

---

## Post-Deployment Testing

### Test 1: Generate Some SIP Traffic

**Purpose:** Verify metrics are being collected during actual usage.

```bash
# Generate test SIP traffic (using your SIP testing tool)
# Or make a test call through the system

# Then check metrics:
curl http://localhost:8888/metrics | grep opensips_core_rcv_requests

# Should show increased values
```

### Test 2: Verify Metrics Persistence

**Purpose:** Verify Prometheus is storing historical data.

1. Wait 5-10 minutes after deployment
2. In Prometheus UI, query:
   ```promql
   opensips_core_rcv_requests[5m]
   ```
3. Should show a graph with historical data points

### Test 3: Service Restart Resilience

**Purpose:** Verify services recover after restart.

```bash
# Restart OpenSIPS
sudo systemctl restart opensips
sleep 5

# Verify metrics endpoint still works
curl http://localhost:8888/metrics | head -5

# Restart Prometheus
sudo systemctl restart prometheus
sleep 5

# Verify Prometheus UI is accessible
curl http://localhost:9090/-/healthy
```

**Expected:** All services should recover and metrics should continue.

### Test 4: Resource Usage

**Purpose:** Verify monitoring stack doesn't consume excessive resources.

```bash
# Check resource usage
ps aux | grep -E "(prometheus|node_exporter|opensips)" | grep -v grep

# Check disk usage
du -sh /var/lib/prometheus

# Check memory
free -h
```

**Expected:**
- Prometheus: ~100-200MB RAM
- Node Exporter: ~10-20MB RAM
- Disk usage: ~50-100MB per day (depends on retention)

---

## Troubleshooting

### Issue: OpenSIPS modules not loading

**Symptoms:**
- OpenSIPS starts but httpd/prometheus modules not loaded
- Error in logs: "module not found"

**Solutions:**

1. **Check package installation:**
   ```bash
   dpkg -l | grep opensips-http-modules
   ```

2. **Reinstall package:**
   ```bash
   sudo apt-get install --reinstall opensips-http-modules
   ```

3. **Check module files exist:**
   ```bash
   ls -la /usr/lib/x86_64-linux-gnu/opensips/modules/httpd.so
   ls -la /usr/lib/x86_64-linux-gnu/opensips/modules/prometheus.so
   ```

4. **Verify OpenSIPS version:**
   ```bash
   opensips -V
   # Should show: 3.6.x
   ```

---

### Issue: Prometheus can't scrape OpenSIPS

**Symptoms:**
- Prometheus target shows "DOWN"
- Error: "connection refused" or "timeout"

**Solutions:**

1. **Verify OpenSIPS is running:**
   ```bash
   sudo systemctl status opensips
   ```

2. **Check endpoint is accessible:**
   ```bash
   curl http://localhost:8888/metrics
   ```

3. **Check firewall:**
   ```bash
   sudo ufw status | grep 8888
   ```

4. **Check Prometheus config:**
   ```bash
   grep -A 5 "opensips" /etc/prometheus/prometheus.yml
   ```

5. **Check Prometheus logs:**
   ```bash
   sudo journalctl -u prometheus -n 50 | grep -i "opensips\|8888\|error"
   ```

---

### Issue: Node Exporter not accessible

**Symptoms:**
- Prometheus target shows "DOWN"
- Can't curl localhost:9100/metrics

**Solutions:**

1. **Check service status:**
   ```bash
   sudo systemctl status node_exporter
   ```

2. **Check if listening:**
   ```bash
   sudo netstat -tlnp | grep 9100
   ```

3. **Check logs:**
   ```bash
   sudo journalctl -u node_exporter -n 50
   ```

4. **Restart service:**
   ```bash
   sudo systemctl restart node_exporter
   ```

---

### Issue: High memory/disk usage

**Symptoms:**
- Prometheus using excessive memory
- Disk filling up quickly

**Solutions:**

1. **Reduce retention:**
   ```bash
   # Edit service file
   sudo systemctl edit prometheus
   
   # Add:
   [Service]
   ExecStart=
   ExecStart=/usr/local/bin/prometheus \
       --config.file=/etc/prometheus/prometheus.yml \
       --storage.tsdb.path=/var/lib/prometheus/ \
       --storage.tsdb.retention.time=7d \
       ...
   
   # Restart
   sudo systemctl daemon-reload
   sudo systemctl restart prometheus
   ```

2. **Check scrape interval:**
   ```bash
   # In prometheus.yml, increase scrape_interval:
   scrape_interval: 30s  # Instead of 15s
   ```

---

## Rollback Plan

If deployment fails or causes issues:

### 1. Disable Prometheus Collection

```bash
# Stop Prometheus
sudo systemctl stop prometheus
sudo systemctl disable prometheus

# Stop Node Exporter
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter
```

### 2. Disable OpenSIPS Prometheus Module

Edit `/etc/opensips/opensips.cfg`:

```opensips
# Comment out or remove:
# loadmodule "httpd.so"
# loadmodule "prometheus.so"
# modparam("httpd", ...)
# modparam("prometheus", ...)
```

Restart OpenSIPS:
```bash
sudo systemctl restart opensips
```

### 3. Remove Firewall Rules

```bash
# Remove rules
sudo ufw delete allow 9090/tcp
sudo ufw delete allow 9100/tcp
sudo ufw delete allow 8888/tcp
```

### 4. Uninstall (if needed)

```bash
# Stop services
sudo systemctl stop prometheus node_exporter

# Remove binaries
sudo rm /usr/local/bin/prometheus
sudo rm /usr/local/bin/promtool
sudo rm /usr/local/bin/node_exporter

# Remove configs (optional - keep for future use)
# sudo rm -rf /etc/prometheus
# sudo rm -rf /var/lib/prometheus

# Remove users (optional)
# sudo userdel prometheus
# sudo userdel node_exporter
```

---

## Success Criteria

✅ **All services running:**
- OpenSIPS: `systemctl is-active opensips`
- Prometheus: `systemctl is-active prometheus`
- Node Exporter: `systemctl is-active node_exporter`

✅ **All endpoints accessible:**
- OpenSIPS metrics: `curl http://localhost:8888/metrics` returns data
- Node Exporter: `curl http://localhost:9100/metrics` returns data
- Prometheus UI: `http://localhost:9090` accessible

✅ **All Prometheus targets UP:**
- Prometheus UI → Status → Targets shows all targets as UP

✅ **Metrics being collected:**
- Prometheus queries return data
- Historical data visible in graphs

✅ **No errors in logs:**
- `journalctl -u opensips` - no errors
- `journalctl -u prometheus` - no errors
- `journalctl -u node_exporter` - no errors

---

## Next Steps After Successful Test

1. **Deploy to additional test servers** (if multiple)
2. **Set up Grafana** (optional - see `../monitoring/PROMETHEUS-GRAFANA-PLAN.md`)
3. **Configure alerting** (optional - see Prometheus alerts.yml)
4. **Document any issues** encountered
5. **Plan production deployment**

---

## References

- **Prometheus Installation Guide:** `../monitoring/PROMETHEUS-INSTALL-UBUNTU.md`
- **Prometheus & Grafana Plan:** `../monitoring/PROMETHEUS-GRAFANA-PLAN.md`
- **Statistics Overview:** `../monitoring/STATISTICS-OVERVIEW.md`
- **OpenSIPS Prometheus Module:** https://opensips.org/docs/modules/3.6.x/prometheus.html
