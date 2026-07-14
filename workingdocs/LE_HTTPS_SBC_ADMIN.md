# Let’s Encrypt HTTPS — SBC admin (`sbc.pbx3.com`)

**Settled lab (2026-07-14):** Filament admin at **`https://sbc.pbx3.com/admin`**. SIP TLS is **out of scope** here (RTP bypass / UDP SIP unchanged).

## What this is / is not

| In | Out |
|----|-----|
| nginx :443 + LE cert for `sbc.pbx3.com` | OpenSIPS SIP TLS (`5061`) |
| HTTP → HTTPS redirect (except ACME) | Control-plane EC2 LE (separate tip) |
| `APP_URL=https://sbc.pbx3.com` | SSO / IP allowlist / Filament redesign |

**Auth honesty:** Filament login already existed. Public **HTTP** was the gap (credentials cleartext). HTTPS closes transport. MSP-grade auth (SSO, allowlist) remains a later TODO.

**Ops checklist after enable:** rotate / confirm Filament admin password (profile menu).

## Prerequisites

1. **DNS** `sbc.pbx3.com` → SBC public IPv4.
2. **UFW** (on box): `80/tcp` and `443/tcp` ALLOW (already typical).
3. **EC2 security group** (easy to miss): explicit **TCP 80** and **TCP 443** from `0.0.0.0/0`.  
   Lab was blocked when SG only had “all traffic from one office IP” (`74.83.26.203/32`) — Mac could hit :80, Let’s Encrypt validators could not (`Timeout during connect`).

## Issue / renew (lab path)

```bash
# On SBC as ubuntu (or with sudo)
sudo apt-get install -y certbot python3-certbot-nginx   # once

# server_name must be sbc.pbx3.com (not the EC2 internal hostname)
# webroot = Laravel public/
sudo certbot certonly --webroot \
  -w /home/ubuntu/pbx3sbc-admin/public \
  -d sbc.pbx3.com \
  --non-interactive --agree-tos -m admin@aelintra.com

# Install nginx site from repo template (or copy live config):
#   pbx3sbc-admin/deploy/nginx-pbx3sbc-admin.conf
# → /etc/nginx/sites-available/pbx3sbc-admin
# Prefer symlink: sites-enabled → sites-available

sudo nginx -t && sudo systemctl reload nginx

# Laravel
# APP_URL=https://sbc.pbx3.com  in /home/ubuntu/pbx3sbc-admin/.env
cd /home/ubuntu/pbx3sbc-admin && php artisan config:clear
```

**Renewal:** `certbot.timer` is enabled with the package. Deploy hook reloads nginx:

`/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh` → `systemctl reload nginx`

Dry-run: `sudo certbot renew --dry-run`

## Verify

```bash
curl -sI http://sbc.pbx3.com/admin | grep -i Location   # → https://…
curl -sI https://sbc.pbx3.com/admin/login | head         # 200
echo | openssl s_client -connect sbc.pbx3.com:443 -servername sbc.pbx3.com 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

## Related

- Node tenant multi-SAN LE: **`pbx3/workingdocs/TLS_IMPLEMENTATION_STEPS.md`** (different product path).
- Fleet HA / VIP: **`pbx3/pbx3-directory/docs/FLEET_TRUNK_PEERING_DECISION.md`** §6 — same VIP name will need this cert story when active–passive lands.
