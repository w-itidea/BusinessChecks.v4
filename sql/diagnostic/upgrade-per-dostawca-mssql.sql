-- ⚠️ TRYB EKSPLORACJI: sierpien 2026. Base rate upgrade'u per dostawca (tylko zamowienia,
-- ktore w ogole wymagaly zakupu towaru) — czy ktorys dostawca wyroznia sie negatywnie.
DECLARE @od DATE = '2026-08-01', @do DATE = '2026-09-01';

IF OBJECT_ID('tempdb..#t38') IS NOT NULL DROP TABLE #t38;
SELECT DISTINCT CustomerOrderId INTO #t38
FROM BIData.opi.OrderProfitTag (NOLOCK) WHERE TagId = 38;

SELECT TOP (20)
    LEFT(ISNULL(o.GOODS_RECEIVED_supplier, o.GOODS_ORDERED_supplier), 22)        [Dostawca],
    COUNT(*)                                                                     [Zamowien],
    SUM(CASE WHEN t.CustomerOrderId IS NOT NULL THEN 1 ELSE 0 END)               [Z_upgrade],
    CAST(100.0 * SUM(CASE WHEN t.CustomerOrderId IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) [Pct_upgrade],
    CAST(AVG(CAST(o.GOODS_RECEIVED_duration AS FLOAT)) AS DECIMAL(8,1))          [Sr_h_na_towar],
    CAST(100.0 * SUM(CASE WHEN o.Hours_late_shipped > 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) [Pct_po_terminie]
FROM BIData.dbo.OrderFulfilmentInfo2 o (NOLOCK)
LEFT JOIN #t38 t ON t.CustomerOrderId = o.CustomerOrderId
WHERE o.ORDER_CREATED >= @od AND o.ORDER_CREATED < @do
  AND o.GOODS_ORDERED IS NOT NULL
GROUP BY LEFT(ISNULL(o.GOODS_RECEIVED_supplier, o.GOODS_ORDERED_supplier), 22)
HAVING COUNT(*) >= 200
ORDER BY [Pct_upgrade] DESC;
