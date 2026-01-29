# Quick Start – Agent Context

**Last updated:** January 2026  
**Read this first** to get current state and next steps.

---

## Current state

- **Branch:** main (cleanupV2 merged). Docs reorganized in `docs/`.
- **OpenSIPS:** Running; usrloc/registrar; Pike flood detection; failed-registration + door-knock logging; Fail2ban integration.
- **Fail2ban:** Running; jail `opensips-brute-force`; admin panel shows status; sudoers set for www-data; sync script avoids duplicate `ignoreip`.
- **Admin panel (pbx3sbc-admin):** Fail2ban status, whitelist, ban/unban; uses sync script with DB credentials (env or args).

---

## Most recent work

**Session:** [SESSIONS/RECENT/SESSION-SUMMARY-FAIL2BAN-ADMIN-PANEL-FIX.md](SESSIONS/RECENT/SESSION-SUMMARY-FAIL2BAN-ADMIN-PANEL-FIX.md)

- Fixed duplicate `ignoreip` in Fail2ban config (sync script + fix script).
- Added sudoers for www-data (systemctl, fail2ban-client, sync script).
- Fail2banService: service running check, better status parsing.
- WhitelistSyncService: calls sync script (no direct config write).
- Installer runs setup-admin-panel-sudoers.sh and fix-duplicate-ignoreip when needed.

**Ready but not yet exercised:** Whitelist sync from admin panel, ban/unban from UI.

---

## Next steps (from last session)

1. **Test whitelist sync** – Add whitelist in admin panel, confirm it syncs to Fail2ban.
2. **Test ban/unban** – Confirm ban/unban from admin panel.
3. **Security & Threat Detection** – Phase 0 mostly done (Pike tested, ratelimit deferred). Remaining: create `docs/security/SECURITY-ARCHITECTURE-DECISIONS.md`.

---

## Key files

| What | Where |
|------|--------|
| OpenSIPS config | `config/opensips.cfg.template` |
| Fail2ban jail | `config/fail2ban/opensips-brute-force.conf` |
| Whitelist sync | `scripts/sync-fail2ban-whitelist.sh` |
| Sudoers setup | `scripts/setup-admin-panel-sudoers.sh` |
| Doc index | `docs/index.md` |
| Project context | `docs/PROJECT-CONTEXT.md` |
| Master plan | `docs/MASTER-PROJECT-PLAN.md` |

---

## Architecture (short)

- **Proxy-registrar:** OpenSIPS proxies REGISTER to Asterisk, stores location in usrloc for routing. See [ARCHITECTURE/ARCHITECTURE-PROXY-REGISTRAR-NAT.md](ARCHITECTURE/ARCHITECTURE-PROXY-REGISTRAR-NAT.md).
- **Usrloc:** `location` table; save on 200 OK; lookup for routing. Quick ref: [QUICK-REFERENCES/USRLOC-QUICK-REFERENCE.md](QUICK-REFERENCES/USRLOC-QUICK-REFERENCE.md).
- **Fail2ban:** Monitors OpenSIPS logs (failed regs + door-knock); blocks at firewall. Whitelist from DB via sync script.

---

## If user says “continue” or “what next”

1. Re-read this file and the most recent session summary in SESSIONS/RECENT/.
2. Check “Next steps” above and in that session summary.
3. Prefer: test Fail2ban from admin panel, then Security Phase 0 (architecture doc).
