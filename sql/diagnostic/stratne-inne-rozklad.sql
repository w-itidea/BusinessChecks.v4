-- DIAGNOSTYKA: rozklad strat w kuble "inne / zlozone" (tydzien).
-- Pytanie: to sa drobne straty rozlozone rowno, czy kilkanascie powaznych ukrytych wsrod groszowych?
-- Od odpowiedzi zalezy, czy kubel trzeba dzielic, czy wystarczy prog istotnosci.

DECLARE dni_wstecz INT64 DEFAULT 7;

WITH stratne AS (
  SELECT
    CustomerOrderId, IdBookstore, fOrderTotal, Profit_Actual, ProductCost, ShippingCost,
    CASE
      WHEN fOrderTotal < ProductCost                                     THEN 'sprzedaz ponizej kosztu towaru'
      WHEN ShippingCost > (fOrderTotal - ProductCost)                    THEN 'wysylka zjada marze'
      WHEN SAFE_DIVIDE(MarketplaceCost, NULLIF(fOrderTotal, 0)) > 0.25   THEN 'koszty marketplace > 25%'
      WHEN SAFE_DIVIDE(PaymentCost, NULLIF(fOrderTotal, 0)) > 0.10       THEN 'koszty platnosci > 10%'
      ELSE 'inne / zlozone'
    END AS przyczyna
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND OrderStatusId <> 40
    AND IsDoneCalculating
    AND Profit_Actual < 0
)
SELECT
  CASE
    WHEN Profit_Actual > -2   THEN 'a) 0 do -2 zl   (szum)'
    WHEN Profit_Actual > -5   THEN 'b) -2 do -5 zl'
    WHEN Profit_Actual > -10  THEN 'c) -5 do -10 zl'
    WHEN Profit_Actual > -25  THEN 'd) -10 do -25 zl'
    ELSE                           'e) ponizej -25 zl (istotne)'
  END                                       AS Przedzial,
  COUNT(*)                                  AS Zamowien,
  ROUND(SUM(Profit_Actual), 2)              AS Strata_PLN,
  ROUND(SUM(Profit_Actual) * 100.0
        / SUM(SUM(Profit_Actual)) OVER (), 1) AS Udzial_w_stracie_pct,
  ROUND(AVG(fOrderTotal), 2)                AS Sr_wartosc_zam
FROM stratne
WHERE przyczyna = 'inne / zlozone'
GROUP BY Przedzial
ORDER BY Przedzial
