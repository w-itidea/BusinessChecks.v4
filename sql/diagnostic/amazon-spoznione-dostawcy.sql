-- DIAGNOSTYKA: spoznione zamowienia Amazon (niewyslane po ShipLatestDateUtc)
--              + czy KTOKOLWIEK ma dzis stan i gdzie najtaniej (SupplierPA, stan biezacy).
--
-- To jest odpowiednik raportu "Watchdog: Amazon — spoznienia i zagrozenia" policzony z mirrora,
-- z dolozona odpowiedzia "czy mamy dostawce i gdzie kupic najtaniej".
--
-- WAZNE ograniczenie: SupplierPA to STAN BIEZACY (mirror nadpisywany po (EAN, SupplierId)).
-- "Co dostawca obiecywal w dniu wystawienia oferty" NIE jest odtwarzalne z tej tabeli —
-- do przyczyny zrodlowej (stan u dostawcy, ktory sie nie ziscil) potrzebny mirror
-- WarehouseRequest. Patrz runs/2026-08-28-amazon-spoznione-i-przeplaty.md, sekcja Otwarte.
--
-- Diagnostyka 2026-08-28: 16 spoznionych, z 18 EAN-ow 6 bez zadnego dostawcy ze stanem.

DECLARE dni_wstecz INT64 DEFAULT 120;  -- okno partycji CreatedOnUtc (spoznione starsze nie wystepuja)

WITH spoznione AS (
  SELECT Id, IdBookstore,
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), ShipLatestDateUtc, HOUR) AS h_po_terminie
  FROM `polish-bookstores-group.BIData.azymut_CustomerOrder`
  WHERE CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND IdBookstore LIKE 'AZ-%'
    AND ShippedDateUtc IS NULL
    AND ShipLatestDateUtc < CURRENT_TIMESTAMP()
    AND OrderStatusId <> 40
    AND NOT Deleted
),
pozycje AS (
  SELECT oi.CustomerOrderId, oi.EAN
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit` oi
  JOIN spoznione s ON oi.CustomerOrderId = s.Id
),
dostepnosc AS (
  SELECT EAN, SupplierId, iloscDostepna, PriceNetWithLogistics, DispatchDays
  FROM `polish-bookstores-group.BIData.azymut_SupplierPA`
  WHERE iloscDostepna > 0
)
SELECT
  p.CustomerOrderId                       AS Zamowienie,
  s.IdBookstore                           AS Rynek,
  s.h_po_terminie                         AS H_po_terminie,
  p.EAN,
  COUNT(d.SupplierId)                     AS Dostawcow_ze_stanem,
  ARRAY_AGG(STRUCT(d.SupplierId, d.PriceNetWithLogistics, d.DispatchDays, d.iloscDostepna)
            ORDER BY d.PriceNetWithLogistics LIMIT 1)[SAFE_OFFSET(0)] AS Najtanszy
FROM pozycje p
JOIN spoznione s ON s.Id = p.CustomerOrderId
LEFT JOIN dostepnosc d ON d.EAN = p.EAN
GROUP BY p.CustomerOrderId, s.IdBookstore, s.h_po_terminie, p.EAN
ORDER BY Dostawcow_ze_stanem ASC, s.h_po_terminie DESC
