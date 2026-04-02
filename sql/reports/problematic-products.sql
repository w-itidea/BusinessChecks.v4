-- Produkty z powtarzajacymi sie stratami (min 3 wystapienia)
-- Podmien: [DAYS] = liczba dni wstecz (domyslnie 30)
SELECT
    oip.EAN,
    COUNT(*) AS LiczbaStrat,
    CAST(AVG(oip.ItemProfit) AS DECIMAL(8,2)) AS SredniaStrata,
    CAST(SUM(oip.ItemProfit) AS DECIMAL(10,2)) AS SumaStrat,
    CAST(AVG(oip.UnitSalesPriceNet) AS DECIMAL(8,2)) AS SrCenaSprzedazy,
    CAST(AVG(oip.UnitPurchasePriceNet) AS DECIMAL(8,2)) AS SrCenaZakupu,
    (SELECT TOP 1
        CASE
            WHEN o2.UnitPurchasePriceNet >= o2.UnitSalesPriceNet THEN 'CENA_ZAKUPU_ZA_WYSOKA'
            WHEN o2.OrderCostMinusShippingChargeForUnit > (o2.UnitSalesPriceNet - o2.UnitPurchasePriceNet) THEN 'KOSZTY_POSREDNIE'
            WHEN o2.ShippingChargePlnNettoForUnit > (o2.UnitSalesPriceNet - o2.UnitPurchasePriceNet) THEN 'KOSZTY_WYSYLKI'
            ELSE 'INNE'
        END
     FROM BIData.opi.OrderItemProfit o2 (NOLOCK)
     JOIN BIData.opi.OrderProfit op2 (NOLOCK) ON o2.CustomerOrderId = op2.CustomerOrderId
     WHERE o2.EAN = oip.EAN
       AND op2.OrderCreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
       AND op2.OrderStatusId <> 40
       AND o2.ItemProfit < 0
     ORDER BY o2.LastUpdateOnUtc DESC
    ) AS GlownaPrzyczyna
FROM BIData.opi.OrderItemProfit oip (NOLOCK)
JOIN BIData.opi.OrderProfit op (NOLOCK) ON oip.CustomerOrderId = op.CustomerOrderId
WHERE op.OrderCreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
    AND op.OrderStatusId <> 40
    AND oip.ItemProfit < 0
GROUP BY oip.EAN
HAVING COUNT(*) >= 3
ORDER BY SUM(oip.ItemProfit) ASC;
