-- Roznice estymacji vs rzeczywistych kosztow wysylki
-- Podmien: [DAYS] = liczba dni wstecz (domyslnie 7)
SELECT TOP 20
    sc.CustomerOrderId,
    CAST(sc.ShippingCostTotal_EstimatedPreShipments AS DECIMAL(10,2)) AS Estymacja,
    CAST(sc.fShippingCostTotal AS DECIMAL(10,2)) AS Rzeczywisty,
    CAST(sc.fShippingCostTotal - sc.ShippingCostTotal_EstimatedPreShipments AS DECIMAL(10,2)) AS Roznica,
    CAST(
        (sc.fShippingCostTotal - sc.ShippingCostTotal_EstimatedPreShipments)
        / NULLIF(sc.ShippingCostTotal_EstimatedPreShipments, 0) * 100
    AS DECIMAL(5,1)) AS ProcentRoznicy,
    CAST(op.Profit_ActualFull AS DECIMAL(10,2)) AS Profit
FROM BIData.opi.ShippingCost sc (NOLOCK)
JOIN BIData.opi.OrderProfit op (NOLOCK) ON sc.CustomerOrderId = op.CustomerOrderId
WHERE op.OrderCreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
    AND op.OrderStatusId <> 40
    AND sc.ShippingCostTotal_EstimatedPreShipments > 0
    AND ABS(sc.fShippingCostTotal - sc.ShippingCostTotal_EstimatedPreShipments)
        / NULLIF(sc.ShippingCostTotal_EstimatedPreShipments, 0) > 0.50
ORDER BY ABS(sc.fShippingCostTotal - sc.ShippingCostTotal_EstimatedPreShipments) DESC;
