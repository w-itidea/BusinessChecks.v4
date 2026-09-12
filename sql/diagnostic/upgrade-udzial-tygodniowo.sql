-- udzial tygodniowo, po dacie ZAMOWIENIA, z dojrzaloscia tagow (tydzien zamkniety)
WITH zam AS (
  SELECT CustomerOrderId, DATE_TRUNC(DATE(OrderCreatedOnUtc), WEEK(MONDAY)) tydz
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP('2026-06-01')
    AND OrderCreatedOnUtc < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 DAY)
    AND OrderStatusId <> 40 AND IsDoneCalculating),
t38 AS (SELECT DISTINCT CustomerOrderId FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` WHERE TagId=38)
SELECT z.tydz Tydzien, COUNT(*) Zam, COUNTIF(t.CustomerOrderId IS NOT NULL) Upgrade,
  ROUND(100*SAFE_DIVIDE(COUNTIF(t.CustomerOrderId IS NOT NULL),COUNT(*)),2) Pct
FROM zam z LEFT JOIN t38 t USING (CustomerOrderId) GROUP BY 1 ORDER BY 1
