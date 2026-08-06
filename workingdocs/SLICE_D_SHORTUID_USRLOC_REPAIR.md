# Slice D — Phone history redial: shortuid usrloc repair

**Status:** Spec lean / **not coded**. Product-lock option A before Magrathea change.  
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

- Length **6** (see `IDPWGEN_ROLLOUT_PLAN.md` / HelperClass shortuid).
- Charset `0-9` + `bcdfghjkmnpqrstvwxyz` (no vowels / similar).
- **Must contain at least one letter** — so `1000`, `811002` (site-dial digits), E.164, etc. never take this path.

All-digit shortuids (charset-legal but rare) would miss repair until the gate is refined; prefer letter-required over false positives on PrefixDial digits.

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

## Recommended pattern (Path 1 — direct RELAY)

```text
INVITE from phone (is_from_asterisk != 1)
  && method INVITE && $rU != ""
  && $rd is tenant FQDN (not IP)
  && is_domain_local($rd)          # caller’s registrar domain is ours
  && $rU matches shortuid shape    # has letter; not digit-only ext
→
  1. Domain-specific lookup: $ru = sip:$rU@$rd ; lookup("location")
     Hit → RELAY (same-tenant shortuid dial via SBC — rare but OK)
  2. Miss → username-only SQL (reuse existing location query style ~line 1013):
       SELECT domain, COALESCE(received, contact) FROM location
       WHERE username='$rU' AND expires > UNIX_TIMESTAMP()
       ORDER BY expires DESC LIMIT 1
     Hit → set $ru/$du to Contact (NAT: prefer received; same as Asterisk→phone path)
           route(RELAY); exit
     Miss → fall through TO_DISPATCHER (unchanged — local digits / 404)
```

Pseudo-OpenSIPS placement (illustrative — match live template idioms for `$du` / SQL fallback / NAT):

```opensips
# After Asterisk endpoint-lookup block; before R-URI/To domain mismatch + TO_DISPATCHER
if (is_method("INVITE") && $var(is_from_asterisk) != 1
    && $rU != "" && $var(ruri_host_is_ip) == 0
    && $(rU{s.len}) == 6 && $rU =~ "[a-z]") {
    # Prefer full shortuid charset check; letter required so 811002 never matches

    $var(original_ru) = $ru;
    $var(lookup_uri) = "sip:" + $rU + "@" + $rd;
    $ru = $var(lookup_uri);
    if (lookup("location")) {
        # … same hit handling as Asterisk→FQDN path → route(RELAY); exit
    }
    $ru = $var(original_ru);
    # username-only: SELECT … WHERE username='$rU' …
    # on contact hit → route(RELAY); exit
    # else continue (restore $ru) into existing TO_DISPATCHER
}
```

**Reuse:** Asterisk→phone hit path already has `lookup("location")` + SQL fallback + `route(RELAY)` (~830–1040). Prefer factoring a shared `route[ENDPOINT_RELAY_FROM_LOCATION]` over copy-paste; acceptable to clone-then-factor in lab.

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

### Separate residual (do not conflate with D)

Same-box site dial: **callee BYE does not always clear caller** (hairpin asymmetry). Track elsewhere; Path 1 may change BYE path — re-check after RELAY.

---

## Resume checklist for implementer

1. Product-lock **A** (this doc) vs **B** (no guarantee) in §3.9.1.  
2. Implement Path 1 in `DOMAIN_CHECK` + auth gate; update **template + Magrathea live**.  
3. Smoke list above on Magrathea + affcot↔duns Snom pair (`81`).  
4. Update this file **Status → lab green** + note Magrathea reload / any pbx3sbc commit.
