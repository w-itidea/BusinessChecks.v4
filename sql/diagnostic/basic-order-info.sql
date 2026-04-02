-- Podstawowe informacje o zamowieniu
-- Podmien: [ID] = CustomerOrderId
SELECT
    op.CustomerOrderId,
    op.IdBookstore AS Marketplace,
    CAST(op.OrderCreatedOnUtc AS DATE) AS DataZamowienia,
    CAST(op.Profit_ActualFull AS DECIMAL(10,2)) AS Profit,
    CAST(op.fOrderTotal AS DECIMAL(10,2)) AS WartoscZamowienia,
    CAST(ABS(op.Profit_ActualFull) / NULLIF(op.fOrderTotal, 0) * 100 AS DECIMAL(5,1)) AS ProcentStraty,
    op.OrderStatusId,
    op.LastUpdatedOnUtc
FROM BIData.opi.OrderProfit op (NOLOCK)
WHERE op.CustomerOrderId = [ID]
    AND op.OrderStatusId <> 40;
