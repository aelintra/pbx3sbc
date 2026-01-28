# Fail2Ban Remote Management Options

**Date:** January 2026  
**Context:** Admin panel must remain decoupled from OpenSIPS server for flexibility, testing, and fleet management

---

## Problem Statement

**Current Implementation:** Assumes admin panel is colocated with OpenSIPS server
- Direct file system access to `/etc/fail2ban/jail.d/opensips-brute-force.conf`
- Direct execution of `fail2ban-client` commands
- Direct `systemctl restart fail2ban` access

**Requirement:** Admin panel should be able to manage Fail2Ban on remote OpenSIPS instances
- Support for fleet management (multiple OpenSIPS servers)
- Testing flexibility (admin panel on different server)
- Maintain security (privileged operations)

---

## Option 1: SSH-Based Remote Execution ⭐ **RECOMMENDED**

### Architecture
- Admin panel uses SSH to execute commands on OpenSIPS server
- SSH key-based authentication (no passwords)
- Commands executed via `ssh user@opensips-server "command"`

### Implementation

**Service Layer:**
```php
class Fail2banService
{
    protected string $sshHost;
    protected string $sshUser;
    protected string $sshKeyPath;
    
    public function getStatus(): array
    {
        $command = "fail2ban-client status opensips-brute-force";
        $output = $this->executeRemoteCommand($command);
        return $this->parseStatus($output);
    }
    
    protected function executeRemoteCommand(string $command): string
    {
        $sshCommand = sprintf(
            'ssh -i %s -o StrictHostKeyChecking=no %s@%s "%s"',
            escapeshellarg($this->sshKeyPath),
            escapeshellarg($this->sshUser),
            escapeshellarg($this->sshHost),
            escapeshellarg($command)
        );
        
        $result = Process::run(['bash', '-c', $sshCommand]);
        return $result->output();
    }
}
```

**Config File Management:**
```php
class WhitelistSyncService
{
    // Use SFTP to read/write config file
    // Or use SSH to execute sed/awk commands
    // Or use SSH to execute sync script remotely
}
```

### Pros
- ✅ No new services needed
- ✅ Secure (SSH encryption, key-based auth)
- ✅ Works with existing infrastructure
- ✅ Supports multiple servers (different SSH hosts)
- ✅ Minimal changes to OpenSIPS server
- ✅ Standard tooling (SSH is ubiquitous)

### Cons
- ⚠️ Requires SSH key management
- ⚠️ Requires SSH access from admin panel to OpenSIPS server
- ⚠️ Network dependency (SSH must be reachable)
- ⚠️ Slightly slower (network latency)

### Security Considerations
- Use dedicated SSH user with limited sudo permissions
- Restrict SSH key to specific commands via `authorized_keys` command restrictions
- Use separate SSH keys per OpenSIPS server
- Rotate keys regularly

### Sudoers Configuration (on OpenSIPS server)
```
# Dedicated user for admin panel operations
admin-panel ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client status opensips-brute-force
admin-panel ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force banip *
admin-panel ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unbanip *
admin-panel ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unban --all
admin-panel ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart fail2ban
admin-panel ALL=(ALL) NOPASSWD: /home/*/pbx3sbc/scripts/sync-fail2ban-whitelist.sh
```

### Testing
- Easy to test: admin panel on different server
- Can use SSH tunnel for local testing
- Supports multiple OpenSIPS instances (different SSH hosts)

---

## Option 2: Lightweight API Agent Service

### Architecture
- Small HTTP API service runs on OpenSIPS server
- Listens on localhost (or internal network)
- Admin panel calls API endpoints
- API executes Fail2Ban commands locally

### Implementation

**Agent Service (on OpenSIPS server):**
```python
# Simple Flask/FastAPI service
from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

@app.route('/api/fail2ban/status', methods=['GET'])
def get_status():
    result = subprocess.run(
        ['fail2ban-client', 'status', 'opensips-brute-force'],
        capture_output=True, text=True
    )
    return jsonify({'output': result.stdout, 'status': result.returncode})

@app.route('/api/fail2ban/unban', methods=['POST'])
def unban_ip():
    ip = request.json.get('ip')
    result = subprocess.run(
        ['sudo', 'fail2ban-client', 'set', 'opensips-brute-force', 'unbanip', ip],
        capture_output=True, text=True
    )
    return jsonify({'success': result.returncode == 0})
```

**Admin Panel Service:**
```php
class Fail2banService
{
    protected string $apiBaseUrl; // e.g., "https://opensips-server:8443/api"
    
    public function getStatus(): array
    {
        $response = Http::get("{$this->apiBaseUrl}/fail2ban/status");
        return $this->parseStatus($response->json()['output']);
    }
}
```

### Pros
- ✅ Clean API interface
- ✅ Can use HTTPS/TLS for security
- ✅ Token-based authentication
- ✅ Easy to add rate limiting
- ✅ Can support multiple OpenSIPS instances (different API URLs)
- ✅ Standard REST API patterns

### Cons
- ⚠️ Requires new service on OpenSIPS server
- ⚠️ Additional maintenance burden
- ⚠️ Network exposure (even if internal)
- ⚠️ Need to secure API endpoints
- ⚠️ Need to handle service failures

### Security Considerations
- Use HTTPS/TLS
- Token-based authentication (JWT or API keys)
- Rate limiting
- IP whitelisting (only admin panel can access)
- Run on internal network only (not public-facing)

### Testing
- Easy to test: admin panel calls API
- Can mock API responses for testing
- Supports multiple OpenSIPS instances

---

## Option 3: Database-Driven with Agent Polling

### Architecture
- Admin panel writes commands to database
- Agent service on OpenSIPS server polls database
- Agent executes commands and updates status
- Similar to job queue pattern

### Implementation

**Database Table:**
```sql
CREATE TABLE fail2ban_commands (
    id INT AUTO_INCREMENT PRIMARY KEY,
    opensips_server_id INT NOT NULL,
    command_type ENUM('unban', 'ban', 'sync_whitelist', 'get_status'),
    command_data JSON,
    status ENUM('pending', 'processing', 'completed', 'failed'),
    result JSON,
    created_at TIMESTAMP,
    completed_at TIMESTAMP
);
```

**Agent Service (on OpenSIPS server):**
```python
# Polls database every few seconds
while True:
    commands = db.query("SELECT * FROM fail2ban_commands WHERE status='pending'")
    for cmd in commands:
        execute_command(cmd)
        update_status(cmd)
    sleep(5)
```

**Admin Panel Service:**
```php
class Fail2banService
{
    public function unbanIP(string $ip, int $serverId): void
    {
        Fail2banCommand::create([
            'opensips_server_id' => $serverId,
            'command_type' => 'unban',
            'command_data' => ['ip' => $ip],
            'status' => 'pending',
        ]);
    }
}
```

### Pros
- ✅ No direct network connection needed
- ✅ Works through existing database connection
- ✅ Natural fit for fleet management (server_id)
- ✅ Can queue commands (retry on failure)
- ✅ Audit trail in database
- ✅ No new network ports

### Cons
- ⚠️ Requires agent service on each OpenSIPS server
- ⚠️ Polling latency (not real-time)
- ⚠️ More complex (queue management)
- ⚠️ Database becomes command queue (coupling)

### Security Considerations
- Database access already secured
- Agent runs with limited permissions
- Commands validated before execution
- Audit trail for all operations

### Testing
- Easy to test: admin panel writes to database
- Agent can run locally for testing
- Supports multiple OpenSIPS instances naturally

---

## Option 4: Message Queue / Event-Driven

### Architecture
- Admin panel publishes commands to message queue (RabbitMQ, Redis, etc.)
- Agent on OpenSIPS server subscribes to queue
- Real-time command execution
- Supports multiple servers via routing keys

### Implementation

**Admin Panel:**
```php
class Fail2banService
{
    public function unbanIP(string $ip, string $serverId): void
    {
        Queue::push('fail2ban.command', [
            'server_id' => $serverId,
            'command' => 'unban',
            'data' => ['ip' => $ip],
        ]);
    }
}
```

**Agent Service (on OpenSIPS server):**
```python
# Subscribes to queue
def handle_command(ch, method, properties, body):
    cmd = json.loads(body)
    if cmd['server_id'] == get_local_server_id():
        execute_command(cmd)
        ch.basic_ack(delivery_tag=method.delivery_tag)
```

### Pros
- ✅ Real-time execution
- ✅ Natural fit for fleet management
- ✅ Decoupled (admin panel doesn't know about servers)
- ✅ Scalable (can add more servers easily)
- ✅ Can use existing message queue infrastructure

### Cons
- ⚠️ Requires message queue infrastructure
- ⚠️ Additional complexity
- ⚠️ Need to handle queue failures
- ⚠️ Overkill for single-server deployments

### Security Considerations
- Secure message queue (TLS, authentication)
- Validate commands before execution
- Rate limiting per server

### Testing
- Can use in-memory queue for testing
- Supports multiple servers naturally
- More complex setup

---

## Option 5: Hybrid: Database + SSH Fallback

### Architecture
- Primary: Database-driven commands (Option 3)
- Fallback: SSH for immediate operations (Option 1)
- Best of both worlds

### Implementation
```php
class Fail2banService
{
    public function unbanIP(string $ip, int $serverId): void
    {
        // Try immediate SSH if available
        if ($this->canUseSSH($serverId)) {
            $this->unbanViaSSH($ip, $serverId);
        } else {
            // Fallback to database queue
            $this->unbanViaDatabase($ip, $serverId);
        }
    }
}
```

### Pros
- ✅ Immediate execution when SSH available
- ✅ Works without SSH (database fallback)
- ✅ Flexible deployment options

### Cons
- ⚠️ More complex implementation
- ⚠️ Two code paths to maintain

---

## Comparison Matrix

| Option | Complexity | Real-time | Fleet Support | Security | Testing Ease | Maintenance |
|--------|-----------|-----------|---------------|---------|--------------|-------------|
| **SSH** | Low | ✅ Yes | ✅ Yes | ✅ High | ✅ Easy | ✅ Low |
| **API Agent** | Medium | ✅ Yes | ✅ Yes | ⚠️ Medium | ✅ Easy | ⚠️ Medium |
| **DB Polling** | Medium | ⚠️ Delayed | ✅ Yes | ✅ High | ✅ Easy | ⚠️ Medium |
| **Message Queue** | High | ✅ Yes | ✅ Yes | ⚠️ Medium | ⚠️ Complex | ⚠️ High |
| **Hybrid** | High | ✅ Yes | ✅ Yes | ✅ High | ✅ Easy | ⚠️ Medium |

---

## Recommendation: Option 1 (SSH-Based) ⭐

**Decision:** SSH-based remote execution will be implemented in the future.

**Rationale:**
- Message queue (RabbitMQ/Redis) would be more "modern" but is **overkill** for current needs
- SSH is less "sexy" but **simpler, more secure, and uses existing infrastructure**
- Supports fleet management (multiple OpenSIPS instances)
- Maintains decoupled architecture principle

**Why SSH is best for this use case:**

1. **Simplicity:** No new services, uses existing SSH infrastructure
2. **Security:** SSH encryption, key-based auth, well-understood security model
3. **Fleet Support:** Easy to support multiple servers (different SSH hosts in config)
4. **Testing:** Easy to test (admin panel on different server)
5. **Maintenance:** Minimal overhead (SSH is standard)
6. **Flexibility:** Can work with or without SSH (fallback options)

**Implementation Strategy:**

1. **Phase 1:** Refactor services to support remote execution
   - Add `$sshHost`, `$sshUser`, `$sshKeyPath` configuration
   - Abstract command execution (local vs remote)
   - Default to local if SSH not configured (backward compatible)

2. **Phase 2:** Add server management
   - `opensips_servers` table (id, hostname, ssh_user, ssh_key_path, etc.)
   - Admin panel can manage multiple OpenSIPS instances
   - Each Fail2Ban operation specifies target server

3. **Phase 3:** Enhanced features
   - Bulk operations across fleet
   - Server health monitoring
   - Centralized logging

---

## Implementation Considerations

### Configuration

**Admin Panel Config:**
```php
// config/fail2ban.php
return [
    'default_server' => env('F2B_DEFAULT_SERVER', 'local'),
    
    'servers' => [
        'local' => [
            'type' => 'local', // Direct execution
        ],
        'opensips-1' => [
            'type' => 'ssh',
            'host' => env('F2B_SERVER_1_HOST'),
            'user' => env('F2B_SERVER_1_USER', 'admin-panel'),
            'key_path' => env('F2B_SERVER_1_KEY_PATH'),
        ],
        'opensips-2' => [
            'type' => 'ssh',
            'host' => env('F2B_SERVER_2_HOST'),
            'user' => env('F2B_SERVER_2_USER', 'admin-panel'),
            'key_path' => env('F2B_SERVER_2_KEY_PATH'),
        ],
    ],
];
```

### Service Refactoring

```php
interface Fail2banCommandExecutor
{
    public function execute(string $command): string;
}

class LocalExecutor implements Fail2banCommandExecutor { }
class SshExecutor implements Fail2banCommandExecutor { }
class ApiExecutor implements Fail2banCommandExecutor { }

class Fail2banService
{
    protected Fail2banCommandExecutor $executor;
    
    public function __construct(Fail2banCommandExecutor $executor)
    {
        $this->executor = $executor;
    }
}
```

---

## Implementation Timeline

### Phase 1: Colocated Deployment (Current) ✅

**Status:** Implemented and working

**Approach:** Admin panel colocated with OpenSIPS server
- Direct file system access
- Direct command execution
- Simple and secure

**Trade-offs:**
- ✅ Simple implementation
- ✅ Fast execution
- ⚠️ Testing requires full server setup
- ⚠️ Cannot manage multiple servers

**Purpose:** Build and test core functionality to satisfaction

### Phase 2: SSH-Based Remote Execution (Future)

**Status:** Planned for future implementation

**Approach:** Refactor to support SSH-based remote execution

**Steps:**
1. **Refactor Services:** Implement executor pattern (LocalExecutor vs SshExecutor)
2. **Add Server Management:** `opensips_servers` table for fleet management
3. **Update UI:** Server selection in admin panel
4. **Configuration:** SSH credentials per server
5. **Testing:** Test with remote admin panel

**Benefits:**
- ✅ Decoupled architecture (admin panel independent)
- ✅ Fleet management (multiple OpenSIPS instances)
- ✅ Easier testing (admin panel anywhere)
- ✅ Maintains security (SSH encryption)

**See:** Implementation details in "Implementation Strategy" section above

---

## Next Steps

### Immediate (Phase 1)
- ✅ Core functionality implemented (colocated)
- ✅ Testing with colocated deployment
- ✅ Refine features based on usage

### Future (Phase 2)
1. **Design:** Detailed SSH executor architecture
2. **Implementation:** Refactor services to support remote execution
3. **Testing:** Test with remote admin panel
4. **Documentation:** Update deployment guides for remote setup

---

**Status:** Phase 1 complete (colocated), Phase 2 planned (SSH-based remote execution)
