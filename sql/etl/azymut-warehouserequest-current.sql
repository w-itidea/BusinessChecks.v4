-- WIDOK: stan biezacy nad logiem przyrostowym azymut_WarehouseRequest (tryb append_log).
--
-- Log DOPISUJE kazda wersje wiersza zmieniona od watermarku (co ~8h), wiec:
--   * historia zmian statusu zostaje w tabeli (to jest feature — pomiar ETA jej wymaga),
--   * duplikaty z nakladki watermarku (OVERLAP_MIN) sa oczekiwane,
--   * stan biezacy = najnowsza wersja per PK — TEN widok.
-- Checki liczace "co jest teraz" czytaja WYLACZNIE widok; po logu jezdza tylko analizy historii.
--
-- Zalozyc PO pierwszym syncu (tabela musi istniec):
--   bq --project_id=polish-bookstores-group --location=europe-west3 query \
--     --use_legacy_sql=false < sql/etl/azymut-warehouserequest-current.sql
--
-- UWAGA: PK (Id) i watermark (LastUpdated) ZGADNIETE — zweryfikuj przez
--   python3 -m etl.sync --table azymut_WarehouseRequest --describe   (na VPN)
-- i popraw ponizej, zanim widok powstanie.

-- ⚠️ mirror-health: po pierwszym syncu dolozyc galaz UNION dla tej tabeli, ale z dedupem
-- liczonym NA WIDOKU _current, nie na logu — duplikaty w logu sa CECHA trybu append_log
-- (nakladka watermarku + wersje wiersza), nie awaria. Galaz na surowym logu krzyczalaby
-- codziennie, a alarm, ktory zawsze wyje, przestaje cokolwiek znaczyc (lekcja z
-- ofi_AmazonFeedProductSettings w mirror-health.sql).

CREATE OR REPLACE VIEW `polish-bookstores-group.BIData.azymut_WarehouseRequest_current` AS
SELECT *
FROM `polish-bookstores-group.BIData.azymut_WarehouseRequest`
QUALIFY ROW_NUMBER() OVER (PARTITION BY Id ORDER BY LastUpdated DESC, CreatedOnUtc DESC) = 1
