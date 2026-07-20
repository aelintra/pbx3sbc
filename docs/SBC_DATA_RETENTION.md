# SBC data retention (pointer)

**Project home:** **`pbx3/pbx3-directory/docs/SBC_DATA_RETENTION_REQUIREMENTS.md`**  
**Operator guide:** **`pbx3-docs/docs/fleet/sbc-data-retention.md`** (MkDocs).

Text/pcap rotation already shipped — see **`FLEET_LOG_RETENTION.md`**. MySQL aging: artisan **`pbx3sbc:purge-security-events`** (30d) and **`pbx3sbc:purge-acc`** (90d); Filament **Logs → Data retention**; cron **`pbx3sbc-admin/deploy/cron.d/pbx3sbc-retention.example`**.
