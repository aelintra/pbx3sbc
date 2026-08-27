# OPTIONS fake RTT on multi-tenant homes

**Symptom:** Asterisk `pjsip show contacts` shows ~2–5 ms RTT for some desk phones and ~20–40+ ms for others on the **same physical device** (same `x-ast-orig-host`). Disabling other tenants’ lines does not change the short RTT.

**Cause:** Asterisk qualifies with `OPTIONS sip:{shortuid}@{sbc-vip}`. OpenSIPS used `GET_DOMAIN_FROM_SOURCE_IP` → `SELECT domain FROM domain WHERE setid=… LIMIT 1`. On a multi-tenant node that picks one tenant (often the first registered domain). Lookup `shortuid@wrong-domain` misses → OpenSIPS answers **local 200 OK** (~1 ms). Asterisk measures SBC RTT, not desk RTT; OPTIONS never reach the phone (NAT pinhole relies on REGISTER only).

**Fix (config):** For shortuid-shaped users when To/RURI domain is VIP/IP, use **username-only** `location` lookup (shortuids are globally unique — same gate as Slice D), then `RELAY`. Digit extensions still use the LIMIT-1 domain path.

**Verify:** `tcpdump` on the SBC — OPTIONS for a non-winning-tenant shortuid must leave toward the phone’s public IP; contact RTT should rise to desk-like values.

**Template:** `route[OPTIONS_SHORTUID_USRLOC]` in `config/opensips.cfg.template`.

---

## Softphone outlier — Bria (CounterPath)

**Not the same bug.** Desk shortuids are fixed. **Bria** still often shows ~2–3 ms Avail RTT:

1. Registered Contact user is `shortuid-<hex-instance>` (hyphen). Qualify OPTIONS use that user; the shortuid charset gate does not match → legacy miss → local 200.
2. Even with a relay, usrloc `received` is typically **Bria’s cloud SBC** (not the handset). Path is Asterisk → our SBC → CounterPath edge; downstream is hidden.

**Product/docs:** When writing per-softphone documentation, surface Bria qualify latency as an **expected outlier** (see `workingdocs/SBC_SOAK_ENDPOINT_REFERENCE.md` — Softphone docs note). No plan to strip `-instance` for OPTIONS unless ops later wants “honest cloud-edge RTT.”
