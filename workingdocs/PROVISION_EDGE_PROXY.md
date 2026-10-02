# Fleet edge provision proxy (C2 + C5)

**Status:** **C2+C5 lab green** on SBC (2026-10-02). Live: `PROVISION_MTLS=optional` + Snom/Yealink CA PEM.  
**Spec:** `pbx3/workingdocs/PROVISIONING_SERVER_REQUIREMENTS.md` §0.3 / §6 / §8 / #3 / #11 · plan **C2/C5**.  
**Depends:** Gatekeeper **C3** MAC index + `catalog/provision-mac.map`.

## Shape

```text
Phone → https://provision.{apex}:41363/provisioning/{mac}.cfg
     or https://provision.{apex}:41363/provisioning?mac={mac}   (Snom)
  → nginx [optional mTLS] → MAC extract → local provision-mac.map → http://{home}:41363
```

- Edge terminates **HTTPS**; **no** 3xx to home (topology hiding).
- **#11:** no routable MAC / Yealink `y000000*` / ignore list / bare `/provisioning` → **404**.
- **#3:** map is a **static file** on the SBC; GET never calls gatekeeper/S3.
- **C5:** vendor client-cert verify against ops-held CA PEM (Snom + Yealink near-term).

## Install (SBC)

1. DNS: `provision.{apex}` A/AAAA → **edge VIP** (same VIP family as SIP).
2. LE cert for `provision.{apex}` (port **41363** is not 443 — use `certbot certonly --webroot` or DNS-01; reuse admin webroot on :80 if convenient, then point ssl paths at the new name).
3. Open **UFW 41363/tcp** phone-facing on the edge (this is the public provision port). Homes stay **SBC-only** on 41363.
4. Install vhost (C2 only):

```bash
cd ~/pbx3sbc   # or deploy path
sudo PROVISION_FQDN=provision.pbx3.com ./scripts/install-provision-edge.sh
```

5. **C5 mTLS** (Snom + Yealink lab prove) — copy ops CA PEM then reinstall:

```bash
# On operator Mac (ops repo): build Snom+Yealink-only PEM from local inventory pack
./devdocs/provisioning/extract-snom-yealink-client-cas.sh \
  /path/to/ops-held-3pcerts.pem \
  ./devdocs/provisioning/inventory/vendor-client-cas-snom-yealink.pem

# On SBC:
sudo VENDOR_CLIENT_CA_BUNDLE=/path/to/vendor-client-cas-snom-yealink.pem \
     PROVISION_MTLS=optional \
     PROVISION_FQDN=provision.pbx3.com \
     ./scripts/install-provision-edge.sh
```

| `PROVISION_MTLS` | nginx `ssl_verify_client` | Behaviour |
|-------------------|--------------------------|-----------|
| `off` | (omitted) | No client-cert verify (default when no CA file) |
| `optional` | `optional` | **Lab default when CA present** — verify if phone presents cert; allow curl / manual-URL brands without cert |
| `require` | `on` | Hardened public edge — TLS fails without trusted client cert |

6. Sync map after MAC claims (or cron):

```bash
sudo PBX3_ORG_BUCKET=08jzwn-pbx3 ./scripts/sync-provision-mac-map.sh
# or: sudo PROVISION_MAC_MAP_FILE=/path/to/provision-mac.map ./scripts/sync-provision-mac-map.sh
```

7. Prove:

```bash
# known MAC in index → 200 from home via edge (path or ?mac=)
# With PROVISION_MTLS=optional, curl without client cert still works:
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning/AABBCCDDEEFF.cfg"
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning?mac=AABBCCDDEEFF"
# unknown / y000000 / bare /provisioning → 404
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning/y000000000028.cfg"
```

Snom/Yealink phones that present a vendor client cert are verified (`$ssl_client_verify=SUCCESS`); edge forwards `X-SSL-Client-Verify` / `X-SSL-Client-S-DN` to home (audit only).

## Files

| Path | Role |
|------|------|
| `config/nginx/pbx3-provision-edge.conf` | HTTPS vhost template (`__MTLS_BLOCK__`) |
| `config/nginx/pbx3-provision-log-format.conf` | `log_format provision_mtls` (`$ssl_client_verify` + DN) |
| `config/nginx/mac-from-request.map` | URI/`?mac=` → `$provision_mac` |
| `config/nginx/provision-mac.map.example` | Empty map seed |
| `config/nginx/vendor-client-cas.pem.example` | Placeholder — **do not** commit real CAs |
| `scripts/install-provision-edge.sh` | Install maps + site + optional C5 CA + reload |
| `scripts/sync-provision-mac-map.sh` | Pull catalog artifact → local + reload |

Live: `/etc/nginx/pbx3-provision/` (`provision-mac.map`, `vendor-client-cas.pem`) + `conf.d/pbx3-provision-maps.conf` + `conf.d/pbx3-provision-log-format.conf`.

## Lab status

- **C2 (2026-09-30):** DNS **A** `provision.pbx3.com` → **`3.93.26.82`**; LE; known MAC **200** / unknown **404**.
- **C5 (2026-10-02):** Yealink T31P **402** (`249ad89b435b`) — `$ssl_client_verify=SUCCESS`, **200** on `.cfg`. Bare curl under `optional` → **NONE**/200; under `require` → **400**. Snom D717 **401** reboot GET **200** (UA present). Left on **`optional`**.

## Related

- Home listener: `pbx3` `install-provision-listener.sh` (fleet HTTP).
- Catalog claim: gatekeeper `POST /api/v1/mac-index/claim` (instance hook on MAC assign).
- Ops CA inventory: `~/GiT/pbx3-ops/devdocs/provisioning/VENDOR_CLIENT_CA_INVENTORY.md`
- Optional later: **C10** Provision access IP allowlist (Filament) — complements mTLS.
