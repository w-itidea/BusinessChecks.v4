-- ⚠️ TRYB EKSPLORACJI: sierpien 2026 (miesiac zamkniety), porownanie upgrade vs baza
-- Pytanie: czy upgrade wysylki bierze sie z tego, ze dostawca nie dowiozl na czas
DECLARE @od DATE = '2026-08-01', @do DATE = '2026-09-01';

IF OBJECT_ID('tempdb..#t38') IS NOT NULL DROP TABLE #t38;
SELECT DISTINCT CustomerOrderId INTO #t38
FROM BIData.opi.OrderProfitTag (NOLOCK) WHERE TagId = 38;

-- 1) sourcing: czy zamowienia z upgrade'em w ogole wymagaly zamowienia towaru
SELECT
    CASE WHEN t.CustomerOrderId IS NOT NULL THEN 'UPGRADE' ELSE 'BAZA' END          [Grupa],
    COUNT(*)                                                                        [Zamowien],
    CAST(100.0 * SUM(CASE WHEN o.GOODS_ORDERED IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) [Pct_wymagalo_zakupu],
    CAST(AVG(CAST(o.GOODS_RECEIVED_duration AS FLOAT)) AS DECIMAL(8,1))             [Sr_h_czekania_na_towar],
    CAST(AVG(CAST(o.PACKING_duration AS FLOAT)) AS DECIMAL(8,1))                    [Sr_h_pakowni],
    CAST(AVG(CAST(o.Hours_late_shipped AS FLOAT)) AS DECIMAL(8,1))                  [Sr_h_spoznienia],
    CAST(100.0 * SUM(CASE WHEN o.Hours_late_shipped > 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) [Pct_wyslane_po_terminie],
    CAST(100.0 * SUM(CASE WHEN o.IsReceivedOnTime = 0 THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN o.IsReceivedOnTime IS NOT NULL THEN 1 ELSE 0 END),0) AS DECIMAL(5,1)) [Pct_dostawa_po_terminie]
FROM BIData.dbo.OrderFulfilmentInfo2 o (NOLOCK)
LEFT JOIN #t38 t ON t.CustomerOrderId = o.CustomerOrderId
WHERE o.ORDER_CREATED >= @od AND o.ORDER_CREATED < @do
GROUP BY CASE WHEN t.CustomerOrderId IS NOT NULL THEN 'UPGRADE' ELSE 'BAZA' END;

-- 2) skad bierze sie termin (co realnie zmienilo sie w sierpniu)
SELECT FORMAT(o.ORDER_CREATED,'yyyy-MM') [Miesiac], ISNULL(o.ShipDeadlineSource,'(brak)') [Zrodlo_terminu],
       COUNT(*) [Zamowien],
       SUM(CASE WHEN t.CustomerOrderId IS NOT NULL THEN 1 ELSE 0 END) [Z_upgrade]
FROM BIData.dbo.OrderFulfilmentInfo2 o (NOLOCK)
LEFT JOIN #t38 t ON t.CustomerOrderId = o.CustomerOrderId
WHERE o.ORDER_CREATED >= '2026-07-01' AND o.ORDER_CREATED < @do
GROUP BY FORMAT(o.ORDER_CREATED,'yyyy-MM'), ISNULL(o.ShipDeadlineSource,'(brak)')
ORDER BY 1, 3 DESC;
