-- CHECK: GDZIE estymacja kosztu wysylki myli sie systematycznie.
--
-- Sortowane wg lacznego rozjazdu (najwiecej pieniedzy na gorze), bo pytanie brzmi
-- "co naprawic najpierw", a nie "gdzie procent jest najwyzszy" — wysoki procent na
-- 3 zamowieniach to ciekawostka, nie priorytet.
--
-- Rozjazd dodatni = realny koszt WYZSZY niz wycena = marza oddana po cichu.
-- Liczone na WSZYSTKICH zamowieniach (nie tylko stratnych) — bo 91% tych pieniedzy
-- siedzi w zamowieniach, ktore nadal "zarabiaja".

DECLARE dni_wstecz INT64 DEFAULT 7;
DECLARE min_zamowien INT64 DEFAULT 5;   -- ponizej tego to szum, nie wzorzec

WITH dane AS (
  SELECT
    COALESCE(sc.ShipmentMethodName, '(brak metody)')            AS metoda,
    COALESCE(sc.ShippingCompany, '(brak)')                      AS przewoznik,
    COALESCE(sc.ShippingCountryIso2, '??')                      AS kraj,
    COALESCE(sc.fShippingCostTotal, 0)
      - COALESCE(sc.ShippingCostTotal_EstimatedPreShipments, 0) AS rozjazd,
    COALESCE(sc.ShippingCostTotal_EstimatedPreShipments, 0)     AS wycena,
    COALESCE(sc.fShippingCostTotal, 0)                          AS realnie,
    op.Profit_Actual
  FROM `polish-bookstores-group.BIData.opi_OrderProfit` op
  JOIN `polish-bookstores-group.BIData.opi_ShippingCost` sc
       ON sc.CustomerOrderId = op.CustomerOrderId
  WHERE op.OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND op.OrderStatusId <> 40
    AND op.IsDoneCalculating
)
SELECT
  metoda                                         AS Metoda,
  przewoznik                                     AS Przewoznik,
  COUNT(*)                                       AS Zamowien,
  ROUND(SUM(rozjazd), 2)                         AS Rozjazd_PLN,
  ROUND(AVG(rozjazd), 2)                         AS Sr_rozjazd,
  ROUND(AVG(wycena), 2)                          AS Sr_wycena,
  ROUND(AVG(realnie), 2)                         AS Sr_realnie,
  ROUND(SAFE_DIVIDE(AVG(realnie), NULLIF(AVG(wycena), 0)), 2) AS Krotnosc,
  COUNTIF(rozjazd > 5)                           AS Zam_ponad_5zl,
  COUNTIF(Profit_Actual < 0)                     AS Z_tego_stratnych
FROM dane
GROUP BY metoda, przewoznik
HAVING COUNT(*) >= min_zamowien
ORDER BY Rozjazd_PLN DESC
