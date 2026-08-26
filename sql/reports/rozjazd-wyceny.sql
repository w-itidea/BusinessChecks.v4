-- CHECK: rozjazd wyceny na WSZYSTKICH zamowieniach, nie tylko stratnych.
-- @opis Gdzie i o ile cena z momentu oferty rozjeżdża się z ceną w momencie zamówienia.
--
-- Pytanie: czy pieniadze sa w stratach (ogon rozkladu), czy w utraconej marzy (caly rozklad)?
-- Straty widac, bo maja znak minus. Rozjazd wyceny na zamowieniu zyskownym nie rzuca sie
-- w oczy — zamowienie dalej "zarabia", tylko mniej niz mialo. Tu mierzymy jedno i drugie
-- ta sama miara: ile kosztowalo wiecej, niz zalozono przy wycenie.

DECLARE dni_wstecz INT64 DEFAULT 7;

WITH zam AS (
  SELECT
    op.CustomerOrderId,
    op.Profit_Actual,
    op.ProductCost,
    op.ProductCost_Estimated,
    sc.fShippingCostTotal,
    sc.ShippingCostTotal_EstimatedPreShipments AS wysylka_wycena,
    IF(op.Profit_Actual < 0, 'stratne', 'zyskowne') AS grupa
  FROM `polish-bookstores-group.BIData.opi_OrderProfit` op
  LEFT JOIN `polish-bookstores-group.BIData.opi_ShippingCost` sc
         ON sc.CustomerOrderId = op.CustomerOrderId
  WHERE op.OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND op.OrderStatusId <> 40
    AND op.IsDoneCalculating
)
SELECT
  grupa                                                              AS Grupa,
  COUNT(*)                                                           AS Zamowien,
  ROUND(SUM(Profit_Actual), 2)                                       AS Zysk_netto_PLN,
  -- ile towar kosztowal PONAD wycene (dodatnie = drozej niz zakladano)
  ROUND(SUM(COALESCE(ProductCost, 0) - COALESCE(ProductCost_Estimated, 0)), 2) AS Towar_ponad_wycene,
  -- ile wysylka kosztowala PONAD wycene
  ROUND(SUM(COALESCE(fShippingCostTotal, 0) - COALESCE(wysylka_wycena, 0)), 2) AS Wysylka_ponad_wycene,
  -- ile zamowien ma rozjazd > 5 zl (na plus dla nas = koszt wyzszy niz wycena)
  COUNTIF(COALESCE(ProductCost,0) - COALESCE(ProductCost_Estimated,0) > 5)      AS Zam_towar_drozej_5zl,
  COUNTIF(COALESCE(fShippingCostTotal,0) - COALESCE(wysylka_wycena,0) > 5)      AS Zam_wysylka_drozej_5zl
FROM zam
GROUP BY grupa
ORDER BY grupa
