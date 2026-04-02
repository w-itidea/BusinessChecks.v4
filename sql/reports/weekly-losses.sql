-- Stratne zamowienia z ostatnich N dni
-- Podmien: [DAYS] = liczba dni wstecz (domyslnie 7)
SELECT TOP 15
    op.CustomerOrderId,
    op.IdBookstore AS Marketplace,
    CAST(op.OrderCreatedOnUtc AS DATE) AS DataZamowienia,
    CAST(op.Profit_ActualFull AS DECIMAL(10,2)) AS Profit,
    CAST(op.fOrderTotal AS DECIMAL(10,2)) AS WartoscZamowienia,
    CAST(ABS(op.Profit_ActualFull) / NULLIF(op.fOrderTotal, 0) * 100 AS DECIMAL(5,1)) AS ProcentStraty,
    CASE
        WHEN EXISTS(
            SELECT 1 FROM BIData.opi.OrderProfitTag opt
            WHERE opt.CustomerOrderId = op.CustomerOrderId
        ) THEN 'MA_TAGI'
        ELSE 'BRAK'
    END AS Tagi
FROM BIData.opi.OrderProfit op (NOLOCK)
WHERE op.OrderCreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
    AND op.OrderStatusId <> 40
    AND op.Profit_ActualFull < 0
ORDER BY op.Profit_ActualFull ASC;
