# OPTIONS fake RTT on multi-tenant homes

**Symptom:** Asterisk `pjsip show contacts` shows ~2–5 ms RTT for some desk phones and ~20–40+ ms for others on the **same physical device** (same `x-ast-orig-host`). Disabling other tenants’ lines does not change the short RTT.

**Cause:** Asterisk qualifies with `OPTIONS sip:{shortuid}@{sbc-vip}`. OpenSIPS used `GET_DOMAIN_FROM_SOURCE_IP` → `SELECT domain FROM domain WHERE setid=… LIMIT 1`. On a multi-tenant node that picks one tenant (often the first registered domain). Lookup `shortuid@wrong-domain` misses → OpenSIPS answers **local 200 OK** (~1 ms). Asterisk measures SBC RTT, not desk RTT; OPTIONS never reach the phone (NAT pinhole relies on REGISTER only).

**Fix (config):** For shortuid-shaped users when To/RURI domain is VIP/IP, use **username-only** `location` lookup (shortuids are globally unique — same gate as Slice D), then `RELAY`. Digit extensions still use the LIMIT-1 domain path.

**Verify:** `tcpdump` on the SBC — OPTIONS for a non-winning-tenant shortuid must leave toward the phone’s public IP; contact RTT should rise to desk-like values.

**Template:** `route[OPTIONS_SHORTUID_USRLOC]` in `config/opensips.cfg.template`.
