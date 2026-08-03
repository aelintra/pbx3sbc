# WebRTC WSS on Magrathea (W1) — operator checklist

**Goal:** SIP over **WSS terminates on Magrathea** (VIP / `sbc.pbx3.com`); OpenSIPS relays **ordinary SIP UDP** to the home fleet instance; **RTP bypass** — browser ICE/DTLS-SRTP ↔ home Asterisk. Desk UDP **:5060** unchanged.  
**Home TCP 8089:** **not required** for Magrathea clients — golden lab closed instance **8089** entirely and edge WSS calls still work (2026-08-03).

**Architecture (why this is the product shape):**

```text
Browser ──WSS :8089──► Magrathea ──SIP UDP :5060──► Home Asterisk (dispatcher)
                                                              │
Browser ◄════════ media (bypass SBC) ═════════════════════════╝
```

Home “WebRTC” PJSIP = **UDP + outbound_proxy + webrtc=yes** (not instance `transport-wss` for edge users). See **`WEBRTC_WSS_LAB.md`** § Fleet edge W1 architecture.

**Not in scope:** rtpengine, multi-AZ proof, SPA line-test product, Magrathea desk SIP TLS (`5061`).  
**Spec:** **`pbx3/pbx3-directory/docs/FLEET_TRUNK_PEERING_DECISION.md`** §6.1 · lab notes **`pbx3/workingdocs/WEBRTC_WSS_LAB.md`** · branch work landed on pbx3sbc **`main`**.

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

### Snapshot (2026-08-03 — **lab green**)

| Phase | Status |
|-------|--------|
| **0** Goal + constraints locked | **[x]** |
| **1** Git branch + recovery discipline | **[x]** branch; **[x]** Magrathea backup |
| **2** Repo config / scripts ready | **[x]** |
| **3** Packages + cert on Magrathea | **[x]** |
| **4** Firewall / SG | **[x]** UFW **8089**; SG open |
| **5** Enable WSS in live `opensips.cfg` | **[x]** UDP **5060** + WSS **8089** |
| **6** Smoke: REGISTER + dialog over WSS | **[x]** |
| **7** Smoke: audio (RTP not on SBC) | **[x]** desk↔webphone both ways, audio OK (2026-08-03 lab) |
| **8** Document + merge `main` | **[x]** merged to main 2026-08-03 |

**Live enable snapshot (2026-08-03):**
- Modules: `opensips-wss-module`, `opensips-tls-openssl-module`, `opensips-tlsmgm-module`
- Cert: `/etc/opensips/tls/sbc.pbx3.com-{fullchain,privkey}.pem` (from LE; renew hook re-copies)
- Config backups: `/root/opensips.cfg.pre-w1.20260803163707`, `/root/opensips.cfg.pre-w1-enable.20260803164214`
- Local TLS: `openssl s_client` → **CN=sbc.pbx3.com**

**Home-node product bits that made Phase 7 work (pbx3 / pbx3cagi, not Opensips alone):**

| Piece | Why |
|-------|-----|
| `pjsip_webrtc.tmpl`: **`transport-udp`** + fleet **`$outbound_proxy`** (`sip:sbc.pbx3.com;lr`) | Tenant FQDN often **A-points at home EIP**; without proxy Dial hairpins (`No matching endpoint` + no outbound_auth). Same path as desk phones. |
| **PrepDial** fleet: always `PJSIP/shortuid/sip:shortuid@tenant.fqdn` (**including WebRTC**) | SIP.js Contact `@192.0.2.x;transport=wss` is unroutable from Asterisk; Magrathea **usrloc** has the real WSS connection. |
| OpenSIPS Asterisk→phone INVITE **usrloc** path | Already used for desks; WSS contacts use `socket=wss:…:8089`. |

Singleton / instance-direct WSS (`wss://instance:8089`) remains valid for lab without fleet edge (overlay `transport-wss` if needed). **Fleet Magrathea clients: close instance TCP 8089.**

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

- [x] Branch **`w1-magrathea-wss`** exists  
- [ ] Remote pushed (`git push -u origin w1-magrathea-wss`)  
- [ ] Optional: git tag on last known-good deployed cfg parent after backup  

### 1.2 Magrathea backup

- [x] `backup-sbc.sh` → **`sbcbak.1785775027.zip`**; S3 `s3://08jzwn-pbx3/sbc/sbc/backups/20260803T163707Z/backup.zip`  
- [x] Live **`opensips.cfg`** copies **`/root/opensips.cfg.pre-w1.*`**  
- [x] Desk UDP path stayed up through enable  

**Recovery if WSS enable goes wrong:** restore pre-w1 `opensips.cfg`, restart OpenSIPS, close SG 8089 if desired.

---

## Phase 2 — Repo work (agent / this branch)

- [x] This checklist  
- [x] Template: optional **`proto_wss` / `tls_mgm` / socket `wss:…:8089`** block (default **commented**)  
- [x] Template: **`route[SKIP_SDP_MEDIA_REWRITE]`** for WSS/WS and ICE SDP (RTP bypass)  
- [x] Script: **`scripts/setup-opensips-wss.sh`**  
- [x] Cert renew notes for OpenSIPS after LE renew  
- [x] `opensips -C` + service up on Magrathea  
- [x] Merged **`w1-magrathea-wss` → `main`** 2026-08-03  

---

## Phase 3 — Magrathea packages + TLS material

- [x] WSS + TLS modules installed  
- [x] Certs under `/etc/opensips/tls/` readable by OpenSIPS  
- [x] Renew path re-copy documented / hook notes  

---

## Phase 4 — Network

- [x] SG 8089 open for lab  
- [x] Host UFW 8089 open  
- [x] Desk 5060 still reaches Magrathea  
- **Note:** Magrathea UDP **10000–20000** **not** required for RTP bypass  

---

## Phase 5 — Enable in live config

- [x] WSS block live; **5060 and 8089** listening  
- [x] Desk phones still REGISTER (UDP)  

**Rollback:** restore `/root/opensips.cfg.pre-w1.*`, restart; close 8089 if desired.

---

## Phase 6 — Signaling smoke

```text
WSS:      wss://sbc.pbx3.com:8089/ws
SIP user: 8af9ee          (shortuid)
Domain:   dhbm8x.pbx3.com
Pass:     golden webrtc-1500.env
```

- [x] TLS handshake OK  
- [x] WebSocket upgrades (`Origin` + `Sec-WebSocket-Protocol: sip` as OpenSIPS requires)  
- [x] REGISTER → **401** → **200** (proxy-registrar; PBX auth)  
- [x] OpenSIPS `location` contact with **transport=wss**  

---

## Phase 7 — Media smoke (bypass)

- [x] Desk → webphone (1500 / `8af9ee`): ring + answer + two-way audio  
- [x] Webphone → desk: same  
- [x] Failures seen along the way (fixed):
  - **No FQDN Dial** → Asterisk “No route” on dummy Contact → VM  
  - **FQDN Dial without outbound_proxy** → tenant DNS A = home EIP hairpin → “No matching endpoint” / “no auth ids available”  
- [ ] Optional: `tcpdump` on Magrathea UDP 10000–20000 quiet during call (proves bypass; not a gate)

---

## Phase 8 — Close-out

- [x] Snapshot table updated (lab green)  
- [x] Home-node fixes noted (tmpl + PrepDial)  
- [x] Merged **`w1-magrathea-wss` → main`** 2026-08-03  
- [x] Optional sunset note: **`webrtc-wss`** remains historical scaffold  
- Residual: clamp instance SG **8089**; package rolls (pbx3 webrtc tmpl, pbx3cagi **1.0.0-10**); multi-AZ; SPA line test  

---

## Technical notes (do not re-litigate mid-lab)

1. **Admin HTTPS ≠ SIP WSS** — nginx **:443** for Filament; OpenSIPS **:8089** for SIP-over-WSS. Shared LE name `sbc.pbx3.com` is OK.  
2. **Path `/ws`** — `proto_wss` `wss_resource`; browsers use full URL with path.  
3. **SDP** — must not run `fix_nated_sdp(rewrite-media-ip)` for WSS/ICE (`route[SKIP_SDP_MEDIA_REWRITE]`).  
4. **Relay to Asterisk** — same domain/dispatcher as UDP phones.  
5. **WebRTC endpoint transport** — fleet: **UDP + outbound_proxy to SBC**, not transport-wss-only (that is for direct instance WSS).  
6. **Tenant FQDN in public DNS** — optional for SIP identity; may point at home (as lab) or edge; Dial always goes via **outbound_proxy** first on fleet.  

---

## Quick status for agent sessions

When landing mid-track: open this file → **Snapshot** table. Lab is **green**. Remaining = merge branch + package rolls + residual lab (clamp 8089 / multi-AZ).
