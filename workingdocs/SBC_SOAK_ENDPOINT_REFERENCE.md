# SBC soak — endpoint brand reference

**Status:** Reference (2026-07-09)  
**Purpose:** Canonical list of desk phones and softphones to exercise during **fleet SBC soak** (step 1 in **`pbx3/pbx3-directory/docs/FLEET_TRUNK_PEERING_DECISION.md`** §9).  
**Audience:** Ops, QA, implementers working on `sbc.pbx3.com` and future SBC pools.

**Related:** `PEERING-PLAN.md` · `QUICK-REFERENCES/SNOM-TROUBLESHOOTING.md` · `pbx3-directory/docs/ARCHITECTURE_REVIEW_SCORECARD.md` §8 (drill log)

---

## Primary soak list (UK experience + global)

Operator experience is **UK-centric**; **Grandstream** is included for North America, APAC, and LATAM; **Gigaset** for DACH/EU business installs (Siemens heritage — soak for market coverage, not preference).

### Desk phones (hardware)

| Priority | Brand | UK / EU | Other regions | Soak notes |
|:--------:|-------|---------|---------------|------------|
| **P1** | **Yealink** | Very common | Top tier globally | REGISTER/INVITE quirks; `:5060` in Request-URI seen on pilot (`8174dfe`) |
| **P1** | **Snom** | Very common | Strong in EU; weaker in NA | `line=` URI param on NAT rewrite; see `QUICK-REFERENCES/SNOM-TROUBLESHOOTING.md` |
| **P1** | **Fanvil** | Common (value tier) | Growing globally | Good UK/EU distributor presence; test REGISTER + re-INVITE/hold |
| **P2** | **Grandstream** | Less common than Yealink in UK | **Top tier NA / APAC / LATAM** | Add for international product soak; GXP/GRP series typical |
| **P2** | **Gigaset** | Common (DECT/IP business); seen in EU | Strong **DACH**; present UK/EU | Siemens-lineage provisioning/SIP habits; soak when EU/DACH customers exist |
| **P3** | **Poly** (Polycom) | Enterprise / UC | Enterprise globally | Teams editions differ from plain SIP; pilot when enterprise customer exists |
| **P3** | **Cisco** | Enterprise | Enterprise globally | 8800/9800 etc.; not default SMB hosted — pilot with enterprise seat |

### Softphones

| Priority | App | Notes |
|:--------:|-----|--------|
| **P1** | **Bria** (CounterPath) | Professional cross-platform; NAT and auth behaviour. **Qualify RTT outlier** — see quirks table + softphone-doc note below. |
| **P1** | **Zoiper** | Very common; good generic softphone soak |
| **P2** | **Linphone** | Open source; optional extra coverage |
| **P2** | Vendor apps | 3CX / other bundled clients — only when that deployment model is sold |

---

## Soak priority order (recommended)

Use this order unless a live customer forces a different brand first.

```text
1. Yealink
2. Snom
3. Fanvil
4. Bria + Zoiper
5. Grandstream          ← international coverage; UK may have few units
6. Gigaset              ← DACH/EU; legacy Siemens quirks — market coverage
7. Poly · Cisco           ← enterprise pilots only
```

**Per brand, minimum matrix:**

- REGISTER → SBC → node backend  
- Extension → extension (same tenant)  
- Extension → extension (cross-tenant via SBC, when multi-tenant)  
- Hold / transfer / re-INVITE (at least one scenario)  
- NAT path (phone behind consumer router)  
- Log **User-Agent**, **model**, **firmware** on first success

---

## Regional supplements (optional)

Not required for UK-first soak; add when targeting those markets.

| Region | Brands often seen beyond this list |
|--------|-----------------------------------|
| **France / EU enterprise** | ALE (Alcatel-Lucent Enterprise) |
| **APAC volume SMB** | Htek (alongside Yealink / Grandstream / Fanvil) |

**Gigaset** is on the primary list (P2) for DACH/EU — not relegated to “optional region only.”

Ground truth beats training data: log REGISTER User-Agent on production SBC over 90 days when available.

---

## Pilot validation log (PBX3)

| Date | Environment | Brands | Result | Notes |
|------|-------------|--------|--------|-------|
| 2026-07-08 | `sbc.pbx3.com` · tenant `dhbm8x` → Golden `08jzwn` | **Snom**, **Yealink** | **Pass** (ext ↔ ext) | `pbx3sbc` `8174dfe`; PSTN not tested |
| | | Fanvil | — | |
| | | Grandstream | — | |
| | | Gigaset | — | |
| | | Bria, Zoiper | — | |
| | | Poly, Cisco | — | |

Update this table as soak continues; mirror major milestones in **`pbx3-directory/docs/ARCHITECTURE_REVIEW_SCORECARD.md`** §8.

---

## Known vendor SIP quirks (fleet SBC)

| Brand | Quirk | PBX3 reference |
|-------|-------|----------------|
| Yealink | `:5060` in Request-URI; 401/407 auth relay | `pbx3sbc` `8174dfe`; `AGENT_HANDOFF.md` 2026-07-08 |
| Snom | `line=` param must survive NAT URI rewrite | `GET_ENDPOINT_URI_PARAMS`; `SNOM-TROUBLESHOOTING.md` |
| Snom / Yealink | NAT `received` vs `contact` on INVITE | `COALESCE(received, contact)` routing |
| All | Dispatcher hostname vs IP for `GET_DOMAIN_FROM_SOURCE_IP` | Store Asterisk **source IP** in dispatcher `attrs` — gate for peering Phase 1 |
| **Bria** | Contact user is `shortuid-<instance>` (hyphen); Asterisk OPTIONS that URI. Shortuid OPTIONS gate does not match → miss → local 200 → ~2–3 ms fake RTT. Even if relayed, `received` is CounterPath cloud (e.g. GCP), not the handset — RTT stays “short” by design. | `docs/guides/troubleshooting/OPTIONS-FAKE-RTT-MULTI-TENANT.md` (softphone outlier); lab: AoR `0fw2kw` |

Add rows here when new brands expose edge cases; link to session summary or commit.

### Softphone docs (when written)

Per-app operator / customer softphone guides should call out **Bria qualify latency** as an expected outlier: not a desk-phone RTT, and not the multi-tenant `LIMIT 1` bug (desk phones fixed via `OPTIONS_SHORTUID_USRLOC`). Do not chase “fix Bria RTT to match Yealink.”

---

## What soak does **not** replace

- **Carrier / PSTN peering** — `PEERING-PLAN.md` Phases 0–4 (after UDP extension path is boring)  
- **WebRTC / WSS** — Phase W1; interim node `:8089` for pilot fleets  
- **TLS / SRTP phones** — deferred fleet v1; document when W1 starts  

---

## References

| Doc | Role |
|-----|------|
| `FLEET_TRUNK_PEERING_DECISION.md` §9 | Locked implementation order (soak = step 1) |
| `PEERING-PLAN.md` | Carrier path after soak |
| `ARCHITECTURE_REVIEW_SCORECARD.md` | Drill pass criteria and log |
| `pbx3/workingdocs/TODO.md` | Suggested “what next?” order |
