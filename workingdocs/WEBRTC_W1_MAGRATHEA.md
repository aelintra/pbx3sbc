# WebRTC WSS on Magrathea (W1) — operator checklist

**Goal:** SIP over **WSS terminates on Magrathea** (VIP / `sbc.pbx3.com`); **RTP bypass** — browser ICE/DTLS-SRTP ↔ home Asterisk. Desk UDP **:5060** unchanged.  
**Not in scope:** rtpengine, multi-AZ proof, SPA line-test product, Magrathea desk SIP TLS (`5061`).  
**Spec:** **`pbx3/pbx3-directory/docs/FLEET_TRUNK_PEERING_DECISION.md`** §6.1 · lab notes **`pbx3/workingdocs/WEBRTC_WSS_LAB.md`** · older scaffold branch **`webrtc-wss`** (superseded by this track for Magrathea).

**Git branch (this work):** **`w1-magrathea-wss`** (from pbx3sbc **`main`**).  
**Lab host:** Magrathea VIP **`3.93.26.82`** · admin HTTPS **`sbc.pbx3.com`**.

**Product surface (client):**

| Field | Value |
|-------|--------|
| **WSS** | `wss://sbc.pbx3.com:8089/ws` (recommended; same VIP as desk SIP) |
| **SIP user** | extension **shortuid** (e.g. `8af9ee`) |
| **SIP domain** | tenant string (e.g. `dhbm8x.pbx3.com`) — **no** public tenant A record required |
| **Media** | direct to home instance (bypass SBC) |

OpenSIPS path is **`/ws`** (`wss_resource`) so clients match golden mental model (Asterisk `:8089/ws`).

---

## Progress legend

- `[x]` done in repo or confirmed  
- `[~]` in progress  
- `[ ]` not done  

Update this section when you complete a phase.

### Snapshot (2026-08-03)

| Phase | Status |
|-------|--------|
| **0** Goal + constraints locked | **[x]** |
| **1** Git branch + recovery discipline | **[x]** branch; **[x]** Magrathea backup |
| **2** Repo config / scripts ready | **[x]** |
| **3** Packages + cert on Magrathea | **[x]** modules installed; certs copied to `/etc/opensips/tls/` |
| **4** Firewall / SG | **[x]** UFW **8089**; SG open (operator 2026-08-03) |
| **5** Enable WSS in live `opensips.cfg` | **[x]** live enabled; `-C` OK; service **active**; UDP **5060** + WSS **8089** listening |
| **6** Smoke: REGISTER + dialog over WSS | **[x]** WSS upgrade **101**; REGISTER **401→200** via Magrathea (`8af9ee` / `dhbm8x`, server Asterisk) — smoke 2026-08-03 from golden |
| **7** Smoke: audio (RTP not on SBC) | **[ ]** browser/webphone still |
| **8** Document + merge `main` | **[ ]** |

**Live enable snapshot (2026-08-03 ~16:42 UTC):**
- Modules: `opensips-wss-module`, `opensips-tls-openssl-module`, `opensips-tlsmgm-module`
- Cert: `/etc/opensips/tls/sbc.pbx3.com-{fullchain,privkey}.pem` (from LE; renew hook re-copies)
- Config backups: `/root/opensips.cfg.pre-w1.20260803163707`, `/root/opensips.cfg.pre-w1-enable.20260803164214`
- Local TLS: `openssl s_client` → **CN=sbc.pbx3.com**
- Desk UDP activity after restart: OPTIONS still answering (log OK)


---

## Phase 0 — Agree (done)

- [x] Target = **Magrathea** (not scratch-first) with recovery first  
- [x] RTP **bypass** only (no edge media)  
- [x] Client: **WSS host = edge**; **SIP domain = tenant** (desk already; proxy-less UIs may differ)  
- [x] Port **8089/tcp** + path **`/ws`** (prefer over 443/admin mix)  
- [x] Do not require tenant public DNS for W1  
- [x] Desk UDP path must keep working after enable  

---

## Phase 1 — Pre-steps (before live cfg change)

### 1.1 Git (repo)

```bash
cd …/pbx3sbc
git fetch origin
git checkout main && git pull --ff-only
git checkout -b w1-magrathea-wss   # already created 2026-08-03
```

- [x] Branch **`w1-magrathea-wss`** exists  
- [ ] Remote pushed (`git push -u origin w1-magrathea-wss`)  
- [ ] Optional: git tag on last known-good deployed cfg parent (e.g. `pre-w1-magrathea-wss`) after backup  

### 1.2 Magrathea backup (operator on VIP host — **before** WSS enable)

SSH to Magrathea (your key). **Do not skip.**

```bash
# On Magrathea as root (or sudo):
sudo /path/to/pbx3sbc/scripts/backup-sbc.sh --trigger pre-upgrade --upload
# If upload not configured, at least local:
sudo /path/to/pbx3sbc/scripts/backup-sbc.sh --trigger pre-upgrade

# Also snapshot live OpenSIPS cfg + any local fragments:
sudo cp -a /etc/opensips/opensips.cfg "/root/opensips.cfg.pre-w1.$(date +%Y%m%d%H%M%S)"
# Confirm Desk still OK after backup (should be read-only):
#   Snom REGISTER + short call via VIP
```

- [x] `backup-sbc.sh` produced zip under `/var/lib/pbx3sbc/bkup/` — **`sbcbak.1785775027.zip`** (2026-08-03); S3 `s3://08jzwn-pbx3/sbc/sbc/backups/20260803T163707Z/backup.zip`  
- [x] Live **`opensips.cfg`** copy: **`/root/opensips.cfg.pre-w1.20260803163707`** (+ `/home/ubuntu/opensips.cfg.pre-w1.20260803163707`)  
- [ ] Spot-check: desk phone still registered via Magrathea after backup (operator optional; OpenSIPS stayed **active**, :5060 up)  

**Recovery if WSS enable goes wrong:** restore pre-w1 `opensips.cfg`, restart OpenSIPS, reopen SG if needed (UDP 5060 path is independent of WSS listener if only WSS block is rolled back).

---

## Phase 2 — Repo work (agent / this branch)

- [x] This checklist  
- [x] Template: optional **`proto_wss` / `tls_mgm` / socket `wss:…:8089`** block (default **commented** so package installs / non-Magrathea stays safe)  
- [x] Template: **skip `fix_nated_sdp` rewrite** for WSS/WS and ICE SDP (RTP bypass — do not pull media face onto SBC)  
- [x] Script: **`scripts/setup-opensips-wss.sh`** (packages, cert ACL, enable helper notes)  
- [x] Cert renew: deploy-hook notes for OpenSIPS after LE renew  
- [ ] `opensips -C` validate on Magrathea after enable (live)  
- [ ] Merge **`w1-magrathea-wss` → `main`** only after Phase 6–7 green  

---

## Phase 3 — Magrathea packages + TLS material

On Magrathea:

```bash
# Discover package names for this OpenSIPS major:
apt-cache search opensips | grep -Ei 'wss|tls|openssl'

# Typical Ubuntu packaging names (adjust to apt output):
sudo apt-get install -y opensips-tls-openssl-module opensips-wss-module
# or equivalents: opensips-module-tls / proto packages

# LE already used for admin (sbc.pbx3.com). OpenSIPS must read same or dedicated chain:
sudo ./scripts/setup-opensips-wss.sh --cert-domain sbc.pbx3.com
# installs ACLs (ssl-cert / opensips readable privkey+fullchain) if paths exist

# Sanity:
sudo -u opensips test -r /etc/letsencrypt/live/sbc.pbx3.com/fullchain.pem && echo fullchain_ok
sudo -u opensips test -r /etc/letsencrypt/live/sbc.pbx3.com/privkey.pem && echo key_ok
```

- [ ] WSS + TLS modules installed  
- [ ] Opensips user can read fullchain + privkey  
- [ ] Deploy hook (or cron) reloads/restarts OpenSIPS on cert renew  

---

## Phase 4 — Network

| Control | Action |
|---------|--------|
| **Security group** (EIP/VIP ENI) | Allow **TCP 8089** from operator / test webphone CIDRs (world only if deliberate). **Magrathea lab SG:** `sg-0c79ea76cd5631398` (instance **`i-078cca73d4a4106bb`**). SBC instance role **cannot** edit SG — open from your AWS console / IAM user. |
| **UFW / Shorewall** on box | **TCP 8089** ACCEPT in (same posture as SIP allow) |
| **UDP 5060** | Unchanged |
| **UDP 10000–20000 on Magrathea** | **Not required for this path** (RTP bypass — do **not** force media SG on SBC for W1) |
| **Golden / home node** | Already has public RTP for WebRTC (Shorewall + SG) |

- [ ] SG 8089 open for test source  
- [ ] Host firewall 8089 open  
- [ ] Desk 5060 still reaches Magrathea  

---

## Phase 5 — Enable in live config

1. Merge template WSS block into **`/etc/opensips/opensips.cfg`** (or re-install from template then re-apply Magrathea customizations).  
2. **Uncomment** the W1 block; set cert paths to `sbc.pbx3.com` LE.  
3. Keep **`socket=udp:0.0.0.0:5060`** and existing `advertised_address` (VIP).  
4. Validate, then restart:

```bash
sudo opensips -C -f /etc/opensips/opensips.cfg
# fix any -C errors before restart
sudo systemctl restart opensips   # or opensips service name on host
sudo ss -lntp | grep -E '5060|8089'
# Expect: :5060/udp  and  :8089 (wss)
```

- [ ] `-C` clean  
- [ ] Service up; **5060 and 8089** listening  
- [ ] Desk phones still REGISTER (UDP) within a few minutes  

**Rollback:** restore `/root/opensips.cfg.pre-w1.*`, restart; close 8089 if desired.

---

## Phase 6 — Signaling smoke

Webphone / JsSIP (browser):

```text
WSS:      wss://sbc.pbx3.com:8089/ws
SIP user: 8af9ee          (shortuid)
Domain:   dhbm8x.pbx3.com
Pass:     golden webrtc-1500.env (or lab copy)
```

- [ ] TLS handshake OK (browser devtools / `openssl s_client -connect sbc.pbx3.com:8089`)  
- [ ] WebSocket upgrades  
- [ ] REGISTER → **401** → REGISTER **200** (proxy-registrar; PBX auth)  
- [ ] OpenSIPS `location` shows contact with **transport=wss** (or equivalent)  
- [ ] Admin / MI logs show domain → setid → golden dispatcher as for desks  

Debug:

```bash
sudo tail -f /var/log/opensips.log   # or journalctl -u opensips -f
# On golden: asterisk verbose / pjsip logger for REGISTER traffic if relayed
```

---

## Phase 7 — Media smoke (bypass)

- [ ] Desk or second UA → webphone extension: ring + answer  
- [ ] Two-way audio  
- [ ] Confirm RTP **not** hairpinned on Magrathea: `tcpdump -ni any udp portrange 10000-20000` on Magrathea during call → **quiet or near-zero** related flows; golden and browser WAN do the media  
- [ ] Webphone → desk same  
- [ ] Audio lag comparable to direct golden WSS (not a product gate)  

---

## Phase 8 — Close-out

- [ ] Update this checklist snapshot table  
- [ ] Note live Magrathea deltas (if any) back into **`opensips.cfg.template`** enable docs  
- [ ] Merge PR **`w1-magrathea-wss` → main`** when stable  
- [ ] Optionally sunset / leave **`webrtc-wss`** as historical scaffold  
- [ ] pbx3 **`TODO` / `WEBRTC_WSS_LAB`**: Magrathea WSS done; residual clamp package multi-AZ / SPA line test  

---

## Technical notes (do not re-litigate mid-lab)

1. **Admin HTTPS ≠ SIP WSS** — nginx **:443** for Filament; OpenSIPS **:8089** for SIP-over-WSS. Shared LE name `sbc.pbx3.com` is OK if OpenSIPS can read the files.  
2. **Path `/ws`** — set via `proto_wss` `wss_resource`; browsers use full URL with path.  
3. **SDP** — for WSS/ICE, config **must not** run `fix_nated_sdp(rewrite-media-ip)` in a way that steals media onto the SBC (`route[SKIP_SDP_MEDIA_REWRITE]`). Desk UDP NAT rewrite for classic phones remains.  
4. **Relay to Asterisk** — same domain/dispatcher as UDP phones; media still needs WebRTC-capable home (PBX3 / last-gen SARK with WSS endpoints).  
5. **Older non-WSS Asterisk** — no audio without media gateway; out of W1.  

---

## Quick status for agent sessions

When landing mid-track: open this file → **Snapshot** table → jump to first empty `[ ]` phase. Do **not** enable on Magrathea without Phase 1.2 backup checked.
