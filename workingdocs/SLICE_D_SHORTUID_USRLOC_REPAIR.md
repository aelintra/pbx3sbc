# Slice D — Phone history redial: shortuid usrloc repair

**Status:** **Lab green** (2026-08-05). Product-locked A. Template + Magrathea live on branch **`slice-d-shortuid-usrloc-repair`**. Path 1 only (not Path 2).  
**Magrathea:** patched + restarted; backup `/root/opensips.cfg.pre-slice-d.20260805210656`. Desk redial hit: `rU=hb64kj rd=9wvvnb…` → username-only → `RELAY` to `74.83.26.203:5060`.  
**Desk matrix (affcot 1101 Snom ↔ duns 1002 Yealink):** forward site dial + **BYE both ways** clear correctly; **missed-call / history dialback both ways** (Yealink→Snom and Snom→Yealink).  
**Parent:** `pbx3/workingdocs/TENANT_SHORT_DIAL_REQUIREMENTS.md` §3.9.1  
**Sibling:** `SLICE_B_USRLOC_MISS_DISPATCHER.md` (Asterisk → `ext@fqdn` miss→dispatcher — **do not confuse**)

---

## Problem (lab-proven)

Snom (and similar) history redial keeps the **user** from CLIP (`hb64kj`) but rewrites **host** to the phone’s own registrar:

```text
INVITE sip:hb64kj@9wvvnb.pbx3.com   # caller tenant FQDN — wrong
From: <sip:59507r@9wvvnb.pbx3.com>  # caller identity — correct
```

Today Magrathea treats that like any phone→tenant INVITE: **no usrloc branch** (FQDN endpoint lookup is **Asterisk-only**), then `is_domain_local` → **`TO_DISPATCHER`** for **caller’s** home → Asterisk **404** (no local user `hb64kj`).

Slice B does **not** help: miss→dispatcher is gated on `$var(is_from_asterisk) == 1`.

Industry note (Snom call-log domain overwrite): mitigate with **PBX/SBC remap/canonicalize** — this slice.

---

## Why username-only is safe here

Fleet phone AoR user = **shortuid** (globally unique). That is the opposite of digit extensions (`1000` on many tenants), where username-only / `LIMIT 1` is **forbidden** — see `docs/guides/WHY-USERNAME-ONLY-LOOKUP.md` and `MULTIPLE-DOMAINS-SAME-USERNAME.md`.

**Gate:** only attempt username-only repair when `$rU` matches **fleet shortuid shape** and is **not digit-only**:

- Charset `0-9` + `bcdfghjkmnpqrstvwxyz` (no vowels / similar) — full-string match.
- **Must contain at least one letter** — so `1000`, `811002` (site-dial digits), E.164, etc. never take this path.
- **No fixed length** in OpenSIPS — generator length may change; hardcoding `== 6` would silently break history return.

All-digit shortuids (charset-legal but rare) would miss repair until the gate is refined; prefer letter-required over false positives on PrefixDial digits.

- **Parked:** Mod suid generator to discard all-digit returns and regen — logical easy fix; **no all-digit phone suids in fleet now**, so letter gate is enough for v1.

---

## Where it plugs in

**File:** `config/opensips.cfg.template` → `route[DOMAIN_CHECK]`

Today (simplified):

| Source | R-URI shape | Behaviour |
|--------|-------------|-----------|
| Asterisk | `user@IP` | endpoint lookup (domain from source IP / SQL) |
| Asterisk | `user@tenant.fqdn` | usrloc hit→phone; **miss→dispatcher** (Slice B) |
| Phone | `user@tenant.fqdn` | skip usrloc → **TO_DISPATCHER** caller home |

**Add** a phone-sourced branch **before** `TO_DISPATCHER` (same RELAY machinery as Asterisk→phone hit).

---

## Recommended pattern (Path 1 — direct RELAY) — **v1 coded**

v1 is **username-only only** (no domain-specific `lookup()` first). Shortuids are globally unique; skipping the big Asterisk usrloc clone keeps blast radius small. Same-tenant phone→`shortuid@$rd` still hits via username-only.

```text
INVITE from phone (is_from_asterisk != 1)
  && method INVITE && $rU != ""
  && $rd is tenant FQDN (not IP)
  && is_domain_local($rd)          # already true — call site is after that
  && $rU matches shortuid shape    # charset + has letter; no fixed length; not digit-only ext
→
  Auth: From registered on $fd; $si == COALESCE(received,contact) host
    miss From reg → return (TO_DISPATCHER)
    IP mismatch → 403 exit
  Username-only SQL (ORDER BY expires DESC LIMIT 1):
    Hit → set $ru/$du (NAT: prefer received) → route(RELAY); exit
    Miss → return (TO_DISPATCHER unchanged)
```

OpenSIPS: `route[SLICE_D_SHORTUID_REPAIR]` + one gated call in `route[DOMAIN_CHECK]` immediately before `route(TO_DISPATCHER)`.

**Reuse:** `GET_ENDPOINT_URI_PARAMS` + same Contact/`received` URI extract as wildcard path ~1013. Does **not** factor Asterisk→phone `lookup()` block.

### Auth / CDR caveats (Path 1)

Phone INVITEs today go to **caller home** first (401 then dialplan). Path 1 **bypasses caller Asterisk** for this leg:

- **Auth:** Harden — require From user registered and `$si` matches that Contact/`received` (or equivalent), so random INVITE `sip:foreign-suid@any-local-domain` cannot ring anyone without a live registered caller.
- **CDR / COS / recording:** May not see the call on caller home unless accounting elsewhere; accept for v1 or follow with Path 2 if ops require home CDR.
- **Media/NAT:** Same as existing station RELAY (force_rport / received) — regression-test Snom↔Snom.

---

## Alternate pattern (Path 2 — canonicalize domain → callee home)

Industry “remap/canonicalize” literally:

1. Username-only find registered **domain** for `$rU` (e.g. `dhbm8x.pbx3.com`).
2. Rewrite `$rd` / `$ru` to `sip:$rU@$registered_domain`.
3. Continue into `is_domain_local` + **`TO_DISPATCHER` for callee’s setid** (not caller’s).
4. Callee home PrepDial / station dial → Magrathea usrloc → phone.

**Pros:** Call still hits an Asterisk (ring groups, CDR on callee home).  
**Cons:** Must confirm Magrathea→callee-home identify trusts SBC IP with **foreign From** (caller identity); may need From rewrite similar to Slice B `sitedial` hairpin — design carefully. Prefer Path 1 unless Path 1 CDR/auth blocks ship.

---

## Explicit non-goals / do not

- Do **not** open Slice B miss→dispatcher for phone-sourced digit `ext@fqdn` (that was lab-fail; not this slice).
- Do **not** username-only lookup digit extensions (`1000`, `81xxxx`).
- Do **not** change REGISTER / `use_domain=1` / station dial hit path.
- Do **not** require reverse dial prefixes for callback (Q10).

---

## Lab smoke (after Magrathea reload)

1. Forward site dial still green (Slice B + PrefixDial).
2. Station dial `shortuid@fqdn` still usrloc→phone (Asterisk-sourced).
3. **D:** After inbound with CLID `suid@fqdn` (GenAst receive), Snom history redial → **Alice rings** (not 404 on Bob’s Asterisk). Capture: R-URI may still show Bob’s domain; Magrathea xlog should show username-only hit + RELAY.
4. Negative: dial unknown shortuid-shaped user → still 404 / no wrong Contact.
5. Negative: digit-only R-URI still goes to home Asterisk (no username-only).

---

## Deploy

Same as Slice B: merge **`config/opensips.cfg.template`** → Magrathea **`/etc/opensips/opensips.cfg`** (live often drifts — **diff before paste**) → `opensips-cli -x mi config_reload` (or restart per SOP). Commit template in **pbx3sbc**; do not leave Magrathea-only hot patch undocumented.

GenAst receive CLID = `suid@fqdn` is in **pbx3 `main`** (`GenClass` `SbcDomainRoute`). On golden: ensure dialplan regenerated (`genAst` / site SOP) so ring-leg CLIP still carries shortuid for Snom history user-part.

---

## Do not reinvent — already known

### Failed experiments (do not re-lab as “maybe phone will…”)

| Tried | Outcome |
|-------|---------|
| Bare ext CLIP (`1101`) | Redial local/wrong |
| CLIP = `ext@calling-tenant` | Phone→SBC≠Asterisk miss→dispatcher; no usrloc |
| CLIP = `suid@fqdn` alone | Snom **keeps user**, **rewrites domain** → still 404 without SBC repair |
| Snom Identity setting to preserve remote domain | None found; industry note confirms registrar anchor |
| DID-on-every-ext as sole fix | Cost / incomplete; not needed if A ships |
| Opening Slice B for phone-sourced INVITEs | Wrong gate; still wrong home |

### Lab fixtures (golden / Magrathea)

| Item | Value |
|------|--------|
| Magrathea | `3.93.26.82` (SBC VIP / lab edge) |
| Home | golden `08jzwn` |
| Pair | affcot `9wvvnb` ↔ duns `dhbm8x` |
| Prefix | `81` both ways (**reverse** dialalias duns→affcot is **lab DB only** — recreate if wiped) |
| Phones | affcot **1101** / `59507r` · duns **1002** / `hb64kj` (Snom D717) |
| Packages | golden pbx3 **0.0.4-8** / cagi **1.0.0-13** (Slice D is **SBC cfg**, not those debs) |

### Copy-from in `opensips.cfg.template` (line #s drift — search markers)

| Need | Search / area |
|------|----------------|
| Asterisk→FQDN usrloc + RELAY | `INVITE Asterisk→tenant FQDN` / `lookup("location")` in `DOMAIN_CHECK` |
| Username-only SQL (pattern to adapt) | `SELECT COALESCE(received, contact) FROM location WHERE username=` (wildcard fallback ~1013) — **add shortuid gate**; do not use for digit exts |
| Slice B miss→dispatcher | `usrloc miss for` / `fall through to domain dispatcher` — **leave gated on `is_from_asterisk`** |
| NAT Contact/`received` | same RELAY path as station dial |
| `is_from_asterisk` | `route[CHECK_IS_FROM_ASTERISK]` |

### Pre-flight SQL (Magrathea) before coding

```sql
-- Confirm unique username Contact for lab callee
SELECT username, domain, contact, received, expires
FROM location
WHERE username = 'hb64kj' AND expires > UNIX_TIMESTAMP();

-- Expect one row, domain = dhbm8x.pbx3.com (not 9wvvnb)
```

SIPp Domain / dual-host site-dial recipe: sipplab **`docs/examples/site-dial-lab.md`** (forward path). Desk D still needs real handset or a UAC that rewrites domain like Snom.

### Separate residual (hairpin BYE)

Earlier same-box site dial: **callee BYE did not always clear caller** (hairpin asymmetry). **Not caused by Path 1** (forward `81` never hits Slice D). Same Snom/Yealink pair, multiple tenant accounts. **2026-08-05:** hangups look OK now — **cause unknown**; watch / capture if it returns.

---

## Resume checklist for implementer

1. ~~Product-lock **A**~~ **done** (2026-08-05).  
2. ~~Implement Path 1 in `DOMAIN_CHECK` + auth gate~~ **done** (template + Magrathea).  
3. ~~Diff template → Magrathea live → reload → smoke~~ **lab green** (desk redial `hb64kj@9wvvnb` → RELAY).  
4. Commit/push branch `slice-d-shortuid-usrloc-repair` (pbx3sbc + pbx3 docs) when operator asks.
