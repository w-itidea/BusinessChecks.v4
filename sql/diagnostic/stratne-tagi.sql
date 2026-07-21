-- DIAGNOSTYKA: jakie tagi systemowe wisza na stratnych zamowieniach (tydzien)?
--
-- OrderProfitTag to tabela, w ktorej systemy same zapisuja CO poszlo nie tak. Sprawdzamy,
-- ktore tagi wspolwystepuja ze strata i ile ta strata wynosi — to jest most miedzy
-- "kubelkiem" (rodzaj) a "przyczyna" (konkret).

DECLARE dni_wstecz INT64 DEFAULT 7;

WITH stratne AS (
  SELECT CustomerOrderId, Profit_Actual, IdBookstore
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND OrderStatusId <> 40
    AND IsDoneCalculating
    AND Profit_Actual < 0
)
SELECT
  t.TagId                                          AS Tag,
  COUNT(DISTINCT s.CustomerOrderId)                AS Stratnych_zamowien,
  ROUND(SUM(DISTINCT_LOSS), 2)                     AS Strata_PLN,
  ANY_VALUE(SUBSTR(t.Note, 1, 90))                 AS Przyklad_opisu,
  ANY_VALUE(t.Source)                              AS Zrodlo
FROM stratne s
JOIN `polish-bookstores-group.BIData.opi_OrderProfitTag` t
     ON t.CustomerOrderId = s.CustomerOrderId
JOIN UNNEST([s.Profit_Actual]) AS DISTINCT_LOSS
GROUP BY t.TagId
ORDER BY Stratnych_zamowien DESC
