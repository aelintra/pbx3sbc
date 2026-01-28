# Fail2Ban Admin Panel Enhancement - Quick Unban & Blocked IP Viewing

**Date:** January 2026  
**Priority:** 🔴 **HIGH** - Addresses panic scenarios when legitimate IPs get blocked

---

## Problem Statement

**Panic Scenario:** Legitimate customer IP gets blocked by Fail2Ban, causing service outage. Admin needs to:
1. Quickly see which IPs are currently blocked
2. Immediately unban the blocked IP
3. Optionally add to whitelist to prevent future blocks

**Current State:** Requires SSH access and command-line execution:
```bash
sudo fail2ban-client status opensips-brute-force
sudo fail2ban-client set opensips-brute-force unbanip <IP>
```

**Solution:** Admin panel with quick access to blocked IPs and one-click unban.

---

## Enhanced Features

### 1. Fail2Ban Status Page (Priority: HIGH)

**Location:** `/admin/fail2ban/status` or prominent link in navigation

**Key Features:**
- **Real-time banned IP list** - Shows all currently blocked IPs
- **One-click unban** - Immediate unban action per IP
- **Bulk unban** - Unban all IPs at once (emergency)
- **Ban details** - Show when IP was banned (if available from Fail2Ban)
- **Quick whitelist** - "Unban & Whitelist" action (prevents re-banning)

**UI Layout:**
```
┌─────────────────────────────────────────────────────────┐
│ Fail2Ban Status - opensips-brute-force                  │
├─────────────────────────────────────────────────────────┤
│ Jail Status: ✅ Enabled                                 │
│ Currently Banned: 5 IPs                                 │
│                                                          │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Currently Banned IPs                                 │ │
│ ├─────────────────────────────────────────────────────┤ │
│ │ IP Address    │ Banned At │ Actions                │ │
│ ├─────────────────────────────────────────────────────┤ │
│ │ 203.0.113.50  │ 2 min ago │ [Unban] [Unban+WL]    │ │
│ │ 198.51.100.25 │ 15 min ago │ [Unban] [Unban+WL]    │ │
│ │ 192.0.2.100   │ 1 hour ago │ [Unban] [Unban+WL]    │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                          │
│ [Unban All] [Manual Ban] [Refresh]                     │
└─────────────────────────────────────────────────────────┘
```

### 2. Dashboard Widget (Priority: HIGH)

**Location:** Main admin dashboard

**Purpose:** Quick visibility of blocked IPs without navigating to status page

**Widget Design:**
```
┌─────────────────────────────────────┐
│ 🔒 Fail2Ban Status                  │
├─────────────────────────────────────┤
│ Currently Banned: 5 IPs             │
│                                     │
│ Recent Bans:                        │
│ • 203.0.113.50 (2 min ago)         │
│ • 198.51.100.25 (15 min ago)        │
│ • 192.0.2.100 (1 hour ago)         │
│                                     │
│ [View All] [Quick Unban]           │
└─────────────────────────────────────┘
```

**Features:**
- Shows count of banned IPs
- Lists recent bans (last 5-10)
- Quick link to status page
- Quick unban action (opens modal with IP input)

### 3. Quick Unban Modal (Priority: HIGH)

**Trigger:** Button in dashboard widget or status page

**Purpose:** Fastest way to unban an IP when you know the IP address

**Modal Design:**
```
┌─────────────────────────────────────┐
│ Quick Unban IP                       │
├─────────────────────────────────────┤
│ IP Address: [203.0.113.50    ]      │
│                                     │
│ ☐ Also add to whitelist            │
│   (prevents future automatic bans)   │
│                                     │
│ [Cancel] [Unban]                    │
└─────────────────────────────────────┘
```

**Features:**
- IP address input with validation
- Optional "add to whitelist" checkbox
- Immediate execution
- Success/error feedback

### 4. Enhanced Status Page Details

**Additional Information to Display:**

1. **Jail Configuration:**
   - Jail name: `opensips-brute-force`
   - Status: Enabled/Disabled
   - Max retries: 10
   - Find time: 5 minutes
   - Ban time: 1 hour

2. **Banned IP Details:**
   - IP address
   - Time banned (relative: "2 min ago")
   - Time until auto-unban (if temporary ban)
   - Reason (if available from logs)

3. **Statistics:**
   - Total banned IPs (current)
   - Bans in last 24 hours
   - Bans in last 7 days
   - Most frequently banned IPs

---

## Implementation Details

### Commands to Execute

**Get Jail Status:**
```bash
fail2ban-client status opensips-brute-force
```

**Parse Output:**
The output format is:
```
Status for the jail: opensips-brute-force
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     15
|  `- File list:        /var/log/opensips/opensips.log
`- Actions
   |- Currently banned: 2
   |- Total banned:     5
   `- Banned IP list:   203.0.113.50 198.51.100.25
```

**Extract Banned IPs:**
```bash
fail2ban-client status opensips-brute-force | grep "Banned IP list:" | awk '{print $4,$5,$6,$7,$8,$9,$10}'
```

**Unban IP:**
```bash
fail2ban-client set opensips-brute-force unbanip <IP>
```

**Unban All:**
```bash
fail2ban-client set opensips-brute-force unban --all
```

### Laravel Implementation

**Service Class:** `app/Services/Fail2banService.php`

```php
<?php

namespace App\Services;

use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Log;

class Fail2banService
{
    protected string $jailName = 'opensips-brute-force';
    
    /**
     * Get jail status
     */
    public function getStatus(): array
    {
        $result = Process::run(['sudo', 'fail2ban-client', 'status', $this->jailName]);
        
        if (!$result->successful()) {
            throw new \Exception('Failed to get Fail2Ban status: ' . $result->errorOutput());
        }
        
        return $this->parseStatus($result->output());
    }
    
    /**
     * Get list of banned IPs
     */
    public function getBannedIPs(): array
    {
        $status = $this->getStatus();
        return $status['banned_ips'] ?? [];
    }
    
    /**
     * Unban a specific IP
     */
    public function unbanIP(string $ip): bool
    {
        $result = Process::run([
            'sudo',
            'fail2ban-client',
            'set',
            $this->jailName,
            'unbanip',
            $ip
        ]);
        
        if (!$result->successful()) {
            Log::error('Failed to unban IP', [
                'ip' => $ip,
                'error' => $result->errorOutput()
            ]);
            return false;
        }
        
        Log::info('IP unbanned via admin panel', [
            'ip' => $ip,
            'user' => auth()->id()
        ]);
        
        return true;
    }
    
    /**
     * Unban all IPs
     */
    public function unbanAll(): bool
    {
        $result = Process::run([
            'sudo',
            'fail2ban-client',
            'set',
            $this->jailName,
            'unban',
            '--all'
        ]);
        
        if (!$result->successful()) {
            Log::error('Failed to unban all IPs', [
                'error' => $result->errorOutput()
            ]);
            return false;
        }
        
        Log::warning('All IPs unbanned via admin panel', [
            'user' => auth()->id()
        ]);
        
        return true;
    }
    
    /**
     * Ban an IP manually
     */
    public function banIP(string $ip): bool
    {
        $result = Process::run([
            'sudo',
            'fail2ban-client',
            'set',
            $this->jailName,
            'banip',
            $ip
        ]);
        
        if (!$result->successful()) {
            Log::error('Failed to ban IP', [
                'ip' => $ip,
                'error' => $result->errorOutput()
            ]);
            return false;
        }
        
        Log::info('IP banned via admin panel', [
            'ip' => $ip,
            'user' => auth()->id()
        ]);
        
        return true;
    }
    
    /**
     * Parse Fail2Ban status output
     */
    protected function parseStatus(string $output): array
    {
        $status = [
            'jail_name' => $this->jailName,
            'enabled' => false,
            'currently_failed' => 0,
            'total_failed' => 0,
            'currently_banned' => 0,
            'total_banned' => 0,
            'banned_ips' => [],
        ];
        
        // Extract banned IPs
        if (preg_match('/Banned IP list:\s*(.+)/', $output, $matches)) {
            $ips = trim($matches[1]);
            $status['banned_ips'] = $ips ? explode(' ', $ips) : [];
        }
        
        // Extract counts
        if (preg_match('/Currently banned:\s*(\d+)/', $output, $matches)) {
            $status['currently_banned'] = (int)$matches[1];
        }
        
        if (preg_match('/Total banned:\s*(\d+)/', $output, $matches)) {
            $status['total_banned'] = (int)$matches[1];
        }
        
        // Check if enabled (jail exists and has status)
        $status['enabled'] = strpos($output, 'Status for the jail') !== false;
        
        return $status;
    }
}
```

### Filament Page

**Location:** `app/Filament/Pages/Fail2banStatus.php`

```php
<?php

namespace App\Filament\Pages;

use App\Services\Fail2banService;
use Filament\Pages\Page;
use Filament\Notifications\Notification;
use Illuminate\Support\Facades\Cache;

class Fail2banStatus extends Page
{
    protected static ?string $navigationIcon = 'heroicon-o-shield-exclamation';
    protected static string $view = 'filament.pages.fail2ban-status';
    protected static ?string $navigationLabel = 'Fail2Ban Status';
    protected static ?int $navigationSort = 10;
    
    public array $status = [];
    public array $bannedIPs = [];
    public string $quickUnbanIP = '';
    public bool $addToWhitelist = false;
    
    protected Fail2banService $fail2banService;
    
    public function boot(): void
    {
        $this->fail2banService = app(Fail2banService::class);
        $this->loadStatus();
    }
    
    public function loadStatus(): void
    {
        try {
            $this->status = $this->fail2banService->getStatus();
            $this->bannedIPs = $this->status['banned_ips'] ?? [];
        } catch (\Exception $e) {
            Notification::make()
                ->title('Failed to load Fail2Ban status')
                ->body($e->getMessage())
                ->danger()
                ->send();
        }
    }
    
    public function unbanIP(string $ip): void
    {
        try {
            if ($this->fail2banService->unbanIP($ip)) {
                Notification::make()
                    ->title('IP Unbanned')
                    ->body("IP {$ip} has been unbanned successfully.")
                    ->success()
                    ->send();
                
                // Optionally add to whitelist
                if ($this->addToWhitelist) {
                    // Call whitelist service to add IP
                    // app(WhitelistService::class)->add($ip, "Auto-whitelisted after unban");
                }
                
                $this->loadStatus();
            } else {
                Notification::make()
                    ->title('Failed to Unban IP')
                    ->body("Could not unban IP {$ip}. Check logs for details.")
                    ->danger()
                    ->send();
            }
        } catch (\Exception $e) {
            Notification::make()
                ->title('Error')
                ->body($e->getMessage())
                ->danger()
                ->send();
        }
    }
    
    public function unbanAll(): void
    {
        try {
            if ($this->fail2banService->unbanAll()) {
                Notification::make()
                    ->title('All IPs Unbanned')
                    ->body('All banned IPs have been unbanned.')
                    ->warning()
                    ->send();
                
                $this->loadStatus();
            }
        } catch (\Exception $e) {
            Notification::make()
                ->title('Error')
                ->body($e->getMessage())
                ->danger()
                ->send();
        }
    }
    
    public function quickUnban(): void
    {
        if (empty($this->quickUnbanIP)) {
            Notification::make()
                ->title('IP Required')
                ->body('Please enter an IP address to unban.')
                ->warning()
                ->send();
            return;
        }
        
        $this->unbanIP($this->quickUnbanIP);
        $this->quickUnbanIP = '';
        $this->addToWhitelist = false;
    }
}
```

### Sudoers Configuration

**File:** `/etc/sudoers.d/pbx3sbc-admin`

```
# Allow www-data to run fail2ban-client commands without password
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client status opensips-brute-force
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force banip *
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unbanip *
www-data ALL=(ALL) NOPASSWD: /usr/bin/fail2ban-client set opensips-brute-force unban --all
```

---

## Priority Features

### Phase 1: Critical (Panic Scenarios)
1. ✅ View banned IPs list
2. ✅ One-click unban per IP
3. ✅ Quick unban modal (IP input)
4. ✅ Dashboard widget showing banned count

### Phase 2: Enhanced
5. ⏸️ "Unban & Whitelist" action
6. ⏸️ Ban time remaining display
7. ⏸️ Statistics (bans in last 24h, etc.)
8. ⏸️ Manual ban functionality

### Phase 3: Advanced
9. ⏸️ Ban history tracking
10. ⏸️ Email notifications on ban/unban
11. ⏸️ Audit log of admin actions

---

## Security Considerations

1. **Audit Logging:** All ban/unban actions logged with user ID and timestamp
2. **Rate Limiting:** Prevent abuse of ban/unban actions
3. **Permission Checks:** Only authorized admins can access Fail2Ban management
4. **Input Validation:** Validate IP addresses before executing commands
5. **Error Handling:** Graceful error handling if Fail2Ban is unavailable

---

## Testing Scenarios

1. **Panic Scenario:** Customer reports blocked IP
   - Admin navigates to Fail2Ban Status page
   - Finds IP in banned list
   - Clicks "Unban"
   - Verifies IP is removed from banned list

2. **Quick Unban:** Admin knows IP address
   - Opens quick unban modal from dashboard
   - Enters IP address
   - Clicks "Unban"
   - IP is immediately unbanned

3. **Bulk Unban:** Multiple false positives
   - Admin clicks "Unban All"
   - All IPs are unbanned
   - System logs action

---

## Related Documentation

- [Admin Panel Security Requirements](ADMIN-PANEL-SECURITY-REQUIREMENTS.md) - Overall admin panel security features
- [Fail2Ban Configuration](../config/fail2ban/README.md) - Fail2Ban setup and configuration
- [Security Implementation Plan](SECURITY-IMPLEMENTATION-PLAN.md) - Overall security project plan

---

**Status:** Ready for implementation  
**Priority:** 🔴 HIGH - Addresses critical panic scenarios
