# Procedure: Opening MySQL Port on OpenSIPS Server

## Overview
This procedure covers how to open MySQL port 3306 on the OpenSIPS server to allow remote database connections. **Important:** Only open MySQL port if you need remote access. For security, MySQL should typically only accept localhost connections.

## Prerequisites
- Root or sudo access to the OpenSIPS server
- UFW (Uncomplicated Firewall) installed (default on Ubuntu/Debian)
- MySQL/MariaDB server installed and configured

## Security Considerations

⚠️ **WARNING:** Opening MySQL port 3306 to the internet exposes your database to potential attacks. Consider these security measures:

1. **Restrict access by IP:** Only allow connections from specific IP addresses or networks
2. **Use strong passwords:** Ensure MySQL user passwords are strong
3. **Use SSL/TLS:** Configure MySQL to require encrypted connections
4. **Consider VPN:** Use a VPN tunnel instead of exposing MySQL directly
5. **Firewall rules:** Use both UFW and cloud security groups if applicable

## Procedure

### Step 1: Check Current Firewall Status

```bash
# Check if UFW is active
sudo ufw status

# Check if MySQL port is already open
sudo ufw status | grep 3306
```

### Step 2: Configure MySQL to Listen on Network Interface

By default, MySQL may only listen on localhost (127.0.0.1). You need to configure it to listen on the network interface.

#### 2.1: Edit MySQL Configuration

```bash
# Edit MySQL configuration file
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# OR for MariaDB:
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

#### 2.2: Find and Modify bind-address

Look for the `bind-address` line and change it:

**For localhost only (most secure):**
```ini
bind-address = 127.0.0.1
```

**For all interfaces (required for remote access):**
```ini
bind-address = 0.0.0.0
```

**For specific interface (recommended):**
```ini
bind-address = <your-server-ip>
```

#### 2.3: Restart MySQL Service

```bash
sudo systemctl restart mysql
# OR for MariaDB:
sudo systemctl restart mariadb

# Verify MySQL is listening on the correct interface
sudo netstat -tlnp | grep 3306
# OR
sudo ss -tlnp | grep 3306
```

You should see output like:
```
tcp  0  0  0.0.0.0:3306  0.0.0.0:*  LISTEN  <pid>/mysqld
```

### Step 3: Configure UFW Firewall Rules

#### Option A: Allow MySQL Port from Specific IP Address (Recommended)

```bash
# Replace <REMOTE_IP> with the IP address that needs access
sudo ufw allow from <REMOTE_IP> to any port 3306 comment 'MySQL from specific IP'

# Example: Allow from a specific IP
sudo ufw allow from 192.168.1.100 to any port 3306 comment 'MySQL from admin workstation'

# Example: Allow from a subnet
sudo ufw allow from 192.168.1.0/24 to any port 3306 comment 'MySQL from local network'
```

#### Option B: Allow MySQL Port from Anywhere (Less Secure)

```bash
# Allow MySQL port from any IP (NOT recommended for production)
sudo ufw allow 3306/tcp comment 'MySQL remote access'
```

#### Option C: Allow MySQL Port from Specific Network Interface

```bash
# Allow MySQL only on specific interface (e.g., private network)
sudo ufw allow in on eth1 to any port 3306 comment 'MySQL on private network'
```

### Step 4: Verify Firewall Rules

```bash
# Check UFW status and verify MySQL rule is added
sudo ufw status numbered

# Check detailed status
sudo ufw status verbose | grep 3306
```

Expected output should show:
```
3306/tcp                   ALLOW       Anywhere                   # MySQL remote access
```

### Step 5: Configure MySQL User Permissions

Even with the firewall open, MySQL users must be granted remote access privileges.

#### 5.1: Connect to MySQL

```bash
mysql -u root -p
```

#### 5.2: Grant Remote Access to User

```sql
-- Grant access from specific IP
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'<REMOTE_IP>' IDENTIFIED BY 'your-password';

-- Grant access from any IP (less secure)
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'%' IDENTIFIED BY 'your-password';

-- Grant access from subnet
GRANT ALL PRIVILEGES ON opensips.* TO 'opensips'@'192.168.1.%' IDENTIFIED BY 'your-password';

-- Apply changes
FLUSH PRIVILEGES;

-- Exit MySQL
EXIT;
```

**Note:** Replace `opensips` with your actual MySQL username and `your-password` with the actual password.

### Step 6: Test Remote Connection

From a remote machine, test the connection:

```bash
# Test connection from remote machine
mysql -h <OPENSIPS_SERVER_IP> -u opensips -p opensips

# Or test with telnet/netcat
telnet <OPENSIPS_SERVER_IP> 3306
# OR
nc -zv <OPENSIPS_SERVER_IP> 3306
```

### Step 7: Cloud Provider Security Groups (If Applicable)

If your OpenSIPS server is running in a cloud environment (AWS, Azure, GCP), you must also configure the cloud provider's security groups/firewall rules.

#### AWS EC2 Security Groups

1. Go to EC2 Dashboard → Security Groups
2. Select your OpenSIPS server's security group
3. Add inbound rule:
   - Type: MySQL/Aurora
   - Protocol: TCP
   - Port: 3306
   - Source: Specific IP or CIDR block (recommended) or 0.0.0.0/0 (not recommended)

#### Azure Network Security Groups

1. Go to Azure Portal → Network Security Groups
2. Select your NSG
3. Add inbound security rule:
   - Source: IP Addresses or Service Tag
   - Source IP: Specific IP or CIDR
   - Destination: Any
   - Service: Custom
   - Protocol: TCP
   - Port: 3306
   - Action: Allow

#### Google Cloud Platform Firewall Rules

```bash
# Create firewall rule via gcloud CLI
gcloud compute firewall-rules create allow-mysql \
    --allow tcp:3306 \
    --source-ranges <REMOTE_IP>/32 \
    --target-tags opensips-server \
    --description "Allow MySQL from specific IP"
```

Or via GCP Console:
1. Go to VPC Network → Firewall Rules
2. Create new rule
3. Set source IP ranges, target tags, and allow TCP port 3306

## Troubleshooting

### MySQL Port Not Accessible

1. **Check MySQL is listening:**
   ```bash
   sudo netstat -tlnp | grep 3306
   ```

2. **Check UFW rules:**
   ```bash
   sudo ufw status | grep 3306
   ```

3. **Check cloud security groups** (if applicable)

4. **Check MySQL error log:**
   ```bash
   sudo tail -f /var/log/mysql/error.log
   ```

5. **Test locally first:**
   ```bash
   mysql -h 127.0.0.1 -u opensips -p opensips
   ```

### Connection Refused

- Verify `bind-address` is not set to `127.0.0.1` only
- Check firewall rules are applied: `sudo ufw reload`
- Verify MySQL user has remote access privileges

### Connection Timeout

- Check cloud security groups allow port 3306
- Verify network routing between source and destination
- Check if ISP or intermediate firewall is blocking port 3306

## Security Best Practices

1. **Use IP restrictions:** Only allow specific IPs or subnets
2. **Use strong passwords:** Enforce complex passwords for MySQL users
3. **Enable SSL/TLS:** Configure MySQL SSL certificates for encrypted connections
4. **Regular updates:** Keep MySQL and system packages updated
5. **Monitor access:** Review MySQL logs regularly for suspicious activity
6. **Use VPN:** Consider using a VPN tunnel instead of exposing MySQL directly
7. **Fail2ban:** Install fail2ban to block repeated connection attempts

## Reverting Changes

If you need to close MySQL port:

```bash
# Remove UFW rule
sudo ufw delete allow 3306/tcp
# OR delete by number
sudo ufw delete <rule_number>

# Revert MySQL bind-address to localhost only
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Change: bind-address = 127.0.0.1
sudo systemctl restart mysql

# Revoke remote access in MySQL
mysql -u root -p
REVOKE ALL PRIVILEGES ON opensips.* FROM 'opensips'@'%';
FLUSH PRIVILEGES;
EXIT;
```

## Related Documentation

- [OpenSIPS Installation Guide](03-Install_notes.md)
- [Cloud Deployment Checklist](CLOUD-DEPLOYMENT-CHECKLIST.md)
- [Manual Install Steps](../workingdocs/MANUAL-INSTALL-STEPS.md)
