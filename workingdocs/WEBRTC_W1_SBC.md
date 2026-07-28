# WebRTC WSS on SBC (W1) — scratch lab recipe

**Status:** Config scaffold on branch **`webrtc-wss`** (pbx3sbc). **Do not** enable on Magrathea VIP until cutover.  
**Related:** **`FLEET_TRUNK_PEERING_DECISION.md`** §6.1 · pbx3 **`WEBRTC_WSS_LAB.md`** · recovery **`pre-webrtc-wss-20260728`**.

## Golden baseline (done 2026-07-28)

| Check | Result |
|-------|--------|
| Asterisk `:8089` HTTPS/WSS | Listening (LE perms + Shorewall tcp 8089) |
| JsSIP REGISTER `1500@dhbm8x` | **OK** (on-box via loopback; EIP hairpin from instance fails) |
| Full media INVITE from Node | N/A — needs browser RTCPeerConnection; use webphone next |

External client URL: `wss://08jzwn.pbx3.com:8089/ws`  
Creds: golden `/home/ubuntu/webrtc-1500.env`

## Scratch SBC (next)

1. **Stand up** throwaway EC2 (Graviton OK) with pbx3sbc install — **own EIP**, not Magrathea VIP.  
2. **Packages:** OpenSIPS `proto_wss` + TLS stack (`tls_openssl`/`tls_mgm` — match distro package names).  
3. **LE** for scratch FQDN (or reuse lab name); readable by opensips user.  
4. Uncomment WSS block in `opensips.cfg` (from template on this branch); set cert paths; `socket=wss:0.0.0.0:5062`.  
5. **Firewall:** Shorewall + SG allow **tcp 5062** from operator IP.  
6. Point domain `dhbm8x.pbx3.com` dispatcher setid → golden (same as Magrathea lab domains) **or** add a lab-only domain for WebRTC.  
7. Webphone: `wss://<scratch-fqdn>:5062` → REGISTER should land in OpenSIPS usrloc; Asterisk auth still on home node (proxy-registrar).  
8. Prove call audio (RTP bypass to golden).  

## Magrathea cutover (later)

Booked window: enable same WSS block on VIP host, Shorewall 5062, SG, LE for `sbc.pbx3.com` (or dedicated SIP name). Keep UDP 5060 phones unchanged.

## Operator ask

Provide or approve **scratch SBC host** (instance id / EIP / SSH user+key) before deploy. Config-only work can continue on **`webrtc-wss`** without it.
