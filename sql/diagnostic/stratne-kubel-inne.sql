-- DIAGNOSTYKA: co naprawde siedzi w kuble "inne / zlozone"? Probka tygodniowa.
--
-- Cel: dobrac progi klasyfikacji na danych, a nie na przeczuciu. Dla kazdego stratnego
-- zamowienia liczymy udzial kazdego skladnika kosztu w wartosci zamowienia i sprawdzamy,
-- ktory z nich najczesciej odpowiada za strate w zamowieniach dzis nieskasyfikowanych.

DECLARE dni_wstecz INT64 DEFAULT 7;

WITH stratne AS (
  SELECT
    CustomerOrderId, IdBookstore, fOrderTotal, Profit_Actual,
    ProductCost, ShippingCost, MarketplaceCost, PaymentCost, HandlingCost, PackagingCost,
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
  przyczyna                                                       AS Przyczyna,
  COUNT(*)                                                        AS Zamowien,
  ROUND(SUM(Profit_Actual), 2)                                    AS Strata_PLN,
  -- sredni udzial skladnikow w wartosci zamowienia (co zjada kase)
  ROUND(AVG(SAFE_DIVIDE(ProductCost,     NULLIF(fOrderTotal,0))) * 100, 1) AS Towar_pct,
  ROUND(AVG(SAFE_DIVIDE(ShippingCost,    NULLIF(fOrderTotal,0))) * 100, 1) AS Wysylka_pct,
  ROUND(AVG(SAFE_DIVIDE(MarketplaceCost, NULLIF(fOrderTotal,0))) * 100, 1) AS Marketplace_pct,
  ROUND(AVG(SAFE_DIVIDE(PaymentCost,     NULLIF(fOrderTotal,0))) * 100, 1) AS Platnosc_pct,
  ROUND(AVG(SAFE_DIVIDE(HandlingCost + PackagingCost, NULLIF(fOrderTotal,0))) * 100, 1) AS Obsluga_pct,
  ROUND(AVG(fOrderTotal), 2)                                      AS Sr_wartosc,
  ROUND(AVG(Profit_Actual), 2)                                    AS Sr_strata
FROM stratne
GROUP BY przyczyna
ORDER BY Strata_PLN ASC
