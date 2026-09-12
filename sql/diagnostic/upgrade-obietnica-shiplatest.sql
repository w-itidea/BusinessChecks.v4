-- czy skrocila sie OBIETNICA (ShipLatestDateUtc z Note) wzgledem daty zamowienia
WITH t AS (
  SELECT CustomerOrderId,
         PARSE_TIMESTAMP('%Y-%m-%d %H:%M:%SZ', REGEXP_EXTRACT(Note, r'\((\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}Z)\)')) deadline
  FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` WHERE TagId=38),
z AS (SELECT CustomerOrderId, OrderCreatedOnUtc, IdBookstore FROM `polish-bookstores-group.BIData.opi_OrderProfit`
      WHERE OrderCreatedOnUtc >= TIMESTAMP('2026-05-01') AND OrderStatusId<>40 AND IsDoneCalculating)
SELECT FORMAT_DATE('%Y-%m', DATE(z.OrderCreatedOnUtc)) Miesiac, COUNT(*) n,
  ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(t.deadline, z.OrderCreatedOnUtc, HOUR),100)[OFFSET(50)],0) Mediana_h_obietnicy,
  ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(t.deadline, z.OrderCreatedOnUtc, HOUR),100)[OFFSET(10)],0) p10_h
FROM t JOIN z USING (CustomerOrderId) WHERE t.deadline IS NOT NULL
GROUP BY 1 ORDER BY 1
