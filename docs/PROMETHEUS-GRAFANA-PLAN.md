# Prometheus & Grafana Deployment Plan

**Date:** January 2026  
**Branch:** `stats`  
**Purpose:** Plan deployment of Prometheus and Grafana for OpenSIPS statistics collection and visualization

## Overview

Deploy Prometheus and Grafana to collect, store, and visualize OpenSIPS real-time statistics that are currently ephemeral (available via Management Interface but not persisted).

**✅ AUTOMATED INSTALLATION:** Prometheus and Node Exporter installation is **fully automated** via the `install.sh` script. No manual installation steps required! See [Phase 1](#phase-1-opensips-prometheus-module-configuration--automated) and [Phase 3](#phase-3-prometheus-server--node-exporter-deployment--automated) for details.

## Goals

1. **Persist Real-Time Statistics** - Store OpenSIPS MI statistics in time-series database
2. **Historical Analysis** - Enable trending and historical analysis of performance metrics
3. **Real-Time Dashboards** - Visualize current system state and performance
4. **Alerting** - Alert on performance issues, errors, and thresholds
5. **Integration** - Integrate with existing monitoring infrastructure

---

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   OpenSIPS      │         │  Node Exporter  │
│   (SBC)         │         │                 │
│                 │         │  System Metrics │
│  Prometheus     │         │  (CPU, Memory,  │
│  Module         │         │   Disk, Network)│
│  (Built-in)     │         │                 │
│                 │         │  HTTP Endpoint  │
│  HTTP Endpoint  │         │  /metrics       │
│  /metrics       │         └────────┬────────┘
└────────┬────────┘                  │
         │                           │
         │ HTTP GET                  │ HTTP GET
         │ (Prometheus format)       │ (Prometheus format)
         │                           │
         └───────────┬───────────────┘
                     │
                     ▼
         ┌─────────────────┐
         │   Prometheus    │
         │   Server        │
         │                 │
         │  - Scrapes      │
         │    both sources │
         │  - Time-series  │
         │    database     │
         │  - Stores       │
         │    metrics      │
         └────────┬────────┘
                  │
                  │ Queries
                  │
                  ▼
         ┌─────────────────┐
         │    Grafana      │
         │                 │
         │  - Dashboards   │
         │  - Visualization│
         │  - Alerting     │
         └─────────────────┘
```

**Architecture Notes:**
- OpenSIPS exposes application metrics via built-in Prometheus module
- Node Exporter exposes system metrics (required for Grafana dashboards)
- Prometheus scrapes both sources
- Grafana visualizes combined metrics

---

## Components Required

### 1. OpenSIPS Prometheus Module Configuration

**Status:** ✅ Built-in to OpenSIPS 3.6

**Reference:** [OpenSIPS 3.6 Prometheus Module](https://opensips.org/docs/modules/3.6.x/prometheus.html)

**Configuration Needed:**
- Enable `httpd` module (required dependency)
- Enable `prometheus` module
- Configure which statistics to export
- Set up HTTP endpoint

**File:** `config/opensips.cfg.template`

```opensips
####### HTTP Server (Required for Prometheus) ########
loadmodule "httpd.so"
modparam("httpd", "socket", "http:0.0.0.0:8888")  # Default port 8888

####### Prometheus Module ########
loadmodule "prometheus.so"

# Metrics endpoint path (default: /metrics)
modparam("prometheus", "root", "metrics")

# Metric prefix (default: opensips)
modparam("prometheus", "prefix", "opensips")

# Group mode: 1 = include group in metric name (e.g., opensips_core_rcv_requests)
modparam("prometheus", "group_mode", 1)

# Export statistics - two approaches:

# Approach 1: Group-based (exports all stats in each group) - CURRENT CONFIGURATION
modparam("prometheus", "statistics", "core:")       # All core statistics
modparam("prometheus", "statistics", "tm:")         # All transaction statistics
modparam("prometheus", "statistics", "dialog:")    # All dialog statistics
modparam("prometheus", "statistics", "dispatcher:") # All dispatcher statistics

# Approach 2: Specific statistics only (uncomment to use instead)
# Useful for reducing metric volume or focusing on specific metrics
# modparam("prometheus", "statistics", "core:rcv_requests core:rcv_replies core:drop_requests")
# modparam("prometheus", "statistics", "tm:active_transactions tm:transactions")
# modparam("prometheus", "statistics", "dialog:active_dialogs dialog:early_dialogs")
# modparam("prometheus", "statistics", "dispatcher:active_destinations dispatcher:inactive_destinations")

# Approach 3: Mixed (specific stats + groups) - Example from OpenSIPS docs
# modparam("prometheus", "statistics", "active_dialogs load: stats:")

# Or export ALL statistics (uncomment to enable - exports everything)
# modparam("prometheus", "statistics", "all")
# Note: If "all" is specified, other statistics parameters are ignored
```

**Access:**
- Prometheus metrics available at: `http://localhost:8888/metrics`
- Standard Prometheus format
- No custom exporter needed!

### 2. OpenSIPS Prometheus Module ✅ **BUILT-IN**

**Excellent News:** OpenSIPS 3.6 includes a **built-in Prometheus module** that exports statistics directly!

**Reference:** [OpenSIPS 3.6 Prometheus Module Documentation](https://opensips.org/docs/modules/3.6.x/prometheus.html)

**Benefits:**
- ✅ **No custom exporter needed** - Built into OpenSIPS
- ✅ **Direct HTTP endpoint** - Exposes `/metrics` endpoint via httpd module
- ✅ **Native integration** - Uses OpenSIPS statistics directly
- ✅ **Configurable** - Can select which statistics to export
- ✅ **Custom metrics** - Supports custom statistics via script routes

**Requirements:**
- `prometheus` module (built-in to OpenSIPS 3.6)
- `httpd` module (required dependency)
- HTTP interface enabled

**Configuration:** Configure in `opensips.cfg.template` - no separate exporter needed!

### 3. Prometheus Server

**Purpose:** Time-series database for storing metrics

**Deployment Options:**
- **Native (Recommended):** Install via Debian package on Ubuntu 24.04 AMD64
  - **See:** `docs/PROMETHEUS-INSTALL-UBUNTU.md` for detailed installation guide
- **Docker:** `prom/prometheus` container (alternative)
- **Kubernetes:** If using K8s (future)

**Configuration:** `prometheus.yml`

### 4. Node Exporter ⚠️ **REQUIRED FOR GRAFANA DASHBOARDS**

**Purpose:** Provides system-level metrics (CPU, memory, disk, network) required by Grafana OpenSIPS dashboard templates

**Why Required:**
- Grafana OpenSIPS dashboard templates (e.g., Dashboard ID 6935) expect node_exporter metrics
- Provides system resource monitoring (CPU, memory, disk I/O, network)
- Complements OpenSIPS application metrics with host-level metrics

**Metrics Provided:**
- CPU usage (`node_cpu_seconds_total`)
- Memory usage (`node_memory_*`)
- Disk I/O (`node_disk_*`)
- Network traffic (`node_network_*`)
- System load (`node_load*`)
- Process counts (`node_procs_*`)

**Installation:** See `docs/PROMETHEUS-INSTALL-UBUNTU.md` for Node Exporter installation guide

### 5. Grafana

**Purpose:** Visualization and dashboards

**Deployment Options:**
- **Local:** Install on OpenSIPS server (same node)
- **Cloud:** Deploy to cloud infrastructure (separate server)
- **Docker:** `grafana/grafana` container (works for both local and cloud)
- **Native:** Install via package manager (works for both local and cloud)
- **Kubernetes:** If using K8s (future)

**Configuration:** Dashboards, datasources, alerting rules

**Dashboard Templates:**
- **OpenSIPS Dashboard (ID 6935):** https://grafana.com/grafana/dashboards/6935-opensips/
  - Requires both OpenSIPS metrics (from Prometheus module) AND Node Exporter metrics
  - Provides comprehensive OpenSIPS and system monitoring

---

## Grafana Deployment Decision: Local vs Cloud

### Overview

Grafana can be deployed either:
1. **Locally** - On the same server as OpenSIPS (co-located)
2. **Cloud** - On a separate cloud server or infrastructure

Both approaches have trade-offs. This section provides arguments for and against each approach to help make an informed decision.

---

### Option 1: Local Deployment (On OpenSIPS Node)

**Deployment:** Grafana runs on the same server as OpenSIPS

#### ✅ Arguments FOR Local Deployment

**1. Simplicity & Ease of Setup**
- ✅ Single server to manage
- ✅ No network configuration between Grafana and Prometheus
- ✅ Easier initial deployment
- ✅ Fewer moving parts
- ✅ Simpler troubleshooting (everything in one place)

**2. Performance & Latency**
- ✅ **Low latency** - Queries to Prometheus are localhost (sub-millisecond)
- ✅ **No network overhead** - No bandwidth usage for monitoring queries
- ✅ **Faster dashboard loading** - Direct connection to Prometheus
- ✅ **Real-time responsiveness** - Instant query execution

**3. Cost**
- ✅ **No additional hosting costs** - Uses existing OpenSIPS server
- ✅ **No cloud service fees** - No monthly cloud hosting charges
- ✅ **Lower total cost of ownership** - Single server infrastructure

**4. Network Independence**
- ✅ **Works offline** - Monitoring available even if external network is down
- ✅ **No internet dependency** - Doesn't require internet connectivity
- ✅ **Internal monitoring** - All monitoring traffic stays on-premises

**5. Data Privacy & Security**
- ✅ **Data stays on-premises** - No data leaves your infrastructure
- ✅ **Reduced attack surface** - No cloud endpoint to secure
- ✅ **Compliance friendly** - Easier to meet data residency requirements
- ✅ **No cloud provider access** - Complete control over data

**6. Operational Benefits**
- ✅ **Single point of management** - One server to monitor and maintain
- ✅ **Easier backups** - Backup entire server including Grafana
- ✅ **Simpler disaster recovery** - Restore single server
- ✅ **Unified logging** - All logs in one place

#### ❌ Arguments AGAINST Local Deployment

**1. Resource Usage**
- ❌ **CPU/Memory consumption** - Grafana uses resources on OpenSIPS server
- ❌ **Resource contention** - Grafana queries compete with OpenSIPS for CPU/memory
- ❌ **Disk I/O** - Grafana queries may impact OpenSIPS database performance
- ❌ **Impact on OpenSIPS** - Heavy dashboard usage could affect SIP processing

**2. Scalability Limitations**
- ❌ **Single server constraint** - Cannot scale Grafana independently
- ❌ **Limited horizontal scaling** - Cannot add more Grafana instances easily
- ❌ **Resource limits** - Bound by OpenSIPS server capacity
- ❌ **Cannot monitor multiple OpenSIPS instances** - Limited to one server

**3. Security Concerns**
- ❌ **Exposed on same server** - Grafana web UI on same host as OpenSIPS
- ❌ **Attack surface** - If Grafana is compromised, OpenSIPS server is at risk
- ❌ **Port exposure** - Need to expose Grafana port (3000) on OpenSIPS server
- ❌ **Shared security boundary** - Same firewall rules apply to both services

**4. High Availability**
- ❌ **Single point of failure** - If OpenSIPS server fails, monitoring is lost
- ❌ **No redundancy** - Cannot have redundant Grafana instances easily
- ❌ **Tied to OpenSIPS availability** - Monitoring unavailable when OpenSIPS is down

**5. Maintenance Impact**
- ❌ **Service disruption** - Grafana updates/restarts affect OpenSIPS server
- ❌ **Shared maintenance window** - Cannot maintain Grafana independently
- ❌ **Risk to production** - Grafana issues could impact OpenSIPS server

**6. Access & Collaboration**
- ❌ **Limited remote access** - Requires VPN or direct server access
- ❌ **Less convenient** - Team members need server access
- ❌ **No centralized monitoring** - Cannot monitor multiple sites from one Grafana

---

### Option 2: Cloud Deployment (Separate Server)

**Deployment:** Grafana runs on a separate cloud server or infrastructure

#### ✅ Arguments FOR Cloud Deployment

**1. Resource Isolation**
- ✅ **No impact on OpenSIPS** - Grafana runs on separate resources
- ✅ **Independent scaling** - Scale Grafana without affecting OpenSIPS
- ✅ **Resource guarantees** - Dedicated CPU/memory for Grafana
- ✅ **Better performance** - OpenSIPS server focused on SIP processing

**2. Scalability & Flexibility**
- ✅ **Monitor multiple OpenSIPS instances** - Single Grafana can monitor many servers
- ✅ **Horizontal scaling** - Can deploy multiple Grafana instances
- ✅ **Cloud scalability** - Leverage cloud auto-scaling features
- ✅ **Multi-site monitoring** - Centralized monitoring for distributed deployments

**3. High Availability**
- ✅ **Independent availability** - Grafana available even if OpenSIPS server fails
- ✅ **Redundancy options** - Can deploy redundant Grafana instances
- ✅ **Cloud HA features** - Leverage cloud provider HA capabilities
- ✅ **Monitoring during outages** - Can monitor OpenSIPS recovery

**4. Security Isolation**
- ✅ **Separate security boundary** - Grafana isolated from OpenSIPS
- ✅ **Reduced attack surface** - Compromise of Grafana doesn't affect OpenSIPS
- ✅ **Network isolation** - Can use VPN or private network for Prometheus connection
- ✅ **Access control** - Separate firewall rules and access policies

**5. Operational Benefits**
- ✅ **Independent maintenance** - Update Grafana without touching OpenSIPS
- ✅ **Separate maintenance windows** - Maintain Grafana independently
- ✅ **Professional hosting** - Cloud provider handles infrastructure
- ✅ **Backup & recovery** - Cloud provider backup solutions

**6. Access & Collaboration**
- ✅ **Remote access** - Team members can access from anywhere
- ✅ **Centralized access** - Single URL for all team members
- ✅ **No VPN required** - Can access via HTTPS (with proper security)
- ✅ **Better for distributed teams** - Easier collaboration

**7. Advanced Features**
- ✅ **Cloud integrations** - Integrate with cloud monitoring services
- ✅ **Professional support** - Cloud provider support options
- ✅ **Advanced networking** - Cloud networking features (VPC, etc.)
- ✅ **Integration options** - Easier to integrate with other cloud services

#### ❌ Arguments AGAINST Cloud Deployment

**1. Complexity**
- ❌ **More complex setup** - Requires network configuration between cloud and OpenSIPS
- ❌ **More moving parts** - Additional server to manage
- ❌ **Network dependencies** - Requires stable network connection
- ❌ **More troubleshooting** - Issues can be in network, cloud, or OpenSIPS

**2. Network & Latency**
- ❌ **Network latency** - Queries to Prometheus go over network (milliseconds)
- ❌ **Bandwidth usage** - Monitoring queries consume network bandwidth
- ❌ **Network dependency** - Monitoring unavailable if network is down
- ❌ **Internet requirement** - Requires internet connectivity

**3. Cost**
- ❌ **Additional hosting costs** - Monthly cloud server fees
- ❌ **Bandwidth costs** - May incur data transfer charges
- ❌ **Higher TCO** - Additional infrastructure to pay for
- ❌ **Ongoing expenses** - Recurring monthly costs

**4. Security & Privacy**
- ❌ **Data in cloud** - Monitoring data stored in cloud provider
- ❌ **Cloud provider access** - Cloud provider has access to infrastructure
- ❌ **Compliance concerns** - May not meet data residency requirements
- ❌ **Additional attack surface** - Cloud endpoint to secure
- ❌ **Network security** - Need to secure Prometheus → Grafana connection

**5. Operational Overhead**
- ❌ **Additional server to manage** - More infrastructure to maintain
- ❌ **Cloud provider dependency** - Dependent on cloud provider availability
- ❌ **More complex backups** - Need to backup cloud server separately
- ❌ **Disaster recovery complexity** - More complex recovery procedures

**6. Access & Network Configuration**
- ❌ **Network configuration** - Need to configure Prometheus to accept connections from cloud
- ❌ **Firewall rules** - Need to open Prometheus port to cloud IP
- ❌ **VPN/Network setup** - May need VPN or private network
- ❌ **Security hardening** - Need to secure cloud → Prometheus connection

---

### Comparison Summary

| Factor | Local Deployment | Cloud Deployment |
|--------|------------------|------------------|
| **Setup Complexity** | ✅ Simple | ❌ More complex |
| **Cost** | ✅ Lower (no cloud fees) | ❌ Higher (cloud hosting) |
| **Latency** | ✅ Low (localhost) | ❌ Higher (network) |
| **Resource Impact** | ❌ Uses OpenSIPS resources | ✅ Isolated resources |
| **Scalability** | ❌ Limited | ✅ Better |
| **Security Isolation** | ❌ Shared security boundary | ✅ Isolated |
| **High Availability** | ❌ Single point of failure | ✅ Independent |
| **Multi-site Monitoring** | ❌ Single server only | ✅ Multiple servers |
| **Data Privacy** | ✅ On-premises | ❌ In cloud |
| **Network Dependency** | ✅ Works offline | ❌ Requires network |
| **Maintenance** | ❌ Shared maintenance | ✅ Independent |
| **Remote Access** | ❌ Requires VPN/server access | ✅ Easy remote access |

---

### Recommendations

#### Choose **Local Deployment** if:
- ✅ **Single OpenSIPS server** deployment
- ✅ **Cost-sensitive** - Want to minimize infrastructure costs
- ✅ **Simple setup** - Prefer simpler deployment
- ✅ **Data privacy critical** - Need data to stay on-premises
- ✅ **Low latency required** - Need fastest possible query response
- ✅ **Limited resources** - Cannot afford separate cloud server
- ✅ **Internal monitoring only** - No need for remote access

**Best For:** Small deployments, single-server setups, cost-sensitive projects, high data privacy requirements

#### Choose **Cloud Deployment** if:
- ✅ **Multiple OpenSIPS servers** to monitor
- ✅ **Resource isolation critical** - Don't want Grafana impacting OpenSIPS
- ✅ **Scalability needed** - Plan to scale or monitor multiple sites
- ✅ **High availability required** - Need monitoring even if OpenSIPS server fails
- ✅ **Remote access needed** - Team needs access from multiple locations
- ✅ **Professional infrastructure** - Want cloud provider managed services
- ✅ **Centralized monitoring** - Want single Grafana for multiple deployments

**Best For:** Production deployments, multi-server setups, distributed teams, scalable infrastructure

#### Hybrid Approach (Advanced)

**Option:** Run Grafana locally for primary monitoring, with cloud Grafana for:
- Backup monitoring (if local Grafana fails)
- Remote team access
- Historical data archiving
- Multi-site aggregation

**Considerations:**
- More complex setup
- Higher cost
- Need to sync or replicate data
- May require Prometheus federation

---

### Decision Matrix

Use this matrix to help decide:

| Your Situation | Recommendation |
|----------------|----------------|
| Single OpenSIPS server, small team, cost-sensitive | **Local** |
| Multiple OpenSIPS servers, distributed team | **Cloud** |
| High data privacy requirements | **Local** |
| Need to monitor during OpenSIPS outages | **Cloud** |
| Limited server resources | **Cloud** |
| Simple setup preferred | **Local** |
| Need remote access | **Cloud** |
| Want fastest query performance | **Local** |
| Plan to scale horizontally | **Cloud** |
| Compliance requires on-premises data | **Local** |

---

### Implementation Notes

**For Local Deployment:**
- Monitor Grafana resource usage
- Set resource limits (CPU/memory)
- Consider running Grafana in Docker with resource constraints
- Use reverse proxy (Nginx) for security
- Restrict Grafana port access via firewall

**For Cloud Deployment:**
- Configure Prometheus to accept connections from cloud IP
- Use VPN or private network for Prometheus connection
- Implement authentication/authorization
- Use HTTPS for Grafana access
- Consider Prometheus federation for multiple Prometheus instances

---

## Statistics to Collect

### Core Statistics (High Priority)

| Statistic | MI Name | Description | Alert Threshold |
|-----------|---------|-------------|-----------------|
| **Requests Received** | `core:rcv_requests` | Total SIP requests received | Rate > threshold |
| **Replies Received** | `core:rcv_replies` | Total SIP replies received | Rate > threshold |
| **Requests Forwarded** | `core:fwd_requests` | Total requests forwarded | Rate > threshold |
| **Replies Forwarded** | `core:fwd_replies` | Total replies forwarded | Rate > threshold |
| **Dropped Requests** | `core:drop_requests` | Requests dropped | Count > threshold |
| **Error Requests** | `core:err_requests` | Requests with errors | Count > threshold |
| **Error Rate** | Calculated | `err_requests / rcv_requests` | Rate > 5% |

### Transaction Statistics (High Priority)

| Statistic | MI Name | Description | Alert Threshold |
|-----------|---------|-------------|-----------------|
| **Active Transactions** | `tm:active_transactions` | Currently active transactions | Count > threshold |
| **Total Transactions** | `tm:transactions` | Total transactions processed | Rate > threshold |
| **UAS Transactions** | `tm:UAS_transactions` | User Agent Server transactions | - |
| **UAC Transactions** | `tm:UAC_transactions` | User Agent Client transactions | - |

### Dialog Statistics (High Priority)

| Statistic | MI Name | Description | Alert Threshold |
|-----------|---------|-------------|-----------------|
| **Active Dialogs** | `dialog:active_dialogs` | Currently active calls | Count > threshold |
| **Early Dialogs** | `dialog:early_dialogs` | Calls in early state (ringing) | - |
| **Processed Dialogs** | `dialog:processed_dialogs` | Total dialogs processed | Rate > threshold |

### Dispatcher Statistics (High Priority)

| Statistic | MI Name | Description | Alert Threshold |
|-----------|---------|-------------|-----------------|
| **Active Destinations** | `dispatcher:active_destinations` | Healthy Asterisk backends | Count < threshold |
| **Inactive Destinations** | `dispatcher:inactive_destinations` | Unhealthy Asterisk backends | Count > 0 |
| **Destination Availability** | Calculated | `active / (active + inactive)` | Rate < 50% |

### Module Statistics (Medium Priority)

| Statistic | MI Name | Description | Alert Threshold |
|-----------|---------|-------------|-----------------|
| **NAT Helper Stats** | `nathelper:*` | NAT traversal statistics | - |
| **User Location Stats** | `usrloc:*` | Registration statistics | - |
| **Accounting Stats** | `acc:*` | Accounting statistics | - |
| **Memory Usage** | `shmem:*` | Shared memory statistics | Usage > threshold |

### Database Statistics (Medium Priority)

| Statistic | Source | Description | Alert Threshold |
|-----------|--------|-------------|-----------------|
| **CDR Count** | `acc` table | Total CDR records | - |
| **Active Registrations** | `location` table | Registered endpoints | Count > threshold |
| **Active Calls** | `dialog` table | Active calls (state 4) | Count > threshold |

---

## Deployment Steps

### Phase 1: OpenSIPS Prometheus Module Configuration ✅ **AUTOMATED**

**Goal:** Enable and configure built-in Prometheus module

**Status:** ✅ **Automated via `install.sh` script and `opensips.cfg.template`**

**What Gets Configured:**
1. **Modules Enabled** (in `opensips.cfg.template`)
   - `loadmodule "httpd.so"` - HTTP server for Prometheus endpoint
   - `loadmodule "prometheus.so"` - Prometheus metrics export

2. **Configuration** (in `opensips.cfg.template`)
   - HTTP server socket: `http:0.0.0.0:8888`
   - Prometheus root path: `/metrics`
   - Metric prefix: `opensips`
   - Group mode: 1 (include group in metric name)
   - Statistics exported: `core:`, `tm:`, `dialog:`, `dispatcher:`, `usrloc:`, `acc:`

3. **Automatic Setup**
   - Configuration included in `opensips.cfg.template`
   - Applied automatically during `install.sh` execution
   - No manual configuration needed

**Verification Steps:**
```bash
# Test metrics endpoint (after installation)
curl http://localhost:8888/metrics

# Should return Prometheus format metrics:
# # HELP opensips_core_rcv_requests ...
# # TYPE opensips_core_rcv_requests counter
# opensips_core_rcv_requests 12345
# opensips_dialog_active_dialogs 5
# etc.
```

**Deliverables:**
- ✅ Prometheus module enabled (via config template)
- ✅ HTTP endpoint accessible at `/metrics`
- ✅ Metrics in Prometheus format
- ✅ Configuration automated in installer

### Phase 2: Prometheus Server Configuration ⚠️ **SIMPLIFIED**

**Goal:** Configure Prometheus to scrape OpenSIPS metrics endpoint

**Note:** No exporter development needed - OpenSIPS exposes metrics directly!

1. **Verify OpenSIPS Metrics Endpoint**
   ```bash
   # Verify metrics are accessible
   curl http://localhost:8888/metrics
   ```

2. **Configure Prometheus Scrape Target**
   - Update `prometheus.yml` to scrape OpenSIPS directly
   - Target: `http://opensips-ip:8888/metrics`
   - No intermediate exporter needed

**Deliverables:**
- ✅ Prometheus configured to scrape OpenSIPS
- ✅ Metrics being collected
- ✅ No custom exporter needed!

### Phase 3: Prometheus Server Deployment

**Goal:** Deploy Prometheus server to collect metrics

**See:** `docs/PROMETHEUS-INSTALL-UBUNTU.md` for complete Ubuntu 24.04 AMD64 installation guide

1. **Install Prometheus**
   ```bash
   # Follow detailed guide: docs/PROMETHEUS-INSTALL-UBUNTU.md
   # Summary:
   # - Download Prometheus binary
   # - Create prometheus user
   # - Set up directories
   # - Configure systemd service
   ```

2. **Configure Prometheus**
   - Create `prometheus.yml` configuration
   - Add OpenSIPS exporter as scrape target
   - Set scrape interval (e.g., 15 seconds)

3. **Prometheus Configuration** (`prometheus.yml`)
   ```yaml
   global:
     scrape_interval: 15s
     evaluation_interval: 15s
   
   scrape_configs:
     - job_name: 'opensips'
       static_configs:
         - targets: ['localhost:9091']  # Exporter endpoint
       scrape_interval: 15s
       metrics_path: '/metrics'
   ```

4. **Test Prometheus**
   - Access Prometheus UI: `http://localhost:9090`
   - Query metrics: `opensips_requests_received_total`
   - Verify data collection

**Deliverables:**
- ✅ Prometheus server running
- ✅ Configuration file
- ✅ Metrics being collected
- ✅ Data retention policy configured

### Phase 4: Grafana Deployment

**Goal:** Deploy Grafana for visualization

1. **Install Grafana**
   ```bash
   # Option 1: Docker
   docker run -d --name grafana \
     -p 3000:3000 \
     grafana/grafana
   
   # Option 2: Native (Ubuntu)
   sudo apt-get install grafana
   ```

2. **Configure Grafana**
   - Access Grafana UI: `http://localhost:3000`
   - Default credentials: `admin/admin`
   - Add Prometheus as datasource
   - Configure connection to Prometheus

3. **Import OpenSIPS Dashboard Template**
   - **Dashboard ID:** 6935
   - **URL:** https://grafana.com/grafana/dashboards/6935-opensips/
   - **Requirements:** 
     - ✅ OpenSIPS Prometheus module metrics
     - ✅ Node Exporter metrics (system metrics)
   - Import via Grafana UI: Configuration → Dashboards → Import
   - Enter dashboard ID: `6935`
   - Select Prometheus datasource
   - Verify all panels populate (requires both OpenSIPS and Node Exporter metrics)

4. **Create Custom Dashboards** (Optional)
   - Core statistics dashboard
   - Transaction statistics dashboard
   - Dialog statistics dashboard
   - Dispatcher health dashboard
   - System overview dashboard

**Deliverables:**
- ✅ Grafana server running
- ✅ Prometheus datasource configured
- ✅ OpenSIPS dashboard template imported (ID 6935)
- ✅ All dashboard panels populated (OpenSIPS + Node Exporter metrics)
- ✅ Custom dashboards created (optional)

### Phase 5: Alerting Configuration

**Goal:** Configure alerting rules

1. **Prometheus Alert Rules**
   - Create `alerts.yml` file
   - Define alert conditions
   - Configure alert thresholds

2. **Alert Examples**
   - High error rate (> 5%)
   - Low dispatcher availability (< 50%)
   - High active transactions (> threshold)
   - No active destinations (all down)

3. **Alertmanager** (Optional)
   - Deploy Alertmanager for alert routing
   - Configure notification channels (email, Slack, etc.)

**Deliverables:**
- ✅ Alert rules configured
- ✅ Alertmanager deployed (optional)
- ✅ Notification channels configured

---

## File Structure

```
pbx3sbc/
├── config/
│   └── opensips.cfg.template        # OpenSIPS config (includes Prometheus module)
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml           # Prometheus configuration
│   │   ├── alerts.yml                # Alert rules
│   │   └── README.md                 # Prometheus documentation
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── opensips-core.json   # Core statistics dashboard
│   │   │   ├── opensips-transactions.json
│   │   │   ├── opensips-dialogs.json
│   │   │   └── opensips-dispatcher.json
│   │   ├── provisioning/
│   │   │   └── datasources.yml      # Datasource configuration
│   │   └── README.md                 # Grafana documentation
│   └── docker-compose.yml            # Docker Compose for Prometheus/Grafana
├── scripts/
│   └── install-monitoring.sh         # Installation script
└── docs/
    └── PROMETHEUS-GRAFANA-PLAN.md    # This document
```

**Note:** No exporter directory needed - OpenSIPS Prometheus module handles everything!

---

## Configuration Details

### OpenSIPS Prometheus Module Configuration

**File:** `config/opensips.cfg.template`

**Reference:** [OpenSIPS 3.6 Prometheus Module Documentation](https://opensips.org/docs/modules/3.6.x/prometheus.html)

```opensips
####### HTTP Server (Required for Prometheus) ########
loadmodule "httpd.so"
modparam("httpd", "socket", "http:0.0.0.0:8888")  # Default port 8888

####### Prometheus Module ########
loadmodule "prometheus.so"

# Metrics endpoint path (default: /metrics)
# Access at: http://localhost:8888/metrics
modparam("prometheus", "root", "metrics")

# Metric prefix (default: opensips)
modparam("prometheus", "prefix", "opensips")

# Group mode: 1 = include group in metric name
# Example: opensips_core_rcv_requests (instead of opensips_rcv_requests)
modparam("prometheus", "group_mode", 1)

# Export statistics (can be defined multiple times)
# Three approaches available:

# Approach 1: Group-based (exports all stats in each group) - CURRENT CONFIGURATION
# Recommended for comprehensive monitoring - exports all statistics in each group
modparam("prometheus", "statistics", "core:")       # All core statistics
modparam("prometheus", "statistics", "tm:")         # All transaction statistics
modparam("prometheus", "statistics", "dialog:")     # All dialog statistics
modparam("prometheus", "statistics", "dispatcher:") # All dispatcher statistics
modparam("prometheus", "statistics", "usrloc:")    # All user location statistics
modparam("prometheus", "statistics", "acc:")       # All accounting statistics

# Approach 2: Specific statistics only (uncomment to use instead)
# Useful for reducing metric volume or focusing on specific metrics
# modparam("prometheus", "statistics", "core:rcv_requests core:rcv_replies core:fwd_requests core:fwd_replies")
# modparam("prometheus", "statistics", "core:drop_requests core:err_requests")
# modparam("prometheus", "statistics", "tm:transactions tm:active_transactions")
# modparam("prometheus", "statistics", "tm:UAS_transactions tm:UAC_transactions")
# modparam("prometheus", "statistics", "dialog:active_dialogs dialog:early_dialogs")
# modparam("prometheus", "statistics", "dialog:processed_dialogs")
# modparam("prometheus", "statistics", "dispatcher:active_destinations")
# modparam("prometheus", "statistics", "dispatcher:inactive_destinations")

# Approach 3: Mixed (specific stats + groups) - Example from OpenSIPS documentation
# You can mix specific stat names with groups in the same modparam call
# modparam("prometheus", "statistics", "active_dialogs load: stats:")
#   - Exports specific stat "active_dialogs"
#   - Exports all stats in "load" group
#   - Exports all stats in "stats" group

# Or export ALL statistics (simpler, but more metrics)
# modparam("prometheus", "statistics", "all")
# Note: If "all" is specified, other statistics parameters are ignored

# Optional: Custom labels for statistics
# Example: Convert duration_gateway to duration with gateway label
# modparam("prometheus", "labels", "group: /^(.*)_(.*)$/\1:gateway=\"\2\"/")
```

### OpenSIPS Prometheus Module Configuration (Complete Example)

**File:** `config/opensips.cfg.template`

**Note:** No custom exporter needed - OpenSIPS exposes metrics directly!

```opensips
####### HTTP Server (Required for Prometheus) ########
loadmodule "httpd.so"
modparam("httpd", "socket", "http:0.0.0.0:8888")

####### Prometheus Module ########
loadmodule "prometheus.so"

# Configuration
modparam("prometheus", "root", "metrics")           # Endpoint: /metrics
modparam("prometheus", "prefix", "opensips")        # Metric prefix
modparam("prometheus", "group_mode", 1)             # Include group in name

# Export statistics (can define multiple times)
modparam("prometheus", "statistics", "core:")       # All core statistics
modparam("prometheus", "statistics", "tm:")         # All transaction statistics
modparam("prometheus", "statistics", "dialog:")     # All dialog statistics
modparam("prometheus", "statistics", "dispatcher:") # All dispatcher statistics

# Optional: Custom statistics via script route
modparam("prometheus", "script_route", "prometheus_custom")

route[prometheus_custom] {
    # Declare custom metric
    prometheus_declare_stat("opensips_total_cps", "gauge", "Total calls per second");
    
    # Push custom metric value
    prometheus_push_stat(3);
    
    # Push with labels
    prometheus_declare_stat("opensips_domain_calls", "counter", "Calls per domain");
    prometheus_push_stat(10, "domain", "example.com");
    
    return;
}
```

**Access Metrics:**
```bash
# Prometheus will scrape from:
curl http://localhost:8888/metrics

# Example output:
# # HELP opensips_core_rcv_requests Total requests received
# # TYPE opensips_core_rcv_requests counter
# opensips_core_rcv_requests 12345
# opensips_dialog_active_dialogs 5
# opensips_tm_active_transactions 10
```

### Prometheus Configuration

**File:** `monitoring/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'pbx3sbc'
    environment: 'production'

# Alertmanager configuration (optional)
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
  # OpenSIPS statistics (direct from OpenSIPS Prometheus module)
  - job_name: 'opensips'
    static_configs:
      - targets: ['localhost:8888']  # OpenSIPS HTTP endpoint
    scrape_interval: 15s
    metrics_path: '/metrics'  # Prometheus module endpoint
    scrape_timeout: 10s

  # Node Exporter (system metrics - required for Grafana dashboards)
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

### Alert Rules

**File:** `monitoring/prometheus/alerts.yml`

```yaml
groups:
  - name: opensips_alerts
    interval: 30s
    rules:
      - alert: HighErrorRate
        expr: rate(opensips_requests_dropped_total[5m]) / rate(opensips_requests_received_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      - alert: NoActiveDestinations
        expr: opensips_active_destinations == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "No active dispatcher destinations"
          description: "All Asterisk backends are down"

      - alert: HighActiveTransactions
        expr: opensips_active_transactions > 1000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of active transactions"
          description: "Active transactions: {{ $value }}"
```

---

## Testing & Validation

### Test Plan

1. **OpenSIPS Prometheus Module Test**
   ```bash
   # Test metrics endpoint
   curl http://localhost:8888/metrics
   
   # Should return Prometheus format:
   # # HELP opensips_core_rcv_requests ...
   # # TYPE opensips_core_rcv_requests counter
   # opensips_core_rcv_requests 12345
   ```

2. **Node Exporter Test**
   ```bash
   # Test metrics endpoint
   curl http://localhost:9100/metrics
   
   # Should return Prometheus format:
   # node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
   # node_memory_MemTotal_bytes 8589934592
   # node_disk_read_bytes_total{device="sda"} 123456789
   ```

3. **Prometheus Scraping Test**
   ```bash
   
   # Verify Prometheus can scrape both
   # Check Prometheus UI: http://localhost:9090
   # Status → Targets: Should show both opensips and node as UP
   
   # Query OpenSIPS metrics
   # Query: opensips_core_rcv_requests
   # Query: rate(opensips_core_rcv_requests[5m])
   
   # Query Node Exporter metrics
   # Query: node_cpu_seconds_total
   # Query: node_memory_MemTotal_bytes
   ```

4. **Grafana Test**
   - Import OpenSIPS dashboard template (ID 6935)
   - Verify all panels populate
   - Test that both OpenSIPS and system metrics appear
   - Test alerting

---

## Deployment Timeline

### ✅ **Automated Installation (Day 1)**

**Status:** Fully automated via `install.sh` script

**What Happens:**
1. Run `sudo ./install.sh` (or with `--skip-prometheus` to skip Prometheus)
2. Script automatically:
   - Installs Prometheus and Node Exporter
   - Configures OpenSIPS Prometheus module
   - Creates Prometheus configuration files
   - Sets up systemd services
   - Configures firewall rules
   - Starts all services

**Time Required:** ~10-15 minutes (mostly download time)

### Week 1: Verification & Testing
- Verify OpenSIPS metrics endpoint: `curl http://localhost:8888/metrics`
- Verify Node Exporter metrics: `curl http://localhost:9100/metrics`
- Verify Prometheus scraping: Check Prometheus UI at `http://localhost:9090`
- Test queries in Prometheus UI
- Verify all services are running: `systemctl status prometheus node_exporter opensips`

### Week 2: Grafana Deployment (Optional - Local or Cloud)
- Deploy Grafana server (local or cloud - see decision section above)
- Configure Prometheus datasource
- Import OpenSIPS dashboard template (ID 6935)
- Verify all panels populate
- Create custom dashboards (optional)

### Week 3: Alerting & Polish (Optional)
- Configure additional alert rules
- Set up Alertmanager (optional)
- Fine-tune dashboards
- Create documentation
- Production deployment review

---

## Maintenance & Operations

### Regular Tasks

1. **Monitor Exporter**
   - Check exporter logs
   - Verify metrics are being collected
   - Monitor exporter resource usage

2. **Prometheus Maintenance**
   - Monitor disk usage
   - Review retention policies
   - Check scrape failures

3. **Grafana Maintenance**
   - Update dashboards as needed
   - Review alert rules
   - Monitor Grafana performance

### Troubleshooting

**Common Issues:**

1. **OpenSIPS metrics not accessible**
   - Check httpd module is loaded and configured
   - Verify Prometheus module is loaded
   - Test endpoint: `curl http://localhost:8888/metrics`
   - Check OpenSIPS logs for errors

2. **Prometheus not scraping**
   - Verify OpenSIPS metrics endpoint accessible (`curl http://opensips-ip:8888/metrics`)
   - Check Prometheus configuration (target should be OpenSIPS IP:8888)
   - Verify metrics_path is `/metrics`
   - Review Prometheus logs

3. **Grafana not showing data**
   - Verify Prometheus datasource
   - Check query syntax
   - Verify time range

---

## Future Enhancements

1. **Additional Metrics**
   - Database query performance
   - Endpoint-specific statistics
   - Domain-based statistics

2. **Advanced Dashboards**
   - Historical trending
   - Predictive analytics
   - Capacity planning

3. **Integration**
   - Integrate with existing monitoring
   - Export to other systems
   - API for external access

---

## References

- **OpenSIPS 3.6 Prometheus Module:** https://opensips.org/docs/modules/3.6.x/prometheus.html
- **OpenSIPS 3.6 HTTPd Module:** https://opensips.org/docs/modules/3.6.x/httpd.html
- **Prometheus Installation Guide (Ubuntu 24.04):** `docs/PROMETHEUS-INSTALL-UBUNTU.md`
- **Prometheus Documentation:** https://prometheus.io/docs/
- **Grafana Documentation:** https://grafana.com/docs/

---

**Last Updated:** January 2026  
**Status:** Planning Phase  
**Next Steps:** Begin Phase 1 - OpenSIPS MI Configuration
