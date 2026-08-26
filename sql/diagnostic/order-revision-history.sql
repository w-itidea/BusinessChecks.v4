-- Historia zmian profitu zamowienia
-- Podmien: [ID] = CustomerOrderId
--
-- UWAGA (2026-08-26): dwie poprawki wzgledem poprzedniej wersji, obie zweryfikowane na produkcji:
--  1) Profit_ActualFull w tabeli rewizji jest NULL w 100% (0 z 2 519 127 wierszy). Uzywamy Profit_Actual.
--  2) CreatedOnUtc NIE porzadkuje rewizji — srednio 1,00 roznych wartosci na 6,87 rewizji.
--     Kolumna porzadkujaca to DeletedOnUtc (6,87 roznych).
SELECT
    opr.DeletedOnUtc AS DataZmiany,
    CAST(opr.Profit_Actual AS DECIMAL(10,2)) AS Profit,
    CAST(
        opr.Profit_Actual - LAG(opr.Profit_Actual) OVER (ORDER BY opr.DeletedOnUtc)
    AS DECIMAL(10,2)) AS ZmianaProfit,
    opr.Notes AS Uwagi
FROM BIData.opi.OrderProfit_Revision opr (NOLOCK)
WHERE opr.CustomerOrderId = [ID]
ORDER BY opr.DeletedOnUtc DESC;
