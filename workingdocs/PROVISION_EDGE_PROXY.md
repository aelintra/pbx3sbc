# Fleet edge provision proxy (C2)

**Status:** Lab tip-hot on control + SBC (2026-09-30). Templates in repo; DNS+LE for `provision.pbx3.com` still operator.  
**Spec:** `pbx3/workingdocs/PROVISIONING_SERVER_REQUIREMENTS.md` §0.3 / §6 / #3 / #11 · plan **C2**.  
**Depends:** Gatekeeper **C3** MAC index + `catalog/provision-mac.map`.

## Shape

```text
Phone → https://provision.{apex}:41363/provisioning/{mac}.cfg
     or https://provision.{apex}:41363/provisioning?mac={mac}   (Snom)
  → nginx MAC extract → local provision-mac.map → http://{home}:41363 (same URI)
```

- Edge terminates **HTTPS**; **no** 3xx to home (topology hiding).
- **#11:** no routable MAC / Yealink `y000000*` / ignore list / bare `/provisioning` → **404**.
- **#3:** map is a **static file** on the SBC; GET never calls gatekeeper/S3.

## Install (SBC)

1. DNS: `provision.{apex}` A/AAAA → **edge VIP** (same VIP family as SIP).
2. LE cert for `provision.{apex}` (port **41363** is not 443 — use `certbot certonly --webroot` or DNS-01; reuse admin webroot on :80 if convenient, then point ssl paths at the new name).
3. Open **UFW 41363/tcp** phone-facing on the edge (this is the public provision port). Homes stay **SBC-only** on 41363.
4. Install vhost:

```bash
cd ~/pbx3sbc   # or deploy path
sudo PROVISION_FQDN=provision.pbx3.com ./scripts/install-provision-edge.sh
```

5. Sync map after MAC claims (or cron):

```bash
sudo PBX3_ORG_BUCKET=08jzwn-pbx3 ./scripts/sync-provision-mac-map.sh
# or: sudo PROVISION_MAC_MAP_FILE=/path/to/provision-mac.map ./scripts/sync-provision-mac-map.sh
```

6. Prove:

```bash
# known MAC in index → 200 from home via edge (path or ?mac=)
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning/AABBCCDDEEFF.cfg"
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning?mac=AABBCCDDEEFF"
# unknown / y000000 / bare /provisioning → 404
curl -sk -o /dev/null -w '%{http_code}\n' \
  "https://provision.pbx3.com:41363/provisioning/y000000000028.cfg"
```

## Files

| Path | Role |
|------|------|
| `config/nginx/pbx3-provision-edge.conf` | HTTPS vhost template |
| `config/nginx/mac-from-request.map` | URI/`?mac=` → `$provision_mac` |
| `config/nginx/provision-mac.map.example` | Empty map seed |
| `scripts/install-provision-edge.sh` | Install maps + site + reload |
| `scripts/sync-provision-mac-map.sh` | Pull catalog artifact → local + reload |

Live includes: `/etc/nginx/pbx3-provision/` + `conf.d/pbx3-provision-maps.conf`.

## Lab status (2026-09-30)

- DNS **A** `provision.pbx3.com` → **`3.93.26.82`** live; **LE** cert issued (expires 2026-12-29); edge vhost on LE paths.
- Curl prove (no `--resolve`): known MAC **200**, unknown/**y000000** **404**.
- Golden SG: TCP **41363** from SBC VIP + `98.80.101.240`.
- Map sync: `PBX3_ORG_BUCKET=08jzwn-pbx3 ./scripts/sync-provision-mac-map.sh`

## mTLS (C5 later)

Client-cert verify is commented in the vhost. Gate on **D1** CA inventory (Snom/Yealink first).

## Related

- Home listener: `pbx3` `install-provision-listener.sh` (fleet HTTP).
- Catalog claim: gatekeeper `POST /api/v1/mac-index/claim` (instance hook on MAC assign).
