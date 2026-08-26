-- Analiza kosztow marketplace vs norma
-- Podmien: [DAYS] = liczba dni wstecz (domyslnie 7)
SELECT TOP 20
    op.CustomerOrderId,
    op.IdBookstore AS Marketplace,
    CAST(op.fOrderTotal AS DECIMAL(10,2)) AS WartoscZamowienia,
    CAST(mc.fMarketplaceCost AS DECIMAL(10,2)) AS KosztyMarketplace,
    CAST(mc.fMarketplaceCost / NULLIF(op.fOrderTotal, 0) * 100 AS DECIMAL(5,1)) AS ProcentMarketplace,
    CAST(mc.ReferralFee_Actual AS DECIMAL(10,2)) AS ReferralFee,
    CAST(mc.ClosingFees_Actual AS DECIMAL(10,2)) AS ClosingFee,
    CAST(op.Profit_Actual AS DECIMAL(10,2)) AS Profit,
    CASE
        WHEN mc.fMarketplaceCost / NULLIF(op.fOrderTotal, 0) > 0.20 THEN 'KRYTYCZNE >20%'
        WHEN mc.fMarketplaceCost / NULLIF(op.fOrderTotal, 0) > 0.17 THEN 'PODWYZSZONE 17-20%'
        ELSE 'NORMALNE'
    END AS Ocena
FROM BIData.opi.OrderProfit op (NOLOCK)
JOIN BIData.opi.MarketplaceCost mc (NOLOCK) ON op.CustomerOrderId = mc.CustomerOrderId
WHERE op.OrderCreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
    AND op.OrderStatusId <> 40
    AND mc.fMarketplaceCost / NULLIF(op.fOrderTotal, 0) > 0.17
ORDER BY mc.fMarketplaceCost / NULLIF(op.fOrderTotal, 0) DESC;
