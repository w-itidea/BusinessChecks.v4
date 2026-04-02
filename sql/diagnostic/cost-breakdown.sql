-- Rozklad kosztow zamowienia
-- Podmien: [ID] = CustomerOrderId
SELECT
    op.CustomerOrderId,
    CAST(op.fOrderTotal AS DECIMAL(10,2)) AS Przychody,
    CAST(op.Profit_ActualFull AS DECIMAL(10,2)) AS Profit,
    CAST(ISNULL(sc.fShippingCostTotal, 0) AS DECIMAL(10,2)) AS KosztyWysylki,
    CAST(ISNULL(pc.fPaymentCost, 0) AS DECIMAL(10,2)) AS KosztyPlatnosci,
    CAST(ISNULL(mc.fMarketplaceCost, 0) AS DECIMAL(10,2)) AS KosztyMarketplace,
    CAST(op.HandlingCost + op.PackagingCost AS DECIMAL(10,2)) AS KosztyObslugi,
    CAST(
        ISNULL(sc.fShippingCostTotal, 0)
        + ISNULL(pc.fPaymentCost, 0)
        + ISNULL(mc.fMarketplaceCost, 0)
        + op.HandlingCost
        + op.PackagingCost
    AS DECIMAL(10,2)) AS SumaKosztowPosrednich
FROM BIData.opi.OrderProfit op (NOLOCK)
LEFT JOIN BIData.opi.ShippingCost sc (NOLOCK) ON op.CustomerOrderId = sc.CustomerOrderId
LEFT JOIN BIData.opi.PaymentCost pc (NOLOCK) ON op.CustomerOrderId = pc.CustomerOrderId
LEFT JOIN BIData.opi.MarketplaceCost mc (NOLOCK) ON op.CustomerOrderId = mc.CustomerOrderId
WHERE op.CustomerOrderId = [ID];
