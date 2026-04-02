-- Tagi problemow zamowienia
-- Podmien: [ID] = CustomerOrderId
SELECT
    opt.Source AS Zrodlo,
    opt.Description AS Opis,
    opt.CreatedOnUtc AS Data
FROM BIData.opi.OrderProfitTag opt (NOLOCK)
WHERE opt.CustomerOrderId = [ID]
ORDER BY opt.CreatedOnUtc DESC;
