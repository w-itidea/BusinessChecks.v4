-- Zestawy rabatowe Slowianina (kup 2 -> -10%) — postep synchronizacji i sprzedaz.
--
-- ⚠️ KLUCZOWA ZASADA POMIARU (Wojtek, 2026-08-31):
-- Zamowienie liczy sie jako efekt zestawu TYLKO gdy zostalo zlozone PO tym, jak zestaw
-- trafil na sklep (CreatedOnUtc >= LastSyncedAt). Zamowienia sprzed publikacji pokazuja
-- wylacznie, ze regula doboru par byla trafna — klienci i tak kupowali te tytuly razem.
-- To NIE jest sukces testu; wrecz przeciwnie, wg taska 869ehazut para o wysokiej
-- confidence jest ZLYM kandydatem, bo rabat dostaja ci, ktorzy i tak by kupili oba.
-- Dlatego obie liczby sa raportowane osobno i nigdy nie sumowane.
--
-- ⚠️ Ograniczenie, ktorego nie da sie dzis obejsc: z zamowienia NIE wynika, czy klient
-- kliknal w zestaw, czy dolozyl dwie pozycje osobno. Selly tego nie eksponuje (otwarty
-- punkt w 869ehazut). Liczba "po publikacji" to GORNA GRANICA efektu, nie sam efekt.

DECLARE dni_okno INT64 DEFAULT 7;

WITH zestawy AS (
  SELECT d.Id, d.Name, d.SellySetId, d.LastSyncedAt,
         MIN(c.Ean) AS ean1, MAX(c.Ean) AS ean2
  FROM `polish-bookstores-group.BIData.selly_BundleDefinitions` d
  JOIN `polish-bookstores-group.BIData.selly_BundleComponents`  c ON c.BundleId = d.Id
  GROUP BY d.Id, d.Name, d.SellySetId, d.LastSyncedAt
  HAVING COUNT(*) = 2
),
zam AS (   -- zamowienia Slowianina z ostatnich 90 dni, anulowane wykluczone
  SELECT co.Id, co.CreatedOnUtc, co.IdBookstore
  FROM `polish-bookstores-group.BIData.azymut_CustomerOrder` co
  WHERE co.IdBookstore LIKE 'SN-%'
    AND co.OrderStatusId <> 40
    AND co.CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
),
pozycje AS (
  SELECT oip.CustomerOrderId, oip.EAN, oip.Quantity, oip.ItemProfit,
         oip.UnitSalesPriceNet * oip.Quantity AS wartosc
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit` oip
  JOIN zam z ON z.Id = oip.CustomerOrderId
  WHERE oip.UnitSalesPriceNet IS NOT NULL AND oip.UnitSalesPriceNet > 0
),
pary AS (   -- zamowienie zawierajace OBA skladniki zestawu
  SELECT s.Id AS zestaw_id, s.Name AS zestaw, s.LastSyncedAt,
         z.Id AS zamowienie, z.CreatedOnUtc, z.IdBookstore,
         p1.wartosc + p2.wartosc         AS wartosc,
         p1.ItemProfit + p2.ItemProfit   AS zysk,
         z.CreatedOnUtc >= s.LastSyncedAt AS po_publikacji
  FROM zestawy s
  JOIN pozycje p1 ON p1.EAN = s.ean1
  JOIN pozycje p2 ON p2.EAN = s.ean2 AND p2.CustomerOrderId = p1.CustomerOrderId
  JOIN zam z      ON z.Id  = p1.CustomerOrderId
  WHERE s.SellySetId IS NOT NULL
)

SELECT
  '1. SYNC'                                                          AS Sekcja,
  FORMAT('%d z %d na sklepie (%.1f%%)',
         COUNTIF(SellySetId IS NOT NULL), COUNT(*),
         100 * SAFE_DIVIDE(COUNTIF(SellySetId IS NOT NULL), COUNT(*)))    AS Stan,
  FORMAT('%d czeka', COUNTIF(SellySetId IS NULL))                    AS Kolejka,
  FORMAT('%d bledow', COUNTIF(COALESCE(TRIM(LastSyncError),'') != '')) AS Bledy,
  FORMAT('%d w tym tygodniu',
         COUNTIF(LastSyncedAt >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_okno DAY))) AS Tempo,
  CAST(NULL AS STRING) AS Zysk_PLN
FROM `polish-bookstores-group.BIData.selly_BundleDefinitions`

UNION ALL
SELECT
  '2. SPRZEDAZ PO PUBLIKACJI — to jest wynik testu',
  FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw_id)),
  FORMAT('okno %d dni', dni_okno),
  CAST(NULL AS STRING),
  CAST(NULL AS STRING),
  FORMAT('%.2f zl (wartosc %.2f)', SUM(zysk), SUM(wartosc))
FROM pary
WHERE po_publikacji
  AND CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_okno DAY)

UNION ALL
SELECT
  '3. PO PUBLIKACJI — narastajaco od poczatku',
  FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw_id)),
  CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
  FORMAT('%.2f zl', SUM(zysk))
FROM pary WHERE po_publikacji

UNION ALL
SELECT
  '4. PRZED publikacja — NIE wynik testu, tylko trafnosc doboru par',
  FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw_id)),
  CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
  FORMAT('%.2f zl', SUM(zysk))
FROM pary WHERE NOT po_publikacji

ORDER BY Sekcja;
