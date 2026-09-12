-- ta sama kontrola, ale po KRAJU DOCELOWYM (nie rynku) + waga
WITH zam AS (
  SELECT CustomerOrderId, Profit_Actual,
    CASE WHEN OrderWeight <= 0.10 THEN 'a' WHEN OrderWeight <= 0.25 THEN 'b'
         WHEN OrderWeight <= 0.50 THEN 'c' WHEN OrderWeight <= 1.00 THEN 'd' ELSE 'e' END AS waga
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 60 DAY)
    AND OrderStatusId <> 40 AND IsDoneCalculating AND OrderWeight > 0),
t38 AS (SELECT DISTINCT CustomerOrderId FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` WHERE TagId=38),
dane AS (
  SELECT s.ShippingCountryIso2 kraj, z.waga, s.ShipmentMethodName met, s.fShippingCostTotal koszt,
         t.CustomerOrderId IS NOT NULL AS up
  FROM zam z JOIN `polish-bookstores-group.BIData.opi_ShippingCost` s USING (CustomerOrderId)
  LEFT JOIN t38 t USING (CustomerOrderId)),
tanie AS (SELECT kraj, waga, AVG(koszt) tani, COUNT(*) n FROM dane
          WHERE NOT up AND (met LIKE '%UNTR%' OR met LIKE '%MINI%') GROUP BY 1,2)
SELECT d.met Metoda, COUNT(*) Zam, ROUND(AVG(d.koszt),2) Koszt,
  ROUND(AVG(k.tani),2) Kontrfaktyk, ROUND(AVG(d.koszt-k.tani),2) Doplata, ROUND(SUM(d.koszt-k.tani),0) Suma_60d
FROM dane d JOIN tanie k ON k.kraj=d.kraj AND k.waga=d.waga
WHERE d.up AND d.met NOT LIKE '%UNTR%' AND d.met NOT LIKE '%MINI%' AND k.n >= 20
GROUP BY 1 HAVING Zam >= 30 ORDER BY Suma_60d DESC
