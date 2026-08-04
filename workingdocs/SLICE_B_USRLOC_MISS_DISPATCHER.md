# Slice B — OpenSIPS usrloc miss → dispatcher

**Status:** Implemented in `config/opensips.cfg.template` (tenant short dial Q11).

## Behaviour

For **INVITE from a fleet Asterisk** (`is_from_asterisk`) with **R-URI host = tenant FQDN** (not a bare IP):

1. **usrloc lookup** for `user@domain` (unchanged station path).
2. **Hit** → RELAY to phone Contact (shortuid AoR / PrepDial).
3. **Miss** → restore original Request-URI and continue **domain → dispatcher setid → hosting Asterisk**.
4. **CLIP / identify (required on miss):**
   - **`X-PBX3-Pres-Num`:** presentation digits (From user before rewrite — usually extension).
   - **`P-Asserted-Identity`:** return AoR — keep if already set by Asterisk (PrefixDial `b(pbx3-site-pai)` → `sip:suid@tenant.fqdn`); else copy original From URI.
   - **`From` user → `sitedial`** (same domain): home Asterisk is `username,ip` ordered; bare shortuid as From user would match a local phone and **401** the unauth hairpin. IP identify → Egress; dialplan restores presentation from `X-PBX3-Pres-Num` and stashes AoR in `__PBX3_RETURN_AOR`.

Same-node “hairpin” via dispatcher is **correct** for `sip:1000@tenant.fqdn` (PrefixDial). Cross-node uses the same path to the other home.

Does **not** open miss→dispatcher for:

- Phone/non-Asterisk callers (no path B endpoint lookup).
- Legacy **IP R-URI** Asterisk→Contact dials (still 404 if contact missing).

## Operator deploy (lab Magrathea)

1. Diff / copy template merge into live `/etc/opensips/opensips.cfg` (or your render path).
2. `opensips-cli -x mi config_reload` or full restart per site SOP.
3. Probe: from Asterisk, INVITE `sip:1000@dhbm8x.pbx3.com` where `1000` is **not** a registered shortuid → should arrive on home Asterisk, not SBC 404.
4. Regression: INVITE `sip:{shortuid}@dhbm8x.pbx3.com` still rings the phone (usrloc hit).

See **`pbx3/workingdocs/TENANT_SHORT_DIAL_REQUIREMENTS.md`** §3.6, slice B.
