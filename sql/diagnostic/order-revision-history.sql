-- Historia zmian profitu zamowienia
-- Podmien: [ID] = CustomerOrderId
SELECT
    opr.CreatedOnUtc AS DataZmiany,
    CAST(opr.Profit_ActualFull AS DECIMAL(10,2)) AS Profit,
    CAST(
        opr.Profit_ActualFull - LAG(opr.Profit_ActualFull) OVER (ORDER BY opr.CreatedOnUtc)
    AS DECIMAL(10,2)) AS ZmianaProfit,
    opr.Notes AS Uwagi
FROM BIData.opi.OrderProfit_Revision opr (NOLOCK)
WHERE opr.CustomerOrderId = [ID]
ORDER BY opr.CreatedOnUtc DESC;
