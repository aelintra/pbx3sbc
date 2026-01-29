# Peering / Trunk Routing – Planning Document

**Branch:** peering  
**Status:** Planning only – no code changes yet  
**Goal:** Route calls to and from external gateways (trunks, peers, carriers).

---

## 1. Objective

- **Inbound:** Calls from carriers (identified by source IP) with RURI = DID → map DID (or DID group by **prefix**) to internal destination (e.g. backend Asterisk).
- **Outbound:** Calls from **backend PBX only** (for now, Asterisk). OpenSIPS receives INVITE from Asterisk with PSTN RURI → select carrier gateway by prefix and relay.

Call direction is distinguished by **source** and **destination length**. Different logic blocks apply to each.

**Design decisions (locked in):**
- **Outbound origin:** Always from backend PBX (Asterisk). Outbound-to-carrier traffic is Asterisk → OpenSIPS with PSTN RURI.
- **PSTN vs internal by digit length:** Outbound PSTN destination is always **longer than 7 digits**. Internal endpoint numbers are **6 digits or less**. So when request is from Asterisk, use `$rU` length to decide "to PSTN" (→ carrier) vs "to internal" (→ endpoint lookup).
- **Inbound DID:** Prefer **DID groups** by **prefix** (e.g. 19249181 → block of numbers route to same backend Asterisk). Prefix will likely suffice; regex deferred. Alias can still resolve one-off DIDs.
- **Multi-tenant:** The system **will be multi-tenant**: it serves **multiple backend Asterisk instances**, each of which may itself be multi-tenant (multiple number ranges, etc.). Peering (carriers, DIDs, outbound groups) must be scoped per tenant/domain using **dr_groups** (username, domain, groupid) aligned with existing domain/setid. Design for per-tenant carrier lists, DID groups, and outbound groups from Phase 1/4.
- **Ownership:** Schema and scripts live in **pbx3sbc**. **pbx3sbc-admin** only maintains data in the tables (CRUD).

---

## 2. Concepts from Reference Snippets

### 2.1 Identifying call direction

| Direction   | Origin                    | Identification                                                                 |
|------------|----------------------------|-------------------------------------------------------------------------------|
| **Inbound**  | External carrier           | Source IP in predefined carrier gateway list; no registered user session.   |
| **Outbound** | Local / internal           | After successful auth/registration check, or source in internal network.     |

### 2.2 Script structure (conceptual)

- **Outbound:** `is_uri_local()` + auth, then **`do_routing(groupid)`** for carrier selection (e.g. groupid **0** for default outbound).
- **Inbound:** `src_ip` in carrier set (via **`is_from_gw(-1, "n")`**), then **`do_routing(groupid)`** for DID groups (e.g. groupid **1** for inbound) or alias/lookup for one-off DIDs.
- **Other:** REGISTER, OPTIONS, etc. handled in existing logic.

**Note:** OpenSIPS 3.6 drouting uses **`do_routing(groupID)`** (not `dr_route`). Use numeric group IDs: **0** = outbound carrier rules, **1** = inbound DID rules (see §4.3).

### 2.3 Number-based (prefix) routing

- Routing is by **number (username)** via prefix match on destination, not by domain.
- **drouting (Dynamic Routing):** prefix + group in DB (`dr_rules`, `dr_gateways`); longest prefix match; supports per-user/origin rules.
- **carrierroute:** match on Request-URI username vs `scan_prefix` in DB; good for large prefix tables.
- **Script:** use `$rU` (and optionally `$fu`) with conditions or **`do_routing(groupid)`**.

### 2.4 Dynamic Routing (drouting) roles in snippets

- **Outbound (groupid 0):** Rules select external carrier gateway by dialed prefix (RURI / To). Script: `do_routing("0")`.
- **Inbound DID (groupid 1):** Rules map incoming DID (RURI) to internal extension, PBX, or service. Script: `do_routing("1")`.

So: separate routing groups and DB data for "which carrier to use for outbound" vs "which internal target for this DID on inbound". See §4.3 for group ID constants.

---

## 3. Current Architecture (pbx3sbc)

- **dispatcher:** Used only for **Asterisk backends**. Domain → `setid` → `ds_select_dst(setid)` → healthy Asterisk. No drouting/carrierroute today.
- **Main route flow (simplified):**
  1. Hygiene (maxfwd, scanner), in-dialog → WITHINDLG, method allowlist.
  2. CANCEL → RELAY.
  3. OPTIONS/NOTIFY: if source = dispatcher (Asterisk) → endpoint lookup; else → DOMAIN_CHECK.
  4. REGISTER / INVITE (not from Asterisk to endpoint): DOMAIN_CHECK (domain + door-knocker) → TO_ASTERISK (dispatcher).
  5. INVITE with RURI like `user@IP`: from Asterisk to endpoint → GET_DOMAIN_FROM_SOURCE_IP, lookup(location), RELAY.

So today we have:

- **Internal:** Endpoints (usrloc) ↔ OpenSIPS ↔ Asterisk (dispatcher).
- **No carrier/trunk layer yet:** no "carrier IP list", no DID mapping, no outbound carrier selection.

Peering adds a **carrier/trunk** layer: carrier IPs, DID mapping (inbound), prefix→carrier (outbound).

---

## 4. Where Peering Fits in the Route Block

Order of checks matters; existing behaviour (REGISTER, OPTIONS/NOTIFY, Asterisk↔endpoint) must stay.

- **Inbound from carrier:**  
  - **When:** Early, for INVITE (and possibly other dialog-forming methods) from known carrier IPs.  
  - **Condition:** Use drouting **`is_from_gw(-1, "n")`** to test if source IP is a known gateway (carrier).  
  - **Action:** RURI = DID → resolve via INBOUND_DID_GROUP (or alias/lookup) → internal destination → relay (e.g. to Asterisk or usrloc).  
  - **Place:** Before or alongside DOMAIN_CHECK; must not be confused with "from Asterisk" (dispatcher) or "from endpoint."

- **Outbound to carrier:**  
  - **When:** Request **from Asterisk** (source = dispatcher) with destination = PSTN (external number).  
  - **Condition:** Source is Asterisk (dispatcher) **and** `$rU` length **> 7 digits** → treat as "to PSTN"; route to carrier via drouting/carrierroute.  
  - **Action:** **`do_routing("0")`** (outbound groupid 0) → relay to chosen gateway.  
  - **Internal (Asterisk → endpoint):** Same source (Asterisk), but `$rU` length **≤ 6 digits** (and RURI often user@IP) → existing flow: GET_DOMAIN_FROM_SOURCE_IP, lookup(location), RELAY.  
  - **Place:** Branch **after** we know request is from Asterisk; use digit length on `$rU` to split "to PSTN" vs "to internal endpoint."

**Resolved:** Outbound always from Asterisk; use `$rU` length > 7 digits for "to PSTN" vs ≤ 6 for "to internal endpoint."

### 4.1 Route block order (insertion points)

To avoid breaking REGISTER, OPTIONS/NOTIFY, or internal routing, peering branches go at these locations in `route {}`.

**Summary**

| Branch | When | Insert after | Insert before |
|--------|------|--------------|---------------|
| **From carrier?** | INVITE from carrier | Initial sanity (maxfwd, loose_routing) and **OPTIONS** handler (e.g. `if (is_method("OPTIONS")) { ... exit; }`) | **REGISTER** handler (`if (is_method("REGISTER"))`) |
| **To PSTN?** | From Asterisk, PSTN number | Logic that identifies request as **from Asterisk** (dispatcher / source check) | Final `t_relay()` or dispatcher for **internal** (Asterisk→endpoint) path |

**1. "From carrier?" (early)**

- **Goal:** Run only for INVITE and only when source is a known carrier (`is_from_gw(-1, "n")`), without touching REGISTER or OPTIONS.
- **Location:** Inside `route {}`, **after** maxfwd (and optional loose_routing) and **after** OPTIONS handling, **before** `if (is_method("REGISTER"))`.
- **Why:** After basic sanity and OPTIONS reply, but before registration and local-user logic. Only INVITEs from dr_gateways (carrier IPs) hit the carrier path; endpoints and Asterisk are not in dr_gateways so they fall through.

**Sketch:**

```opensips
# --- Existing: maxfwd, OPTIONS → 200 OK, exit ---

# --- [INSERT] From carrier? (early) ---
if (is_method("INVITE") && is_from_gw(-1, "n")) {
    route(FROM_CARRIER);
    exit;
}
# ---

# --- Existing: REGISTER, then INVITE / DOMAIN_CHECK / etc. ---
```

**2. "To PSTN?" (late)**

- **Goal:** Run only when the request is from Asterisk and the dialed number is PSTN (`$rU` length > 7).
- **Location:** Inside the block that already treats the request as **from Asterisk** (e.g. after dispatcher/source check), **before** the branch that does GET_DOMAIN_FROM_SOURCE_IP + lookup + relay to endpoint.
- **Why:** So we only send to PSTN when we know the source is Asterisk and the number is long; internal (≤6 digits) stays on the existing Asterisk→endpoint path.

**Sketch:**

```opensips
# ... already in "from Asterisk" branch ...

# --- [INSERT] To PSTN? (from Asterisk, long number) ---
if (is_method("INVITE") && $rU =~ "^[0-9]{8,}") {
    if (!do_routing("0")) { send_reply(404, "No Route"); exit; }
    t_on_failure("DR_FAILOVER");
    t_relay();
    exit;
}
# ---

# --- Existing: Asterisk → endpoint (GET_DOMAIN_FROM_SOURCE_IP, lookup, t_relay) ---
```

(Alternatively use `$rU` length > 7 in script logic instead of regex; same condition.)

**3. FROM_CARRIER route block**

- **Goal:** Inbound from carrier → DID resolution → relay to Asterisk (or alias/lookup for one-off).
- **Content:** In `route[FROM_CARRIER]`: DID resolution (e.g. **`do_routing("1")`** for inbound DID prefix groups; optionally **`alias_db_lookup("dbaliases", "d")`** for one-off); then relay to the chosen destination (gateway address from dr_gateways = Asterisk). Do **not** use `is_uri_host_local()` to choose "TO_ENDPOINT vs TO_PSTN" here; our model is carrier→DID→Asterisk (or alias→internal).

**Risks and how this order avoids them**

| Risk | Mitigation |
|------|-------------|
| Breaking REGISTER/OPTIONS | "From carrier?" runs only for INVITE and only after OPTIONS has been handled and exited. REGISTER block is never skipped. |
| Treating endpoint or Asterisk as carrier | `is_from_gw(-1, "n")` matches only source IPs in dr_gateways (carriers). Internal endpoints and Asterisk IPs are not in dr_gateways. |
| Sending internal calls to PSTN | "To PSTN?" runs only in the branch that is already "from Asterisk" and only when `$rU` length > 7. Short numbers (≤6) stay on Asterisk→endpoint path. |
| Sending carrier DID to wrong destination | FROM_CARRIER uses dr_rules (DID prefix → gwlist) and optionally alias_db; relay to the gateway (Asterisk) returned by do_routing. |

**Note:** In the "From carrier?" sketch we use `is_from_gw(-1, "n")` (type -1 = all gateway types; flag n = ignore port). Use a specific type (e.g. 1) instead of -1 if you restrict carrier gateways to one type in dr_gateways.

### 4.2 Current config (opensips.cfg.template) – actual structure

The following reflects the **current** `config/opensips.cfg.template` so insertion points can be tied to real line numbers. (Line numbers may shift slightly after edits.)

**Main `route {}` (starts ~line 260)**

1. Logging, SDP log (~261–268).
2. **maxfwd** (~272–282): `mf_process_maxfwd_header(10)`; 483 on failure.
3. Scanner drop (~287–297).
4. **has_totag()** (~302–305): `route(WITHINDLG); exit;`.
5. Method allowlist (~310–319): REGISTER|INVITE|ACK|BYE|CANCEL|OPTIONS|NOTIFY|SUBSCRIBE|PRACK.
6. **CANCEL** (~325–336): `route(RELAY); exit;`.
7. **OPTIONS|NOTIFY** (~340–598): Large block. If OPTIONS/NOTIFY, checks “from dispatcher?” and “R-URI like endpoint?”; if yes, lookup and `route(RELAY); exit;`. If **no**, **falls through** (no “reply 200 and exit” for generic OPTIONS).
8. **REGISTER** (~600–683): If REGISTER, NAT fix, then `route(DOMAIN_CHECK)` at ~683.
9. **route(DOMAIN_CHECK)** (~683): All other requests (including INVITE that didn’t match above) go here.

**Implications**

- There is **no** single “if OPTIONS reply 200 exit” at the top. OPTIONS/NOTIFY that are **not** “Asterisk→endpoint” fall through to the REGISTER check (false) and then to `route(DOMAIN_CHECK)`.
- **“From carrier?”** must run only for **INVITE** (`is_method("INVITE") && is_from_gw(-1, "n")`), so OPTIONS from carrier just fall through and are handled later (e.g. DOMAIN_CHECK or 404).

**Insertion points in this file**

| Branch | Insert after | Insert before | Line range (approx.) |
|--------|--------------|---------------|----------------------|
| **From carrier?** | End of OPTIONS/NOTIFY block (after the `}` that closes the block, so after “continuing normal routing” and the closing `}`). | Start of REGISTER block (`if (is_method("REGISTER"))`). | **After ~598, before ~600** |
| **To PSTN?** | Method is INVITE and we know “from Asterisk”. Best: **in main route, before `route(DOMAIN_CHECK)`** so PSTN calls never hit domain/setid. Need “from Asterisk” = source IP in dispatcher (e.g. same query as GET_DOMAIN_FROM_SOURCE_IP, or dispatcher module’s source check if available). | `route(DOMAIN_CHECK);` (~683). | **Before ~683** (e.g. after REGISTER block, ~681): `if (is_method("INVITE") && $rU length > 7 && source_in_dispatcher) { do_routing("0"); ... t_relay(); exit; }` |

**“From Asterisk” for To PSTN:** The config uses **GET_DOMAIN_FROM_SOURCE_IP** (query by `$si` to get setid/domain). Reuse that idea: before DOMAIN_CHECK, if INVITE and `$rU` length > 7, run the same “source IP → dispatcher set” check (or a dedicated helper). If source is in a dispatcher set, treat as “from Asterisk” and run `do_routing("0")`, `t_on_failure("DR_FAILOVER")`, `t_relay(); exit;`. Otherwise continue to `route(DOMAIN_CHECK)`.

### 4.3 Group IDs for config build (implementation constants)

Use these **numeric group IDs** in `dr_rules` and in script calls to **`do_routing()`** so the builder has a single source of truth:

| Purpose | groupid | Script call | dr_rules.groupid |
|---------|---------|-------------|-------------------|
| **Outbound** (Asterisk → PSTN carrier) | **0** | `do_routing("0")` | 0 |
| **Inbound DID** (carrier → Asterisk by prefix) | **1** | `do_routing("1")` | 1 |

- **Outbound:** `dr_rules` with `groupid = 0` and prefix/dialed number → `gwlist` = carrier gateway IDs.
- **Inbound:** `dr_rules` with `groupid = 1` and DID prefix → `gwlist` = internal gateway ID(s) (Asterisk in dr_gateways).

Do **not** use the string "INBOUND_GROUP" or "OUTBOUND_GROUP" in script; use **"0"** and **"1"** (or variables set to these).

---

## 5. Module and Data Model Options

**Decision: use drouting (Dynamic Routing).** For OpenSIPS 2.2+, drouting is the recommended choice over carrierroute. Do not use both for the same routing.

### 5.0 New modules for peering (summary)

| Module | Purpose | When added | Required? |
|--------|---------|------------|-----------|
| **drouting** | Carrier gateways (`dr_gateways`), prefix rules (`dr_rules`), outbound carrier selection, inbound carrier ID (**`is_from_gw(-1, "n")`**), inbound DID groups. Functions: `do_routing()`, `use_next_gw()`, `is_from_gw()`. | Phase 0 | **Yes** |
| **alias_db** | One-off DID → internal (alias_username/alias_domain → username/domain). Function: **`alias_db_lookup(table_name, [flags])`** (3.6). Used when DID is not in any `dr_rules` prefix group. | Phase 5 | Optional (only if one-off DIDs are needed) |
| **uac_registrant** | Outbound registration (OpenSIPS → carrier). Registers OpenSIPS with the carrier so the carrier can deliver inbound calls. **Table:** default `registrant` (modparam `table_name`). Key columns: **registrar** (carrier URI), **aor** (To in REGISTER), **binding_URI** (Contact), **username**, **password**, **expiry**. Handles REGISTER, 401/407 (via **uac_auth**), re-registration. **Dependency:** **uac_auth** must be loaded before uac_registrant. No script functions; runs from DB + timer. MI: `reg_list`, `reg_reload`, `reg_enable`, `reg_disable`, `reg_force_register`. | When carrier requires registration (e.g. Phase 0 or 1) | Optional (only if carrier requires registration) |
| **uac_auth** | **Required by uac_registrant** for 401/407 authentication challenges from the carrier. Load before uac_registrant. | With uac_registrant | When carrier requires auth |

All other modules (dispatcher, domain, usrloc, tm, registrar, etc.) are already in use; no new modules beyond **drouting**, optionally **alias_db**, and optionally **uac_registrant** + **uac_auth** when carriers require registration.

### 5.1 drouting (Dynamic Routing) – chosen

- **Functions:** `do_routing()`, `use_next_gw()`, **`is_from_gw()`** to select gateway by group/prefix; see §11.2 and §11.4 for 3.6 API.
- **Why drouting:** Actively maintained; excellent for LCR (weight-based or random gateway selection); prefix matching, time-based rules, failover; handles high volume and complex routing; supports scripts, pseudo-variables, logging. Can do everything carrierroute can and more.
- **Resolved:** OpenSIPS 3.6 drouting API and table layout confirmed (§11.2). DID → internal = gwlist in dr_rules pointing to gateway in dr_gateways whose address is Asterisk; prefix only for DIDs (regex deferred).

See **§6 Database tables reference** for drouting table details.

### 5.2 carrierroute – not used

- **Status:** Legacy; not maintained for several years. Use only for old, pre-2.2 installations.
- **Conclusion:** Use drouting for this project. Do not use carrierroute unless locked into a legacy OpenSIPS version.

### 5.3 Carrier identification (inbound)

- **Resolved:** Carrier IPs are stored in **dr_gateways** (address = IP, port, protocol). No separate carrier-IP table. For "is this INVITE from a carrier?" use drouting function **`is_from_gw(-1, "n")`** (type -1 = all types; flag **n** = ignore port, match source IP only). See [drouting 3.6](https://opensips.org/docs/modules/3.6.x/drouting.html#is_from_gw).
- **DID groups:** DIDs are structured in **dr_rules** (prefix match) and **gwlist** (gateway IDs or #carrier IDs). Incoming DID → longest-prefix match in dr_rules → gwlist → gateway(s). For DID → internal (Asterisk), rule can point to an "internal" gateway or routeid (script that forwards to dispatcher setid).

### 5.4 Storage and integration (drouting + dispatcher + domain)

- **In-memory:** drouting and dispatcher load routing data from DB into memory at startup for high-performance lookups. **MI reload** (Management Interface) can refresh drouting/dispatcher data at runtime without restart.
- **Dispatcher vs drouting:** drouting can replace or work alongside dispatcher. drouting is the logic engine (prefix, carrier, time-based rules); dispatcher is simple load balancing (round-robin/weight across a set). **In this project we use both:** **dispatcher** for **Asterisk backends** only (simple "pick an Asterisk from this set"); **drouting** for **peering** (carrier selection, DID groups, prefix rules). They work alongside; we do not replace dispatcher with drouting for Asterisk.
- **Domain:** Domain module is for **multi-tenant / domain-based routing** (e.g. company-a.com vs company-b.com), not direct gateway load balancing. It can decide **which dispatcher set** a call uses (we use domain → setid for Asterisk). No gateway probing. Use with drouting for per-tenant or domain-aware routing where needed.
- **Failover/probing:** Dispatcher performs OPTIONS probing on destinations; drouting has its own gateway state/probing. Use as needed for carrier health.

### 5.5 Dispatcher vs Domain (gateway management)

OpenSIPS can use both the **domain** and **dispatcher** modules in relation to gateways; they serve different architectural purposes.

**1. Dispatcher module**

- **Primary use:** Managing groups of gateways (destinations) for load balancing and failover.
- **Gateway sets:** Group gateways into "destination sets" (e.g. all PSTN gateways in Set 1).
- **Health monitoring:** Can actively ping gateways with SIP OPTIONS and remove down gateways from the routing list.
- **Algorithms:** Distributes traffic by round-robin, hashing (Call-ID, URI), or weight-based distribution.

**2. Domain module**

- **Primary use:** Multi-tenant or domain-based routing, not direct gateway load balancing.
- **Multi-domain support:** Handle subscribers and logic for multiple SIP domains (e.g. company-a.com vs company-b.com).
- **Gateway association:** Can be used to decide **which** set of gateways (managed by Dispatcher or drouting) a call uses; it does not probe or manage gateways itself.

**Comparison**

| Feature              | Dispatcher module   | Domain module              |
|----------------------|---------------------|----------------------------|
| Primary use          | Load balancing & failover | Multi-tenancy & subscriber domains |
| Gateway probing      | Supported (SIP pinging)   | Not supported              |
| Routing logic        | Probabilistic / hash-based | Domain / identity-based    |
| Storage              | DB or flat file (dispatcher list) | DB (domain table)          |

**Recommendation:** For standard PSTN or trunking gateway management, use the **Dispatcher** module (we use it for Asterisk backends). For prefix/cost-based routing (LCR) to carriers, use the **Dynamic Routing (drouting)** module alongside Dispatcher. Use **Domain** when you need per-tenant or domain-based selection of which gateway set applies.

### 5.6 Configuration reference: Dispatcher and drouting (data + script)

To use either module you need **two components:** a destination list (or DB) and the routing logic in `opensips.cfg`.

#### Dispatcher: gateway list + routing logic

**1. Gateway list (dispatcher.list or DB)**

Defines gateway sets. Each line (or row) is a gateway: Set ID, SIP URI, flags, priority, optional attrs.

```text
# setid  destination           flags  priority  attrs
1        sip:1.2.3.4:5060      0      1         "gw1"
1        sip:1.2.3.5:5060      0      1         "gw2"
2        sip:10.0.0.10:5060    0      1         "backup-gw"
```

- **Set ID 1:** Primary load-balanced group; Set ID 2 could be backup or another group.
- **Flags:** 0 = active; 2 = enable probing (OPTIONS).
- **Priority:** Lower number = higher priority when using priority-based algorithms.

**2. opensips.cfg (Dispatcher)**

```opensips
# ---- Dispatcher params ----
loadmodule "dispatcher.so"
modparam("dispatcher", "list_file", "/etc/opensips/dispatcher.list")
modparam("dispatcher", "ds_ping_method", "OPTIONS")
modparam("dispatcher", "ds_ping_interval", 30)      # Ping every 30s
modparam("dispatcher", "ds_probing_mode", 1)        # 1 = ping even if active

route {
    if (is_method("INVITE")) {
        # Select from Set ID 1 using Round-Robin (alg 4)
        if (!ds_select_dst("1", "4")) {
            send_reply(500, "Service full");
            exit;
        }
        t_on_failure("GW_FAILOVER");
        t_relay();
    }
}

failure_route[GW_FAILOVER] {
    if (t_check_status("(408)|([56][0-9][0-9])")) {
        if (ds_next_dst()) {
            t_on_failure("GW_FAILOVER");
            t_relay();
            exit;
        }
        send_reply(503, "All Gateways Unavailable");
    }
}
```

**Key functions**

- `ds_select_dst("set", "alg")`: Picks gateway by algorithm (e.g. "4" = Round Robin).
- `ds_next_dst()`: On failure, switches to the next available gateway in the same set.
- `ds_ping_interval` + probing: Active health checks so traffic is not sent to dead gateways.

**In pbx3sbc:** Dispatcher is used only for **Asterisk backends** (domain → setid → `ds_select_dst(setid, ...)`). Carrier/trunk gateways are managed by **drouting**.

#### drouting: database + routing logic

drouting is almost exclusively **database-driven**: gateways and rules live in DB tables.

**1. Database setup**

- **dr_gateways:** Define gateways (address, strip, priprefix, probe_mode).

| gwid | type | address           | strip | priprefix | probe_mode |
|------|------|-------------------|-------|-----------|------------|
| 1    | 1    | sip:1.1.1.1:5060  | 0     |           | 2          |
| 2    | 1    | sip:2.2.2.2:5060  | 1     | 00        | 2          |

- **dr_rules:** Routing logic by prefix (longest match), priority, gwlist.

| ruleid | groupid | prefix | priority | gwlist |
|--------|---------|--------|----------|--------|
| 1      | 0       | 1      | 10       | 1      |
| 2      | 0       | 44     | 20       | 2,1    |

- Rule 1: Numbers starting with **1** (e.g. USA) → Gateway 1.
- Rule 2: Numbers starting with **44** (e.g. UK) → Gateway 2 first, then Gateway 1 as backup.

**2. opensips.cfg (drouting)**

```opensips
loadmodule "drouting.so"
modparam("drouting", "db_url", "mysql://opensips:opensipsrw@localhost/opensips")

route {
    if (is_method("INVITE")) {
        # Select gateway by dialed number (R-URI); "0" = groupid in dr_rules
        if (!do_routing("0")) {
            send_reply(404, "No Route Found");
            exit;
        }
        t_on_failure("DR_FAILOVER");
        t_relay();
    }
}

failure_route[DR_FAILOVER] {
    if (t_check_status("[456][0-9][0-9]")) {
        if (use_next_gw()) {
            t_on_failure("DR_FAILOVER");
            t_relay();
            exit;
        }
    }
}
```

**Key functions**

- `do_routing("groupid")`: Picks gateway from `dr_rules` by longest prefix match on R-URI (e.g. `$rU`).
- `use_next_gw()`: On failure, tries the next gateway in the rule’s `gwlist`.

**Why use drouting over Dispatcher for carriers?**

- **Prefix matching:** Chooses gateways by longest prefix (e.g. +4420 vs +44) without separate script logic.
- **Manipulation:** Can strip digits or add `priprefix` per gateway before sending.
- **Scalability:** Built for large rule sets (millions of rules) and LCR.

**In pbx3sbc:** drouting will be used for **peering** (outbound carrier selection by prefix; inbound carrier identification via `dr_gateways` address; DID groups via `dr_rules`). Dispatcher remains for Asterisk backends only.

### 5.7 Comparison and recommendation: Domain+Dispatcher vs drouting for peering

Given our peering requirements, should we use the **simpler domain + dispatcher** mechanism or the **sophisticated drouting** module?

**What we need for peering**

| Requirement | What we need |
|-------------|--------------|
| **Inbound carrier identification** | Decide "is this INVITE from a carrier?" by matching `$si` (source IP) to a known list. |
| **Inbound DID → internal** | Map DID (or DID **group** by prefix, e.g. 19249181XX) to backend Asterisk. |
| **Outbound carrier selection** | From Asterisk, PSTN RURI → pick carrier gateway by **prefix** (e.g. 1→GW1, 44→GW2), with optional strip/priprefix and failover. |

**Option A: Domain + Dispatcher only (simpler)**

- **Pros:** Already in use for Asterisk; one destination list per "set"; `ds_select_dst(setid, alg)`; probing built in. Fewer moving parts.
- **Cons for peering:**
  - **No prefix matching.** Dispatcher picks from a set by algorithm (round-robin, hash); it does not choose set by dialed number. To do "1→GW1, 44→GW2" we would need **one dispatcher set per prefix group** and **custom script** that tests `$rU` (e.g. `if ($rU =~ "^1") { ds_select_dst("set_usa", "4"); } else if ($rU =~ "^44") { ... }`). No longest-prefix match, no strip/priprefix in the module.
  - **No carrier "source" list.** Dispatcher lists **destinations** we send to, not **sources** we accept from. So "is $si a carrier?" would need a **separate** structure (DB table, file, or ACL) and script logic.
  - **No DID groups.** Domain + dispatcher do not map DID prefix → internal. We could use **alias_db** for one-off DIDs only; for DID **groups** (prefix → same Asterisk) we would need a **custom table + script** (prefix match, then `ds_select_dst(asterisk_setid, ...)`).

So with domain+dispatcher we would **reimplement** prefix matching, carrier ACL, and DID-group logic in script and extra data—and still lack longest-prefix and per-gateway strip/priprefix.

**Option B: drouting (sophisticated)**

- **Pros for peering:**
  - **Prefix matching:** `dr_rules` + `do_routing(groupid)` give **longest prefix match** on `$rU` and gateway (or carrier) selection in one call. No hand-written prefix logic.
  - **Carrier identification:** `dr_gateways` holds gateway **address** (IP:port). Use **`is_from_gw(-1, "n")`** to check if sender is a known gateway (source IP matched against dr_gateways; flag **n** = ignore port).
  - **DID groups:** Same `dr_rules` model: DID prefix → internal target (e.g. routeid or gateway pointing at Asterisk setid). One-off DIDs can stay on alias_db.
  - **Strip/priprefix, failover:** Per-gateway in `dr_gateways`; `use_next_gw()` for failover. Scales to many rules and carriers.
- **Cons:** New module, new DB tables (`dr_gateways`, `dr_rules`, etc.), more to learn and operate. Slightly more complex than "one list + ds_select_dst."

**Comparison (for peering only)**

| Aspect | Domain + Dispatcher | drouting |
|--------|---------------------|----------|
| Outbound prefix → carrier | Custom script + one set per prefix; no longest-prefix, no strip/priprefix. | Native: `dr_rules` longest-prefix, strip/priprefix, `do_routing()`. |
| Inbound "from carrier?" | No native source list; need separate ACL + script. | **`is_from_gw(-1, "n")`** (drouting checks source IP against dr_gateways). |
| Inbound DID groups (prefix) | Custom table + script or alias only (one-off). | `dr_rules`: DID prefix → internal gw/routeid. |
| Config complexity | Simpler: list + `ds_select_dst`. | More: DB tables, `do_routing`, `use_next_gw`. |
| Scaling (many prefixes/carriers) | Script and sets grow; maintenance burden. | Designed for large rule sets. |

**Recommendation: use drouting for peering**

- Our requirements **are** prefix-based (outbound by dialed number, inbound by DID group) and we need a **carrier source list**. drouting provides all three (prefix rules, carrier gateways, DID→internal) in one place with longest-prefix and strip/priprefix.
- Domain + dispatcher would only simplify the **first** step (pick a gateway from a set); we would still have to build carrier ACL, prefix logic, and DID-group mapping ourselves. That offsets the "simpler" benefit and leaves us without longest-prefix and gateway manipulation.
- **Keep domain + dispatcher for what they are good at:** domain → setid → Asterisk backends. Use **drouting only for the carrier/trunk layer**: inbound carrier ID, inbound DID groups, outbound prefix→carrier.

**Summary:** Use the **sophisticated drouting** for peering. Use the **simpler domain/dispatcher** only for Asterisk backend selection (already in place). Do not try to implement peering with domain+dispatcher alone; the missing prefix and carrier-source features would force custom logic that drouting already provides.

**Typical customer scale (does not change the conclusion)**

In our customer systems we do **not** have large fleets of Asterisk backends or carriers:

| Component | Typical scale |
|-----------|----------------|
| **Asterisk backends** | 2–10 per customer |
| **DIDs** | A couple of hundred per customer |
| **Carriers (gateways)** | Usually 1 primary + 1 backup |

This **does not** change the recommendation to use drouting for peering:

1. **Logic, not scale.** We still need (a) inbound carrier identification (**`is_from_gw(-1, "n")`**), (b) DID **groups** by prefix (so we don’t maintain hundreds of one-off rows), and (c) outbound prefix → carrier with primary/backup failover. Domain+dispatcher do not provide (a) or (b), and only partially (c) by hand. drouting provides all three with small tables: e.g. 2 rows in `dr_gateways`, a handful of `dr_rules` for outbound (e.g. default prefix → gwlist "1,2") and inbound DID groups (e.g. 5–10 prefix rules covering 200 DIDs).

2. **Small scale is still a good fit for drouting.** drouting works fine with few gateways and few rules; “scales to millions” is an upside, not a requirement. We get one place for carrier list, prefix rules, and DID→internal without custom script.

3. **Primary + backup is native.** One outbound rule with `gwlist "1,2"` and `use_next_gw()` in failure_route gives primary-then-backup. No need for a second module or complex logic.

4. **Asterisk count stays on dispatcher.** 2–10 Asterisk backends per customer are already handled by domain → setid → `ds_select_dst(setid, ...)`. We are not moving that to drouting; we are adding drouting only for the **carrier** layer (2 gateways, DID groups, carrier ACL).

So: **same conclusion.** Use drouting for peering even at typical customer scale (2–10 Asterisk, ~200 DIDs, 1 primary + 1 backup carrier). The *kind* of logic we need is unchanged; only the data size is modest, which keeps drouting simple to operate.

---

## 6. Database tables reference (drouting vs carrierroute)

OpenSIPS uses several database tables, primarily within the **Dynamic Routing (drouting)** or **CarrierRoute (carrierroute)** modules, to manage routing to and from carriers/gateways.

### 6.1 Dynamic Routing (drouting) module tables

| Table | Purpose |
|-------|---------|
| **dr_gateways** | Definitions of end SIP entities (carriers/gateways) where traffic is sent. Includes gateway SIP address (URI), type, prefix add/strip, and probing configuration. |
| **dr_carriers** | Groups multiple gateways (from `dr_gateways`) and applies sorting or load-balancing (e.g. weighted distribution). A routing rule can refer to a carrier group rather than individual gateways. |
| **dr_rules** | Routing logic. Defines rules by destination prefix (longest prefix match), time validity, and priority. Each rule references a specific gateway or carrier group when a match occurs. |
| **dr_groups** | Logically groups routing rules. Allows different rule sets (e.g. "premium" vs "standard") depending on originating user or call characteristics. |

**Use case:** Complex routing, multi-carrier, per-user/per-group rule sets. **drouting offers greater flexibility and control for large-scale, multi-carrier environments.**

### 6.2 CarrierRoute (carrierroute) module tables

| Table | Purpose |
|------|---------|
| **carrierroute** | Main table for routing, balancing, and blacklisting. Uses number prefixes to choose gateway; supports traffic distribution by probability. |
| **carrierfailureroute** | Routes to use when primary carrier routing fails. |
| **route_tree** | Hierarchical routing, balancing, and blacklisting. |

**Use case:** User-based routing or Least Cost Routing (LCR) in smaller or specific installations.

### 6.3 Other relevant tables

| Table | Purpose (in this project) |
|-------|----------------------------|
| **location** | Standard OpenSIPS usrloc table: current registration (AOR + contact URIs) of local subscribers. Essential for routing to internal users; also "user unavailable" before routing outbound to carrier. |
| **dispatcher** | Used by dispatcher module for load balancing/failover. **In pbx3sbc:** used only for **Asterisk backends**, not carriers. Simpler than drouting for that use case. |

**Choice:** Module and tables depend on routing needs and complexity. **Dynamic Routing (drouting)** is the common choice for large-scale, multi-carrier peering; **carrierroute** for user-based/LCR and smaller setups.

### 6.4 Tables needed for current peering project (schema lookup)

Lookup performed against [OpenSIPS DB schema 3.2.x](https://opensips.org/html/docs/db/db-schema-3.2.x.html). Below are the tables we expect to need for the current peering project and their status in pbx3sbc.

| Table | Module | Already in pbx3sbc? | Use in peering |
|-------|--------|---------------------|----------------|
| **dr_gateways** | drouting | No (new) | Carrier/trunk definitions: gwid, type, address, strip, pri_prefix, probe_mode, state, socket, description. Link from dr_rules/dr_carriers. |
| **dr_carriers** | drouting | No (new) | Group gateways: carrierid, gwlist (GW IDs), sort_alg, state. Referenced in dr_rules as #CR-id. |
| **dr_rules** | drouting | No (new) | Routing rules: groupid, prefix, timerec, priority, routeid, gwlist (GW IDs and/or #carrierid), sort_alg. Longest prefix match. |
| **dr_groups** | drouting | No (new) | User → group: username, domain, groupid. Chooses which rule set (e.g. outbound group id). |
| **dr_partitions** | drouting | No (new) | Optional: partition name, db_url, table names, AVP names. Only if using multiple DB partitions. |
| **carrierroute** | carrierroute | No (new) | Alternative to drouting: carrier, domain, scan_prefix, prob, strip, rewrite_host/prefix/suffix. Prefix → gateway. |
| **carrierfailureroute** | carrierroute | No (new) | Failure routing: carrier, domain, scan_prefix, host_name, reply_code, next_domain. |
| **route_tree** | carrierroute | No (new) | Carrier names (id, carrier). Used with carrierroute for hierarchy. |
| **dbaliases** | alias_db | No (new) | Optional for DID → internal: alias_username, alias_domain → username, domain. DID = alias, target = user@domain. Table name configurable via modparam `alias_db`, `table_name` (default dbaliases). Create when adding alias_db (Phase 5 or Phase 0 if module loaded earlier). |
| **location** | usrloc | Yes | Already used. Internal routing (lookup) and "user unavailable" before outbound. |
| **dispatcher** | dispatcher | Yes | Already used for Asterisk only. Do not use for carriers; keep peering on drouting or carrierroute. |

**Summary**

- **If we use drouting:** Add `dr_gateways`, `dr_carriers`, `dr_rules`, `dr_groups`. Optionally `dr_partitions` for multi-DB.
- **If we use carrierroute:** Add `carrierroute`, `carrierfailureroute`, `route_tree`.
- **If we map DIDs via alias:** Add `dbaliases` (alias_db module) or implement DID → internal via dr_rules (e.g. rule pointing to internal gateway/setid).
- **Existing:** `location` and `dispatcher` stay as-is; no new tables for them.

Schema source: [https://opensips.org/html/docs/db/db-schema-3.2.x.html](https://opensips.org/html/docs/db/db-schema-3.2.x.html) (Chapters 2 alias db, 10 carrierroute, 16 dispatcher, 19 Dynamic Routing, 41 User location).

---

## 7. Inbound DID → Internal Destination

- **RURI:** DID (e.g. E.164 or carrier-specific number).
- **Target:** Backend Asterisk (setid) for the DID or DID group. Optionally internal extension (alias → user@domain then lookup).

**Primary: DID groups (prefix)**  
- Customers typically have **sequential DID blocks**, e.g. 19249181XX → 100 numbers (19249180700–19249180799), all going to the **same** backend Asterisk.  
- We want to route by **prefix** or **regex**, not one row per DID.  
- Example: prefix `19249181` or pattern `19249181[0-9]{2}` → setid 10 (that tenant's Asterisk).  
- Data model: DID group = prefix (and/or regex if supported) + setid (or internal "gateway" pointing to Asterisk). Longest-prefix or first regex match wins.

**Secondary: alias for one-off DIDs**  
- Alias table (e.g. dbaliases) can still map individual DIDs → user@domain or URI when a DID is not part of a group.  
- Flow: try DID group (prefix) first; if no match, try alias; optionally then lookup(location).

**Implications**  
- **DID groups:** Use **prefix only** (dr_rules prefix + gwlist → internal gateway). Prefix will likely suffice; regex deferred. dr_rules prefix + "internal" gateway (Asterisk in dr_gateways) is sufficient; no dedicated did_groups table for regex.

---

## 8. Outbound: Prefix → Carrier

- **Input:** Dialed number `$rU` (and possibly From/user for per-tenant or per-user carrier).
- **Process:** Longest prefix match in DB (e.g. `dr_rules` → gateway or `dr_carriers` group → `dr_gateways`) or carrierroute equivalent → pick carrier.
- **Script:** e.g. **`do_routing("0")`** (outbound groupid 0) then relay. Stripping/prefix manipulation per carrier can be script or DB-driven (dr_gateways stores prefix add/strip).

### 8.1 Carrier registration (outbound and inbound)

Many carriers (gateways) require the client (OpenSIPS/pbx3sbc) to **register** with them so that inbound calls can be delivered. OpenSIPS handles carrier registration in two directions.

**Outbound registration (OpenSIPS → carrier)**

- **Module:** **uac_registrant** – OpenSIPS registers as a client to the carrier so it can receive incoming calls on that trunk. See [uac_registrant 3.6](https://opensips.org/docs/modules/3.6.x/uac_registrant.html).
- **Dependency:** **uac_auth** must be loaded before uac_registrant (handles 401/407 challenges).
- **Configuration:** Records are loaded from a **database table** (default name **`registrant`**; modparam `table_name`). Key columns: **registrar** (URI of remote registrar/carrier), **aor** (address of record, used as To in REGISTER), **binding_URI** (Contact URI), **username**, **password** (mandatory if carrier requires auth), **expiry** (expiration; match carrier requirements). Optional: proxy, third_party_registrant, binding_params, forced_socket, state (0 = enabled, 1 = disabled). At startup records are loaded into memory; a timer drives REGISTERs and re-registration. No script functions; operation is automatic.
- **Authentication:** uac_auth is used with uac_registrant for 401/407. Set **expiry** in the table to match the carrier’s required registration interval so bindings are not dropped prematurely.
- **When needed:** Use when the carrier requires registration before accepting inbound calls. If the carrier is IP-only (no registration), uac_registrant is not required for that carrier.

**Inbound registration (carrier → OpenSIPS)**

- **Modules:** **registrar** and **usrloc** (already in use in pbx3sbc).
- **Process:** When a carrier sends a REGISTER to OpenSIPS, the request is processed with `save("location")`, storing the contact in the user location database.
- **NAT / stability:** Use `modparam("registrar", "tcp_persistent_flag", "TCP_PERSIST_DURATION")` (or equivalent) to keep TCP connections open where needed for NAT. **Path support (RFC 3327):** Use **path_mode** in the registrar module for proxy scenarios if carriers send Path headers.
- **Note:** Many carriers do not register to OpenSIPS; they send INVITEs from a fixed IP. Inbound-from-carrier is then identified by **`is_from_gw(-1, "n")`** (source IP in dr_gateways). Inbound registration is only needed when the carrier is configured to REGISTER to OpenSIPS.

**Mid-registrar (optional)**

- **Module:** **mid_registrar** – For high-volume or scaling, acts as a proxy between UAs and a main registrar (throttling, parallel forking). Not required for typical deployments (2–10 Asterisk, 1–2 carriers).

**Summary for peering**

- **Outbound to carrier:** If the carrier requires registration, add **uac_auth** (first) and **uac_registrant**, and the **registrant** table (or custom name). Configure one or more rows per carrier (registrar, aor, binding_URI, username, password, expiry). Ensure registration is active (MI `reg_list` to check state) before routing outbound INVITEs to that carrier (drouting picks the gateway; uac_registrant keeps the binding alive for inbound).
- **Inbound from carrier:** Either (a) carrier registers to OpenSIPS (registrar/usrloc, already in place) or (b) carrier sends from fixed IP (identify with `is_from_gw(-1, "n")`). No change to inbound logic beyond what is already planned.

---

## 9. Security and Robustness

- **Inbound:** Only accept from configured carrier IPs; optional IP auth / ACL so unknown IPs don't hit DID logic. Consider rate limiting / Pike per carrier.
- **Outbound:** Only for authenticated/internal sources (domain-check or auth); avoid open relay.
- **Fail2ban / logging:** Optional: log carrier INVITEs and outbound attempts; reuse or extend existing door-knock/failed-reg patterns for new failure cases.

---

## 10. Open Points (to resolve before implementation)

**Resolved (see §1 Design decisions):**
- **Outbound origin:** Always from Asterisk; PSTN = `$rU` length > 7 digits, internal = ≤ 6 digits.
- **DID → internal:** Primary = DID groups by **prefix** → Asterisk setid; alias for one-off DIDs. Prefix only (regex deferred).
- **Ownership:** Schema and scripts in **pbx3sbc**; **pbx3sbc-admin** only maintains table data (CRUD).

**Resolved:** Module choice = **drouting**; **Carrier IP storage** = **dr_gateways** (carrier IPs, ports, protocols in dr_gateways; use **`is_from_gw(-1, "n")`** for "from carrier?"). **DID group storage** = dr_rules (prefix) + gwlist (gateway/carrier IDs); DIDs map to gateway groups; for DID → Asterisk, rule gwlist points to internal gateway (Asterisk address in dr_gateways) or use routeid for script-only ops.

**Verify during implementation (not blocking):**
1. **Integration with existing dispatcher/domain:** Keep Asterisk routing (domain → setid → dispatcher) unchanged; peering as additional branches only; use MI `dr_reload` for runtime updates without restart. Confirm "from Asterisk" check (e.g. GET_DOMAIN_FROM_SOURCE_IP or dispatcher source check) before calling `do_routing("0")`.

## 11. Uncertainties and research needed

To fill out the plan and move to implementation, the following need to be resolved.

### 11.1 Decisions (need your input)

| # | Area | Status | Notes |
|---|------|--------|-------|
| 1 | **Outbound origin** | **Resolved** | Always from backend PBX (Asterisk). PSTN = `$rU` length > 7 digits; internal = ≤ 6 digits. |
| 2 | **Module choice** | **Resolved** | **drouting** (recommended for OpenSIPS 2.2+; actively maintained, LCR/failover; do not use carrierroute for new projects). |
| 3 | **DID → internal** | **Resolved** | Primary = **DID groups** by **prefix** → same backend Asterisk (setid). Alias for one-off DIDs. Prefix only (regex deferred). Example: 19249181 → block → setid 10. |
| 4 | **Carrier IP storage** | **Resolved** | **dr_gateways** – carrier IPs, ports, protocols stored here; use **`is_from_gw(-1, "n")`** for "from carrier?". No separate table. |
| 5 | **Ownership** | **Resolved** | Schema and scripts in **pbx3sbc**; **pbx3sbc-admin** only maintains data in tables (CRUD). |

### 11.2 Research (documentation / code)

| # | Topic | What we need | Source / action |
|---|--------|--------------|------------------|
| 1 | **OpenSIPS 3.6 drouting** | **Resolved** – Module: drouting. Tables: dr_gateways (drd_table), dr_rules (drr_table), dr_groups (drg_table), dr_carriers (drc_table). Functions: `do_routing()`, `use_next_gw()`, **`is_from_gw()`**, `route_to_gw()`, `route_to_carrier()`, `dr_disable()`, `dr_match()`. MI: `dr_reload`, `dr_gw_status`, etc. Dependencies: db, tm. | [OpenSIPS 3.6 drouting](https://opensips.org/docs/modules/3.6.x/drouting.html). |
| 2 | ~~carrierroute~~ | **Not used** – drouting chosen; skip carrierroute research. | N/A |
| 3 | **"From carrier" using dr_gateways** | **Resolved** – Use **`is_from_gw(-1, "n")`**: checks if sender (source IP + port) is a gateway; type -1 = all types; flag **n** = ignore port (match source IP only). No SQL/AVP needed. | [drouting 3.6 – is_from_gw](https://opensips.org/docs/modules/3.6.x/drouting.html). |
| 4 | **Inbound DID via drouting** | **Resolved** – **gwlist** can point to any gateway in dr_gateways; add Asterisk as a gateway (address = sip:asterisk-ip:5060) and use that gateway id in inbound dr_rules. **routeid** in dr_rules runs a script route when rule matches but must NOT do signaling (t_relay, etc.); use routeid only for custom ops/AVPs. For DID→Asterisk use gwlist → internal gateway. | [drouting 3.6 – rules, gateways](https://opensips.org/docs/modules/3.6.x/drouting.html). |
| 5 | **alias_db in OpenSIPS 3.6** | **Resolved** – Module exists. Function **`alias_db_lookup(table_name, [flags])`**: takes R-URI, looks up alias, replaces R-URI with user SIP URI if found; returns TRUE if alias found. Flags: **d** = username-only lookup (use for DID), **r** = reverse. Table: username, domain, alias_username, alias_domain (or configurable). | [OpenSIPS 3.6 alias_db](https://opensips.org/docs/modules/3.6.x/alias_db.html). |
| 6 | **Exact route block order** | **Resolved** – See **§4.1 Route block order (insertion points)**. From carrier?: after maxfwd + OPTIONS, before REGISTER; INVITE + `is_from_gw(-1, "n")` → route(FROM_CARRIER). To PSTN?: inside "from Asterisk" block, before endpoint path; INVITE + $rU length > 7 → do_routing, t_relay. Risks (REGISTER/OPTIONS, endpoint-as-carrier, internal→PSTN) addressed by that order. | §4.1. |
| 7 | **Multi-tenant and dr_groups** | **Resolved** – System **will be multi-tenant**: multiple backend Asterisk instances, each of which may itself be multi-tenant (multiple number ranges). Use **dr_groups** (username, domain, groupid) to scope peering by tenant/domain; align with existing domain/setid. Design for **per-tenant** carrier lists, DID groups, and outbound groups from Phase 1/4 so each tenant gets the correct carriers and DIDs. | Drouting docs (dr_groups); align with domain/setid in pbx3sbc. |
| 8 | **Security / Fail2ban** | **Deferred** – Nice-to-have; must not block main switching logic. Phase 6 or later: optional door_knock extension, carrier ACL filter, rate limit per carrier IP, peering-specific logging. | Do not block Phases 0–5. |

### 11.3 Summary

- **Decisions:** All **resolved** – outbound origin, module (drouting), DID→internal (DID groups + alias), carrier IP storage (dr_gateways), ownership.
- **Research:** OpenSIPS 3.6 drouting and alias_db **resolved** (see §11.2): use **`is_from_gw(-1, "n")`** for carrier check; gwlist → internal gateway (Asterisk in dr_gateways) for DID→Asterisk; **`alias_db_lookup(table, "d")`** for one-off DIDs; **route block order** in §4.1; **multi-tenant** resolved (dr_groups, per-tenant carriers/DIDs/outbound). **Security/Fail2ban** deferred (Phase 6+, nice-to-have). **DID:** prefix only (regex deferred). In-memory load + MI dr_reload for runtime updates.

### 11.4 OpenSIPS 3.6 implementation notes (from manuals)

From [drouting 3.6](https://opensips.org/docs/modules/3.6.x/drouting.html) and [alias_db 3.6](https://opensips.org/docs/modules/3.6.x/alias_db.html):

| Need | Solution |
|------|----------|
| **"Is this INVITE from a carrier?"** | **`is_from_gw(-1, "n")`** – checks if sender (source IP + port) is a gateway; type -1 = all types; flag **n** = ignore port (match source IP only). No SQL/AVP. |
| **Inbound DID → Asterisk** | Add Asterisk as a **gateway** in dr_gateways (address = sip:asterisk-ip:5060). Inbound dr_rules (groupid **1**): prefix → **gwlist** = that gateway id. **`do_routing("1")`** sets R-URI destination to that gateway. **routeid** in dr_rules runs a script route when rule matches but must NOT do signaling (t_relay, etc.); use only for custom ops/AVPs. |
| **One-off DID → internal** | **`alias_db_lookup("dbaliases", "d")`** – looks up R-URI in alias table; replaces R-URI with user SIP URI if alias found; flag **d** = username-only lookup (DID in R-URI user). Returns TRUE if alias found. Table: username, domain, alias_username, alias_domain (or modparam column names). |
| **do_routing** | `do_routing([groupID], [flags], ...)` – groupID from dr_groups or passed; flags **F** = rule fallback, **L** = strict length match, **C** = check only (no R-URI change). |
| **Reload** | MI **`dr_reload`** – reload routing data from DB; optional partition name; optional inherit_state. |
| **uac_registrant (carrier registration)** | **Dependency:** load **uac_auth** before uac_registrant (401/407). **Table:** default `registrant`; columns: registrar (carrier URI), aor, binding_URI, username, password, expiry. No script functions; timer-driven. **MI:** `reg_list` (status), `reg_reload`, `reg_enable`, `reg_disable`, `reg_force_register`. **Params:** `timer_interval`, `failure_retry_interval`, `db_url`, `table_name`. | [uac_registrant 3.6](https://opensips.org/docs/modules/3.6.x/uac_registrant.html) |

---

## 12. Build and test plan (phased)

Work is split into **small, manageable phases**. Each phase has a narrow scope, clear deliverables, and test criteria so we can verify behavior before moving on. This limits blast damage: if something breaks, we know which phase caused it and can roll back that change only.

**Principles**

- **One concern per phase:** Each phase changes one area (e.g. "add drouting module only" or "outbound PSTN only") so failures are easy to isolate.
- **No big bang:** Avoid a single large change that touches route logic, DB, and config at once.
- **Test after each phase:** Existing behavior (REGISTER, OPTIONS/NOTIFY, Asterisk↔endpoint, DOMAIN_CHECK) must remain correct after every phase.
- **Safe rollback:** Each phase is reversible (revert config, optionally DB) without leaving the system in a half-built state.

**Phase overview**

| Phase | Name | Scope | Route logic change? | Blast risk |
|-------|------|--------|----------------------|------------|
| 0 | Foundation | **Installer:** create peering tables via `init-database.sh` + `peering-create.sql`. Then add drouting module; no peering branches in route. | No | Low |
| 1 | Outbound single gateway | One carrier, one rule; "from Asterisk + PSTN" → do_routing → relay | Yes (one branch) | Low |
| 2 | Outbound failover | Second gateway in gwlist; use_next_gw() in failure_route | No (failure_route already there) | Low |
| 3 | Inbound carrier ID | Detect "from carrier" with **is_from_gw(-1, "n")**; take safe action (relay or 503) | Yes (early branch) | Medium |
| 4 | Inbound DID groups | DID prefix → Asterisk via dr_rules; relay from carrier to backend | Yes (use do_routing in carrier path) | Medium |
| 5 | Inbound one-off DIDs | alias_db for DIDs not in prefix group | Yes (**alias_db_lookup** in carrier path) | Low |
| 6 | Polish | Security (fail2ban/logging) **deferred** – nice-to-have, not blocking; dr_groups for multi-tenant (already in scope from Phase 1/4), docs | Optional | Low |

**Carrier registration (uac_registrant):** If the carrier requires OpenSIPS to register to it (so the carrier can deliver inbound calls), add **uac_auth** (first) and **uac_registrant** and the **registrant** table (default table name). This can be done as part of **Phase 0** (foundation) or alongside **Phase 1** when adding the first outbound carrier. Ensure registration is active (MI `reg_list`) before relying on that carrier for inbound.

---

### Phase 0: Foundation (no route logic change)

**Objective:** Add peering DB schema via the installer first (so admin panel and testing can create objects in parallel), then add drouting module and config—without changing any routing behavior.

**Scope (order of work)**

1. **Installer / table creation (first).** Modify the installer so the new peering tables are created when the database is initialized. This is the **first** deliverable so that:
   - The admin panel agent can work in parallel and use the same schema.
   - Test data can be created (e.g. via admin panel or SQL) before or during config build.
   - **Concrete change:** Extend `install.sh`’s database initialization path so the new tables are created. Specifically:
     - Add a SQL script that defines and creates: `dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `registrant`, `dbaliases` (schema aligned with OpenSIPS 3.6; include `version` table entries for module compatibility).
     - Run this script from `scripts/init-database.sh` (which is invoked by `install.sh` during `initialize_database`). Use idempotent checks (e.g. create only if `dr_gateways` does not exist) so re-runs do not fail.
   - **Deliverable:** New file `scripts/peering-create.sql`; `scripts/init-database.sh` updated to run it when the DB is initialized. No seed data required; tables may be empty.
2. **Config: drouting module (no route logic).** Add `loadmodule "drouting.so"` and `modparam("drouting", "db_url", ...)` to `opensips.cfg.template`. Do **not** call `do_routing()` or add any peering branches in `route {}`.
3. **Optional (carrier requires registration):** Load **uac_auth** (first), then **uac_registrant**; ensure **registrant** table exists (already created in step 1) and add modparam `db_url`/`table_name`. No route logic change; registration runs from timer. MI `reg_list` to verify state; `reg_reload` to reload from DB.

**Deliverables**

- Running `install.sh` (with DB init) or `scripts/init-database.sh` creates the peering tables (`dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `registrant`, `dbaliases`). Admin panel and test scripts can populate them immediately.

**Do you need a re-install?** No. **Fresh install:** `install.sh` creates the DB and runs `init-database.sh`, which creates the peering tables. **Existing install:** run `scripts/init-database.sh` manually (with `DB_NAME`, `DB_USER`, `DB_PASS` set); it is idempotent and only adds the peering tables if `dr_gateways` is missing. No need to reinstall or reinitialize (drop) the database.
- OpenSIPS starts with drouting loaded; no new route logic.
- MI command to reload drouting (if applicable) works.

**Test criteria**

- Restart OpenSIPS; no startup errors.
- Existing flows unchanged: REGISTER, INVITE to Asterisk, OPTIONS/NOTIFY, Asterisk→endpoint, DOMAIN_CHECK.
- No traffic goes to drouting (no do_routing calls yet).

**Rollback:** Remove loadmodule and modparam; optionally drop new tables. To remove tables: drop `dr_gateways`, `dr_rules`, `dr_carriers`, `dr_groups`, `registrant`, `dbaliases` and their `version` rows; revert `init-database.sh` and delete `scripts/peering-create.sql`.

---

### Phase 1: Outbound to carrier (single gateway)

**Objective:** Route outbound PSTN calls (from Asterisk, $rU length > 7) to one test carrier via drouting. All other traffic unchanged.

**Prerequisite:** Phase 0 done.

**Scope**

- Insert 1 row in `dr_gateways` (test carrier: address, e.g. sip:carrier-ip:5060).
- Insert 1 row in `dr_rules` (e.g. groupid 0, prefix "1" or "0", priority 10, gwlist "1").
- In `route {}`: at the agreed insertion point (after we know request is from Asterisk), add: if `$rU` length > 7 then `do_routing("0")`; on success, `t_on_failure("DR_FAILOVER")`, `t_relay()`. On `do_routing` failure, send 404 or continue to existing logic as designed.
- Add `failure_route[DR_FAILOVER]`: on 4xx/5xx/408, `use_next_gw()`; if success, re-arm and `t_relay()`; else send 503.

**Deliverables**

- Outbound INVITE from Asterisk with PSTN number (e.g. 10-digit) goes to test carrier.
- Outbound INVITE from Asterisk with short number (≤6 digits) still goes to endpoint path (unchanged).
- All other methods and origins unchanged.

**Test criteria**

- INVITE from Asterisk, RURI user = 10-digit number → request sent to carrier IP.
- INVITE from Asterisk, RURI user = 5-digit (internal) → existing GET_DOMAIN_FROM_SOURCE_IP / lookup / RELAY path.
- INVITE from non-Asterisk → unchanged (e.g. DOMAIN_CHECK, etc.).
- REGISTER, OPTIONS, etc. unchanged.

**Rollback:** Remove the "to PSTN" branch and failure_route; leave DB rows.

---

### Phase 2: Outbound failover (second gateway)

**Objective:** Add a second carrier to the same outbound rule so that if the first fails, the next is tried.

**Prerequisite:** Phase 1 done.

**Scope**

- Insert second row in `dr_gateways` (backup carrier).
- Update `dr_rules` gwlist to "1,2" (or equivalent). failure_route from Phase 1 already handles `use_next_gw()`.

**Deliverables**

- When primary gateway returns 4xx/5xx/408 or times out, request is sent to backup.

**Test criteria**

- Simulate primary failure (e.g. wrong port or 503): call should be retried to backup gateway.
- Normal case: primary still used when it responds 2xx.

**Rollback:** Set gwlist back to "1"; optionally disable or remove second gateway row.

---

### Phase 3: Inbound – carrier identification only

**Objective:** Detect INVITEs from a known carrier using drouting **`is_from_gw(-1, "n")`** (source IP matched against dr_gateways; flag **n** = ignore port) and send them down a dedicated path. For this phase, that path does **not** resolve DIDs; it only takes a safe action (e.g. relay to default Asterisk set or reply 503 "inbound not configured").

**Prerequisite:** Phase 0 (and ideally Phase 1) done. No extra research: use **`is_from_gw(-1, "n")`** per [drouting 3.6](https://opensips.org/docs/modules/3.6.x/drouting.html).

**Scope**

- Early in `route {}` (before DOMAIN_CHECK / TO_ASTERISK): if method INVITE and **`is_from_gw(-1, "n")`** returns true (source is a known gateway/carrier), branch to "from carrier" path.
- "From carrier" path: relay to existing Asterisk set (e.g. fixed setid) **or** send 503 with reason "Inbound peering not configured". No DID-based routing yet.

**Deliverables**

- INVITE from carrier IP → new path (fixed relay or 503).
- INVITE from any other IP → existing flow unchanged (DOMAIN_CHECK, etc.).

**Test criteria**

- INVITE from carrier IP (is_from_gw matches) → request goes to Asterisk (or 503).
- INVITE from non-carrier IP → unchanged; no regression on REGISTER, OPTIONS, or other INVITEs.

**Rollback:** Remove the "from carrier?" branch; all INVITEs again follow existing logic.

---

### Phase 4: Inbound DID groups → Asterisk

**Objective:** Resolve DID (RURI user) by prefix using dr_rules and route the call to the correct Asterisk backend (setid or equivalent).

**Prerequisite:** Phase 3 done. Inbound DID→internal is resolved (gwlist → gateway in dr_gateways whose address is Asterisk; see §11.2 item 4).

**Scope**

- Populate `dr_rules` for **inbound groupid 1**: prefix(es) → **gwlist** pointing to gateway(s) in dr_gateways whose **address** is the Asterisk backend (sip:asterisk-ip:5060). Optionally use **routeid** for script-only ops (no signaling in that route).
- In "from carrier" path: call **`do_routing("1")`** (inbound groupid 1) with RURI = DID; relay to the returned destination (gateway address from dr_gateways).

**Deliverables**

- INVITE from carrier with DID matching a prefix rule → request reaches the intended Asterisk backend.
- INVITE from carrier with DID not matching any rule → 404 or fall-through to Phase 5 (alias).

**Test criteria**

- Carrier sends INVITE with DID in configured prefix range → Asterisk receives it.
- DID outside prefix range → 404 or alias path (Phase 5).

**Rollback:** Remove DID resolution from "from carrier" path (back to fixed relay or 503); optionally clear inbound dr_rules.

---

### Phase 5: Inbound one-off DIDs (alias_db)

**Objective:** Handle DIDs that are not in any prefix group by resolving them via alias_db (DID → user@domain) and then existing lookup/relay logic.

**Prerequisite:** Phase 4 done. Requires: alias_db module and schema (if not already present). Use **`alias_db_lookup(table_name, [flags])`** per [alias_db 3.6](https://opensips.org/docs/modules/3.6.x/alias_db.html); flag **d** = username-only lookup (DID in R-URI user).

**Scope**

- In "from carrier" path: if `do_routing()` for inbound group returns no match, call **`alias_db_lookup("dbaliases", "d")`** (or configured table); if found, R-URI is replaced with user SIP URI; then continue (e.g. lookup location or relay to Asterisk as for local user).

**Deliverables**

- One-off DIDs (not in dr_rules prefix) resolve to the correct internal destination via alias.

**Test criteria**

- DID in prefix group → still works (Phase 4).
- DID only in alias → reaches correct target.
- DID in neither → 404 or appropriate reply.

**Rollback:** Remove alias_db_lookup from carrier path; DIDs only in alias will fail until reverted.

---

### Phase 6: Polish and security

**Objective:** Harden and document: optional fail2ban or logging for unknown IPs hitting carrier path, dr_groups for multi-tenant if needed, and updates to QUICK-START/README.

**Scope**

- Logging: consider logging "INVITE from unknown IP to DID" for security monitoring.
- Fail2ban: extend or add filter for repeated requests from non-carrier IPs to carrier path (if detectable), or for carrier ACL violations; optional.
- dr_groups: if multiple tenants/domains need separate carrier lists or DID groups, configure dr_groups and groupid usage.
- Docs: add "Peering" subsection to QUICK-START (or README); link to this plan.

**Deliverables**

- Documented, optionally secured, peering flow; docs updated.

**Test criteria**

- No regression on Phases 0–5; security and multi-tenant behavior as designed.

---

### Build plan summary

- **Order:** 0 → 1 → 2 → 3 → 4 → 5 → 6. Phases 1–2 are outbound-only; 3–5 are inbound; 6 is cross-cutting.
- **Research before implementation:** Complete §11.2 items that affect each phase (e.g. "from carrier" match and route order before Phase 3; inbound DID→internal before Phase 4; alias_db before Phase 5).
- **Per-phase workflow:** Implement → test (existing + new) → commit; only then start next phase. If a phase fails, fix or roll back that phase before proceeding.

### Config build checklist (single reference for building the new config)

Use this when building the new config from this plan:

| Item | Value / location |
|------|------------------|
| **Group IDs** | Outbound = **0** (`do_routing("0")`), Inbound DID = **1** (`do_routing("1")`) — see §4.3 |
| **Failure route name** | `DR_FAILOVER` (use_next_gw, t_on_failure, t_relay) |
| **Carrier check** | `is_from_gw(-1, "n")` (INVITE only); route **FROM_CARRIER** |
| **Insert "From carrier?"** | After OPTIONS/NOTIFY block (after ~598), before REGISTER block (~600) |
| **Insert "To PSTN?"** | After REGISTER block (~681), before `route(DOMAIN_CHECK);` (~683). Use **route(CHECK_IS_FROM_ASTERISK)** then if `$var(is_from_asterisk)==1` and INVITE and `$rU` length > 7: `do_routing("0")`, t_on_failure, t_relay, exit. |
| **PSTN vs internal** | `$rU` length > 7 → PSTN; ≤ 6 → internal (Asterisk→endpoint) |
| **Carrier vs Asterisk IPs** | **dr_gateways** = carrier IPs (for `is_from_gw`) + Asterisk *destinations* for DID rules only. Do **not** put Asterisk backend IPs in dr_gateways for carrier *source* identification; Asterisk source IPs stay in **dispatcher** only. |
| **alias_db table** | Default **dbaliases**; override with modparam `alias_db`, `table_name` if needed. Create in Phase 5 (or Phase 0 if loading alias_db earlier). |
| **drouting tables** | dr_gateways, dr_rules, dr_groups, dr_carriers (schema per OpenSIPS 3.6 / db-schema); use 3.6 schema for new installs |

---

## 13. Suggested next steps (planning and first phase)

1. **Research** §11.2 remaining items only if needed (route block order and multi-tenant dr_groups **resolved**; security **deferred**). Drouting/alias_db items **resolved** (is_from_gw, gwlist→internal gw, alias_db_lookup).
2. Document **route block order**: exact insertion points in `opensips.cfg.template` for "from carrier?" and "to PSTN?".
3. **Implement Phase 0** (foundation): drouting module + DB tables; verify startup and no behavior change.
4. Add a short **"Peering" section** to `workingdocs/QUICK-START.md` (or README) once Phase 0–1 are stable, and link to this plan.

---

## 14. References

### 14.1 OpenSIPS 3.6 module documentation (primary)

- **Dynamic Routing (drouting):** [https://opensips.org/docs/modules/3.6.x/drouting.html](https://opensips.org/docs/modules/3.6.x/drouting.html) — gateways, carriers, rules, groups; `do_routing()`, `use_next_gw()`, **`is_from_gw()`** (carrier check), `dr_disable()`, `dr_match()`; MI `dr_reload`, `dr_gw_status`, etc.
- **ALIAS_DB (alias_db):** [https://opensips.org/docs/modules/3.6.x/alias_db.html](https://opensips.org/docs/modules/3.6.x/alias_db.html) — alias lookup from DB; **`alias_db_lookup(table_name, [flags])`** (replaces R-URI when alias found); `alias_db_find()` for pvar input/output; flags `d` (username-only), `r` (reverse).
- **UAC Registrant (uac_registrant):** [https://opensips.org/docs/modules/3.6.x/uac_registrant.html](https://opensips.org/docs/modules/3.6.x/uac_registrant.html) — outbound registration (OpenSIPS → carrier). **Dependency:** **uac_auth** (must be loaded first). **Table:** default `registrant`; columns registrar, aor, binding_URI, username, password, expiry (and optional proxy, third_party_registrant, binding_params, forced_socket, state). No script functions; runs from DB + timer. Handles REGISTER, 401/407 via uac_auth, re-registration. **MI:** `reg_list`, `reg_reload`, `reg_enable`, `reg_disable`, `reg_force_register`. **Params:** `timer_interval`, `failure_retry_interval`, `db_url`, `table_name`, column names.

### 14.2 Other references

- **Module choice (drouting vs carrierroute):** For OpenSIPS 2.2+, drouting is recommended over carrierroute. drouting is actively maintained, supports LCR/failover, handles high volume and complex routing; carrierroute is legacy and not maintained. Use drouting only; do not use both for the same routing.
- **Carrier IPs and DID groups (drouting):** Carrier IPs, ports, protocols in **dr_gateways**; DIDs in **dr_rules** (prefix) + **gwlist** (gateway/carrier IDs). Data loaded into memory at startup; **MI dr_reload** updates without restart. Dispatcher used for load balancing/probing; domain module for multi-tenant/URI-based routing.
- **drouting vs dispatcher/domain:** **Dispatcher** = gateway sets, load balancing, probing (we use for Asterisk). **Domain** = multi-tenant, which dispatcher set (we use domain → setid). **drouting** = carrier/PSTN with prefix/LCR (we use for peering). Use dispatcher for standard gateway sets; drouting alongside for complex prefix/cost routing.
- **OpenSIPS database tables (all modules, schema + docs):** [https://opensips.org/html/docs/db/db-schema-3.2.x.html](https://opensips.org/html/docs/db/db-schema-3.2.x.html) — use for drouting, carrierroute, location, dispatcher, alias, etc.
- Snippets provided in planning session (inbound vs outbound, do_routing group IDs, prefix routing).
- Database tables reference: drouting (dr_gateways, dr_carriers, dr_rules, dr_groups); carrierroute (carrierroute, carrierfailureroute, route_tree); location; dispatcher.
- Current config: `config/opensips.cfg.template` (dispatcher, DOMAIN_CHECK, TO_ASTERISK, GET_DOMAIN_FROM_SOURCE_IP).
- workingdocs: `QUICK-START.md`, `README.md`, `ARCHITECTURE/`.

---

## 15. Example: Data for one carrier (CarrierAlpha)

This section answers: **what tables must be populated, and what would the data look like?** for a hypothetical carrier that:

- Sends our outbound traffic to the PSTN (we send INVITEs to them).
- Sends us inbound calls (we receive INVITEs from them and route by DID to the correct Asterisk backend).
- Requires **registration** (username + password) before we can send or receive traffic; OpenSIPS registers to the carrier via **uac_registrant**.

**Assumptions for the example:** CarrierAlpha gives us: (1) their SIP endpoint for signaling, e.g. `sip.carrieralpha.com:5060` (we send outbound here; they send inbound from the same or a known IP), (2) registrar URI for registration, e.g. `sip:registrar.carrieralpha.com:5060`, (3) a trunk identity (AOR) to register as, e.g. `our-trunk@carrieralpha.com`, (4) username and password for REGISTER auth, (5) our DID block prefix(es), e.g. `19249181` → our Asterisk at `10.0.0.20:5060`. We use **groupid 0** for outbound and **groupid 1** for inbound (§4.3).

---

### 15.1 Tables to populate

| Table | Purpose for CarrierAlpha |
|-------|---------------------------|
| **dr_gateways** | Define CarrierAlpha as a gateway (outbound destination + inbound source for `is_from_gw()`). Define Asterisk backend(s) as gateways for inbound DID → internal. |
| **dr_rules** | Outbound: prefix(es) → CarrierAlpha gwid (groupid **0**). Inbound: DID prefix(es) → Asterisk gateway gwid (groupid **1**). |
| **registrant** | One row per trunk/registration: registrar URI, AOR, Contact (binding_URI), username, password, expiry so OpenSIPS can register to CarrierAlpha. |
| **dr_carriers** | Optional; only if grouping multiple gateways (e.g. LCR). Omitted in this single-carrier example. |
| **dr_groups** | Optional; only for multi-tenant (per-user/domain groupid). Omitted for single-tenant example. |
| **dbaliases** | Optional; only for one-off DIDs not covered by a DID prefix in dr_rules (Phase 5). |

---

### 15.2 Example rows

**1. dr_gateways**

- **CarrierAlpha:** One row so we can (a) send outbound INVITEs to them and (b) recognise inbound INVITEs from them (`is_from_gw(-1,"n")` matches source IP against `address`). Use carrier’s signaling IP or hostname and port.
- **Asterisk backend:** One row per Asterisk we route inbound DIDs to; `address` = that Asterisk’s SIP URI. dr_rules (groupid 1) reference this gateway by `gwid`.

Schema columns (see §6.4): `gwid`, `type`, `address`, `strip`, `pri_prefix`, `attrs`, `probe_mode`, `state`, `socket`, `description`. Typical 3.2/3.6 schema uses `id` (auto) and `gwid` (string, unique).

| gwid | type | address | strip | pri_prefix | probe_mode | state | description |
|------|------|---------|-------|------------|------------|-------|--------------|
| 1 | 1 | sip:sip.carrieralpha.com:5060 | 0 | NULL | 0 | 0 | CarrierAlpha – outbound + inbound source |
| 2 | 1 | sip:10.0.0.20:5060 | 0 | NULL | 0 | 0 | Asterisk backend for DID block 19249181 |

- **gwid "1"** = CarrierAlpha. Same row used for outbound (do_routing("0") sends to this address) and for inbound (is_from_gw checks source IP against this address; use hostname only if carrier sends from that hostname’s IP).
- **gwid "2"** = our Asterisk; inbound dr_rules (groupid 1) point DID prefix to this gwid.

**2. dr_rules**

- **Outbound (groupid 0):** Which dialed prefix(es) go to CarrierAlpha. Example: default/blank prefix or "1" (e.g. North America) → gwlist "1".
- **Inbound (groupid 1):** Which DID prefix(es) go to which Asterisk. Example: prefix "19249181" → gwlist "2".

| ruleid | groupid | prefix | priority | routeid | gwlist | sort_alg | description |
|--------|---------|--------|----------|--------|--------|----------|--------------|
| 1 | 0 | 1 | 10 | NULL | 1 | N | Outbound: numbers starting 1 → CarrierAlpha |
| 2 | 0 | (empty or 0) | 5 | NULL | 1 | N | Outbound: default → CarrierAlpha |
| 3 | 1 | 19249181 | 10 | NULL | 2 | N | Inbound: DIDs 19249181xx → Asterisk 10.0.0.20 |

- Longest prefix match: e.g. 19249181234 matches prefix "19249181" and routes to gwlist "2" (Asterisk).

**3. registrant** (uac_registrant – OpenSIPS registers to CarrierAlpha)

CarrierAlpha requires registration; we store one row per trunk/registration. uac_registrant (and uac_auth) use this to send REGISTER and handle 401/407.

| id | registrar | proxy | aor | username | password | binding_URI | expiry | state |
|----|-----------|-------|-----|----------|----------|-------------|--------|-------|
| 1 | sip:registrar.carrieralpha.com:5060 | NULL | sip:our-trunk@carrieralpha.com | carrier-given-username | carrier-given-password | sip:opensips-public-ip:5060 | 3600 | 0 |

- **registrar:** Carrier’s registrar URI (where we send REGISTER).
- **aor:** Address of record we register as (To in REGISTER); carrier typically assigns this (e.g. our-trunk@carrieralpha.com).
- **binding_URI:** Our Contact URI (our public SIP endpoint so CarrierAlpha can send inbound to us); use OpenSIPS’s public IP or hostname and port.
- **username / password:** Credentials carrier gave us for REGISTER authentication (401/407).
- **expiry:** Registration lifetime in seconds (e.g. 3600); match carrier’s policy.
- **state:** 0 = enabled, 1 = disabled.

Optional: `binding_params`, `forced_socket`, `third_party_registrant` if needed (see uac_registrant docs).

---

### 15.3 Summary: what you need from the carrier

To populate the above for a CarrierAlpha-style trunk:

| Data | Used in | Example |
|------|---------|--------|
| Signaling address (IP or hostname:port) | dr_gateways.address (gwid CarrierAlpha) | sip.carrieralpha.com:5060 |
| Registrar URI (for REGISTER) | registrant.registrar | sip:registrar.carrieralpha.com:5060 |
| AOR to register as | registrant.aor | sip:our-trunk@carrieralpha.com |
| Our public SIP URI (Contact for registration) | registrant.binding_URI | sip:opensips-public-ip:5060 |
| Username for REGISTER | registrant.username | (from carrier) |
| Password for REGISTER | registrant.password | (from carrier) |
| Registration expiry (seconds) | registrant.expiry | 3600 |
| DID block prefix(es) and which Asterisk | dr_rules (groupid 1), dr_gateways (Asterisk row) | 19249181 → Asterisk 10.0.0.20 |
| Outbound prefix(es) to send via this carrier | dr_rules (groupid 0) | e.g. "1" or default → gwid 1 |

After populating: run **MI `dr_reload`** to load dr_gateways/dr_rules; run **MI `reg_reload`** (or restart) so uac_registrant picks up the registrant row. Verify registration with **MI `reg_list`** before relying on inbound/outbound.

---

## 16. Admin panel (pbx3sbc-admin) – requirements for UI/CRUD

This section is for the **admin front-end** agent. It defines what the panels must manage so they can build CRUD UIs from this document alone. **pbx3sbc-admin** only maintains **data** in the peering tables (CRUD); schema and migration scripts live in **pbx3sbc** (§1).

### 16.1 Scope: tables and ownership

| Table | Admin panel manages? | Notes |
|-------|----------------------|--------|
| **dr_gateways** | **Yes** | Create/read/update/delete gateways (carriers + Asterisk backends). |
| **dr_rules** | **Yes** | Create/read/update/delete routing rules (outbound groupid 0, inbound groupid 1). |
| **registrant** | **Yes** | Create/read/update/delete outbound registration rows (OpenSIPS → carrier). |
| **dr_carriers** | Optional | Only if using carrier groups (LCR); gwlist in dr_rules can reference #carrierid. |
| **dr_groups** | Optional | Only for multi-tenant (per-user/domain → groupid); align with domain/setid. |
| **dbaliases** | **Yes** (if alias_db used) | One-off DID → username@domain; optional feature (Phase 5). |
| **dispatcher**, **domain**, **location** | **No** | Existing tables; not part of peering CRUD. Do not manage from peering panels. |

### 16.2 Entity specs for CRUD

Use the **OpenSIPS DB schema** for exact types/lengths: [db-schema 3.2.x – Dynamic Routing (Ch.19), Registrant (Ch.31), alias db (Ch.2)](https://opensips.org/html/docs/db/db-schema-3.2.x.html). Below: required vs optional, allowed values, and references.

---

**1. dr_gateways**

| Column | Type (schema) | Required | Editable | Notes / validation |
|--------|----------------|----------|----------|--------------------|
| id | auto | No (PK) | No | Auto-increment; display only. |
| gwid | string(64) | **Yes** | Yes | **Unique.** Referenced by dr_rules.gwlist (e.g. "1", "2"). Used in script as gateway id. |
| type | int | Yes | Yes | User-defined; e.g. 1 = carrier, 1 = Asterisk (same type ok). |
| address | string(128) | **Yes** | Yes | **SIP URI:** `sip:host:port` or `sip:host`. Host = IP or FQDN. Used for outbound relay and for `is_from_gw()` (inbound source match). |
| strip | int | Yes | Yes | Digits to strip from username (0 if none). |
| pri_prefix | string(16) | No | Yes | Prefix to add to username (e.g. "00"); NULL = none. |
| attrs | string(255) | No | Yes | Opaque attributes; script can use. |
| probe_mode | int | Yes | Yes | **0** = no probing, **1** = probe when disabled, **2** = always probe. |
| state | int | Yes | Yes | **0** = enabled, **1** = disabled, **2** = temp disabled (probing). |
| socket | string(128) | No | Yes | Local socket for sending; NULL = default. |
| description | string(128) | No | Yes | Human-readable label (e.g. "CarrierAlpha", "Asterisk backend 1"). |

**Validation:** `address` must look like `sip:...`. **Before delete:** either prevent delete if any dr_rules.gwlist references this gwid, or soft-delete (set state=1). After create/update/delete: **MI `dr_reload`** so OpenSIPS picks up changes.

---

**2. dr_rules**

| Column | Type (schema) | Required | Editable | Notes / validation |
|--------|----------------|----------|----------|--------------------|
| ruleid | auto | No (PK) | No | Auto-increment; display only. |
| groupid | string(255) | **Yes** | Yes | **This project:** use **"0"** (outbound) or **"1"** (inbound) only (§4.3). Comma-separated list in schema. |
| prefix | string(64) | **Yes** | Yes | Numeric prefix for longest-match (e.g. "1", "44", "19249181"). Empty string = default/catch-all. |
| timerec | string(255) | No | Yes | Time recurrence; NULL = always. |
| priority | int | Yes | Yes | Lower = higher priority when prefix matches overlap. |
| routeid | string(255) | No | Yes | Script route name when rule matches; NULL = use gwlist. Do not use for normal DID/carrier routing. |
| gwlist | string(255) | Yes | Yes | **Comma-separated gwids** (e.g. "1", "2" or "1,2"). Each must exist in dr_gateways.gwid. Can include #carrierid if using dr_carriers. |
| sort_alg | string(1) | Yes | Yes | **N** = preserve order, **W** = weight, **Q** = quality; default **N**. |
| sort_profile | int | No | Yes | For sort_alg Q; NULL otherwise. |
| attrs | string(255) | No | Yes | Opaque; script can use. |
| description | string(128) | No | Yes | Human-readable (e.g. "Outbound default → CarrierAlpha"). |

**Validation:** `groupid` in {"0","1"} for this project. `gwlist` tokens must be existing dr_gateways.gwid (or #carrierid). **After create/update/delete:** **MI `dr_reload`**.

---

**3. registrant** (uac_registrant)

| Column | Type (schema) | Required | Editable | Notes / validation |
|--------|----------------|----------|----------|--------------------|
| id | auto | No (PK) | No | Auto-increment; display only. |
| registrar | string(255) | **Yes** | Yes | **SIP URI** of carrier registrar (e.g. sip:registrar.carrieralpha.com:5060). |
| proxy | string(255) | No | Yes | Outbound proxy URI; NULL = none. |
| aor | string(255) | **Yes** | Yes | Address of record we register as (To in REGISTER), e.g. sip:our-trunk@carrieralpha.com. |
| third_party_registrant | string(255) | No | Yes | NULL = not used. |
| username | string(64) | Yes* | Yes | *Required if carrier uses auth (401/407). |
| password | string(64) | Yes* | Yes | *Required if carrier uses auth; plain or HA1. |
| binding_URI | string(255) | **Yes** | Yes | **Our Contact URI** (e.g. sip:opensips-public-ip:5060). |
| binding_params | string(64) | No | Yes | Contact params; NULL = none. |
| expiry | int | No | Yes | Registration lifetime (seconds); match carrier. NULL = module default. |
| forced_socket | string(64) | No | Yes | Local socket for REGISTER; NULL = default. |
| state | int | Yes | Yes | **0** = enabled, **1** = disabled. |

**Validation:** `registrar`, `aor`, `binding_URI` should be valid SIP URIs. **After create/update/delete:** **MI `reg_reload`** (and optionally show **MI `reg_list`** for status).

---

**4. dr_carriers** (optional)

| Column | Required | Notes |
|--------|----------|--------|
| carrierid | Yes | Unique; referenced in dr_rules.gwlist as #carrierid. |
| gwlist | Yes | Comma-separated dr_gateways.gwid. |
| flags, sort_alg, state, attrs, description | Per schema | See DB schema Ch.19. |

**After change:** **MI `dr_reload`**.

---

**5. dr_groups** (optional, multi-tenant)

| Column | Required | Notes |
|--------|----------|--------|
| username, domain | Yes | User/domain mapping. |
| groupid | Yes | Which rule set (e.g. 0 or 1); align with domain/setid. |

**After change:** **MI `dr_reload`**.

---

**6. dbaliases** (optional, Phase 5)

| Column | Required | Notes |
|--------|----------|--------|
| alias_username | Yes | DID or alias (username part). |
| alias_domain | Yes | Often same domain or "*". |
| username | Yes | Target user (internal). |
| domain | Yes | Target domain (internal). |

**Validation:** Unique (alias_username, alias_domain). **No MI reload** (alias_db may read on demand or cache; check alias_db docs).

### 16.3 Suggested UI structure

- **Gateways** – List/create/edit/delete **dr_gateways**. Distinguish by description or type (carrier vs Asterisk). Show gwid prominently (referenced by rules).
- **Routing rules** – List/create/edit/delete **dr_rules**. **Filter or tabs by groupid:** "Outbound (0)" and "Inbound (1)". In forms: groupid dropdown (0, 1); gwlist as multi-select or comma-separated gwids validated against dr_gateways.
- **Carrier registration** – List/create/edit/delete **registrant**. Optional: show registration status (read-only) via MI `reg_list` if backend can call MI.
- **Carriers** (optional) – Only if using dr_carriers; list/create/edit with gwlist.
- **Groups** (optional) – Only if multi-tenant; map username/domain → groupid.
- **DID aliases** (optional) – If using dbaliases; list/create/edit/delete alias → user@domain.

### 16.4 Post-save actions (backend)

After any create/update/delete on **dr_gateways**, **dr_rules**, **dr_carriers**, or **dr_groups**: call **OpenSIPS MI `dr_reload`** so routing data is refreshed without restart. After any change to **registrant**: call **MI `reg_reload`** so uac_registrant reloads registrations. The admin backend (or a small service) must perform these MI calls; the plan does not define the exact API.

### 16.5 What the admin panel does *not* do

- Does **not** create or alter **schema** (tables, indexes); that is in pbx3sbc migrations.
- Does **not** manage **dispatcher**, **domain**, or **location**; those remain in existing admin flows.
- Does **not** manage OpenSIPS config (e.g. opensips.cfg); peering logic is already wired to groupids 0 and 1 and to these tables.

With §15 (example data) and this section, an agent building the admin front-end has: scope of tables, column-level requirements, validation and allowed values, relationships (gwlist → gwid, groupid 0/1), post-save reload requirements, and a suggested UI layout. For exact SQL types and lengths, they should still open the OpenSIPS DB schema (Ch.2, 19, 31) linked in §6 and §14.

No code or config changes have been made; this document is planning only.

---

## 17. Final review: risk assessment and overall comments

This section is a final review of the plan as it stands (including Phase 0 deliverables: `peering-create.sql`, `init-database.sh` integration). It summarizes strengths, risks, and residual implementation notes.

### 17.1 Strengths

- **Phased, reversible delivery.** Phases 0–6 have narrow scope, clear deliverables, test criteria, and rollback. Blast radius is limited; failures can be isolated to one phase.
- **Design locked and documented.** Outbound origin (Asterisk only), PSTN vs internal (digit length >7 vs ≤6), module choice (drouting), group IDs (0/1), DID groups by prefix, and carrier IP storage (dr_gateways) are resolved and consistently used.
- **Route order and risks addressed.** §4.1 defines insertion points (after OPTIONS/NOTIFY ~598, before REGISTER ~600 for “from carrier?”; before DOMAIN_CHECK ~683 for “to PSTN?”) and the risk table explains how this avoids breaking REGISTER/OPTIONS, treating endpoints as carrier, or sending internal calls to PSTN.
- **Schema and installer aligned.** `scripts/peering-create.sql` matches OpenSIPS 3.6 drouting/alias_db/registrant schema; `scripts/init-database.sh` runs it when `dr_gateways` is missing. Phase 0 is done and allows parallel admin-panel and config work.
- **Single reference for implementers.** Config build checklist (§12), admin panel requirements (§16), and example data (§15) give a single place to look when building config or UI.
- **“From Asterisk” already in config.** The template already has `route[CHECK_IS_FROM_ASTERISK]` (dispatcher lookup by `$si`). The “to PSTN?” branch can call it and test `$var(is_from_asterisk) == 1` and `$rU` length > 7 before `do_routing("0")`, reducing implementation guesswork.

### 17.2 Risk assessment

| Risk | Level | Mitigation / note |
|------|--------|-------------------|
| **“From Asterisk” / To-PSTN logic wrong** | Medium | Use existing `route(CHECK_IS_FROM_ASTERISK)`; then only if `$var(is_from_asterisk)==1` and `$rU` length > 7 run `do_routing("0")`. Test: INVITE from Asterisk with 10-digit RURI → carrier; 5-digit → endpoint path. |
| **Carrier vs Asterisk IP confusion** | Medium | **Do not** put Asterisk backend IPs in `dr_gateways` for *carrier identification*. Asterisk IPs stay in **dispatcher** only. Inbound DID → Asterisk uses *separate* dr_gateways rows whose *address* is the Asterisk SIP URI (destination). So: dr_gateways = carrier IPs (source check) + Asterisk backends as *destinations* for DID rules. |
| **OPTIONS from carrier get 404** | Low | Plan correctly has “from carrier?” only for INVITE. OPTIONS from carrier IP fall through to DOMAIN_CHECK and may 404. If a carrier requires 200 OK for OPTIONS, add an optional branch: `if (is_method("OPTIONS") && is_from_gw(-1,"n")) { sl_send_reply(200,"OK"); exit; }` (Phase 3 or 6). |
| **CREATE INDEX not idempotent** | Low | `peering-create.sql` uses `CREATE INDEX` without `IF NOT EXISTS` (MySQL limitation). init-database.sh runs the script only when `dr_gateways` is missing, so the index is created once. Manual re-run of the SQL file can hit duplicate index error; documented in script comment. |
| **Multi-tenant (dr_groups) under-specified** | Low | dr_groups and per-tenant carriers/DIDs are in scope but Phase 6 “configure if needed.” Acceptable; document tenant-to-groupid mapping when first multi-tenant deployment is done. |
| **Security (Phase 6) deferred** | Low | Fail2ban and peering-specific logging are optional. Unknown IPs hitting “from carrier?” simply fall through (no match); no new open relay. Revisit in Phase 6. |
| **registrant / alias_db column names** | Low | Schema was taken from official OpenSIPS MySQL scripts; one-off verify against OpenSIPS 3.6 uac_registrant and alias_db docs (e.g. `cluster_shtag` in registrant) when loading modules. |

### 17.3 Overall comment

The plan is **implementation-ready**. Phase 0 (tables + installer) is complete; Phases 1–6 are config and data work with clear insertion points and existing helpers (`CHECK_IS_FROM_ASTERISK`, `GET_DOMAIN_FROM_SOURCE_IP`). Remaining risk is concentrated in getting the “to PSTN?” branch condition exact (Asterisk + long number only) and keeping carrier IPs (for `is_from_gw`) strictly separate from Asterisk IPs (dispatcher only). Explicitly referencing `CHECK_IS_FROM_ASTERISK` in the “to PSTN?” insertion note and stating the carrier-vs-Asterisk data rule in the config checklist would further reduce that risk. Proceed with Phase 1 after a quick sanity check that drouting loads and no existing flows regress.
