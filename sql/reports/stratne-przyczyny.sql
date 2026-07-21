-- CHECK: PRZYCZYNY strat — nie "co sie stalo", tylko "dlaczego".
--
-- Kubel z stratne-daily mowi RODZAJ ("wysylka zjada marze"). Ten check mowi POWOD,
-- bo laczy strate z tagami, ktore systemy same zapisuja w opi_OrderProfitTag:
--   1  = rozjazd kosztu wysylki (rzeczywisty vs estymowany)
--   10/13/16 = rozjazd kosztu towaru (cena zakupu wyzsza niz w wycenie)
--   17 = kierunek (np. AZ-DE -> CH)
--   21 = discount
--   24 = wymiary produktu zgadywane (!) — wycena wysylki na zmyslonych wymiarach
--   33 = towar kupiony >365 dni przed sprzedaza (zalegacz)
--   34 = DispatchDate juz przekroczony
--   35 = WarehouseRequest do konkretnego dostawcy
--   40 = stock z awaryjnego przyjecia (SupplierOrder bez faktury -> koszt nieznany przy wycenie)
--   43 = wymuszona zmiana metody wysylki (np. Prime->Paket, dwukrotnosc wyceny)
--
-- Grupujemy po tagu, bo pytanie brzmi "ktory mechanizm kosztuje nas najwiecej", a nie
-- "ktore zamowienie bylo wczoraj najgorsze".

DECLARE dni_wstecz INT64 DEFAULT 7;

WITH stratne AS (
  SELECT CustomerOrderId, Profit_Actual, IdBookstore
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND OrderStatusId <> 40
    AND IsDoneCalculating
    AND Profit_Actual < 0
),
-- jeden wiersz na (zamowienie, tag) — inaczej wielokrotne tagi tego samego typu
-- zawyzalyby zarowno liczbe zamowien, jak i sume strat
pary AS (
  SELECT DISTINCT s.CustomerOrderId, s.Profit_Actual, s.IdBookstore, t.TagId,
         FIRST_VALUE(t.Note) OVER (PARTITION BY s.CustomerOrderId, t.TagId
                                   ORDER BY t.CreatedOnUtc DESC) AS Note
  FROM stratne s
  JOIN `polish-bookstores-group.BIData.opi_OrderProfitTag` t
       ON t.CustomerOrderId = s.CustomerOrderId
)
SELECT
  TagId                                              AS Tag,
  COUNT(DISTINCT CustomerOrderId)                    AS Zamowien,
  ROUND(SUM(Profit_Actual), 2)                       AS Strata_PLN,
  ROUND(AVG(Profit_Actual), 2)                       AS Sr_strata,
  STRING_AGG(DISTINCT IdBookstore ORDER BY IdBookstore LIMIT 4) AS Rynki,
  SUBSTR(ANY_VALUE(Note), 1, 80)                     AS Przyklad
FROM pary
GROUP BY TagId
HAVING Zamowien >= 3          -- pojedyncze przypadki to szum, nie mechanizm
ORDER BY Strata_PLN ASC
