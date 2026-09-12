-- DIAGNOSTYKA: czy WarehouseRequest do konkretnego dostawcy (tag 35) nadal koreluje ze strata.
-- @opis Base-rate per dostawca: nie "ile strat ma tag Libri", tylko "czy zamowienia z requestem
--       do Libri psuja sie czesciej niz reszta". Bez porownania do bazy tag 35 nic nie znaczy,
--       bo check stratne-przyczyny patrzy WYLACZNIE na zamowienia juz stratne (selekcja po wyniku).
-- ⚠️ TRYB EKSPLORACJI: okno parametryzowane, domyslnie 90 dni

DECLARE dni_wstecz INT64 DEFAULT 90;

WITH zam AS (
  SELECT CustomerOrderId, Profit_Actual, OrderCreatedOnUtc
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND OrderStatusId <> 40
    AND IsDoneCalculating
),
-- dostawca wyciagniety z Note tagu 35; jedno zamowienie moze miec kilku dostawcow
tag35 AS (
  SELECT DISTINCT
         t.CustomerOrderId,
         TRIM(REGEXP_EXTRACT(t.Note, r'było do (.+)$')) AS Dostawca
  FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` t
  WHERE t.TagId = 35
    AND t.CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz + 30 DAY)
),
polaczone AS (
  SELECT z.CustomerOrderId, z.Profit_Actual, COALESCE(t.Dostawca, '— BAZA (bez tagu 35) —') AS Dostawca
  FROM zam z
  LEFT JOIN tag35 t ON t.CustomerOrderId = z.CustomerOrderId
)
SELECT
  Dostawca,
  COUNT(*)                                                              AS Zamowien,
  ROUND(100 * AVG(CASE WHEN Profit_Actual < 0 THEN 1 ELSE 0 END), 1)    AS Pct_stratnych,
  ROUND(AVG(Profit_Actual), 2)                                          AS Sr_profit_PLN,
  ROUND(APPROX_QUANTILES(Profit_Actual, 100)[OFFSET(50)], 2)            AS Mediana_profit,
  ROUND(SUM(CASE WHEN Profit_Actual < 0 THEN Profit_Actual END), 0)     AS Suma_strat_PLN,
  ROUND(SUM(Profit_Actual), 0)                                          AS Wynik_netto_PLN
FROM polaczone
GROUP BY Dostawca
HAVING Zamowien >= 30
ORDER BY Pct_stratnych DESC
