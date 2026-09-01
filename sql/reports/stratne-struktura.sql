-- CHECK: z czego SKLADA sie miesieczna strata — przeglad struktury, nie lista zamowien
-- @opis Miesięczny rozkład strat na klasy: zwroty, wysyłki zastępcze, świadome wyprzedaże, błędy wyceny, błędy wykonania — żeby wiadomo było, gdzie w ogóle warto szukać.
-- @cisza-gdy-pusto
--
-- PO CO OSOBNO: pojedyncze zamowienie mowi „co sie stalo", struktura mowi „gdzie jest
-- pieniadz". Bez niej latwo miesiacami poprawiac cennik, podczas gdy 60% straty siedzi
-- w zwrotach. Tak wlasnie pomylil sie ten projekt 2026-09-01: pierwsza wersja checku
-- podala „75% strat bylo zaplanowane", bo nie odsiewala zwrotow ani zamowien zerowych.
--
-- ✅ FAKT [2026-09-01] (30 dni, n=1109 stratnych):
--   wysylki zastepcze / reklamacje (wartosc 0)  220 zam.  -18 312 zl  (-83,24/zam.)
--   zwykla sprzedaz                             889 zam.  -11 852 zl  (-13,33/zam.)
-- Czyli JEDNA piata zamowien odpowiada za TRZY piate straty i nie ma zwiazku z cennikiem.
--
-- Raport miesieczny: odzywa sie 1. dnia miesiaca. W pozostale dni zwraca zero wierszy,
-- a @cisza-gdy-pusto usuwa go z wiadomosci.
-- ⚠️ Profit_Actual, NIGDY Profit_ActualFull.

DECLARE dni           INT64 DEFAULT 30;
DECLARE dzien_raportu INT64 DEFAULT 1;   -- 1. dzien miesiaca

WITH s AS (
  SELECT o.CustomerOrderId, o.Profit_Actual, o.Profit_Estimated, o.fOrderTotal,
         EXISTS(SELECT 1 FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` t
                WHERE t.CustomerOrderId = o.CustomerOrderId AND t.TagId = 22) AS zwrot,
         EXISTS(SELECT 1 FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` t
                WHERE t.CustomerOrderId = o.CustomerOrderId AND t.TagId = 33) AS zalegacz
  FROM `polish-bookstores-group.BIData.opi_OrderProfit` o
  WHERE o.OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni DAY)
    AND o.OrderStatusId <> 40 AND o.IsDoneCalculating AND o.Profit_Actual < 0
    AND EXTRACT(DAY FROM CURRENT_DATE()) = dzien_raportu
)
SELECT
  CASE
    WHEN fOrderTotal <= 0 THEN '1. wysylka zastepcza / reklamacja (wartosc 0)'
    WHEN zwrot            THEN '2. zwrot towaru (tag 22)'
    WHEN zalegacz         THEN '3. wyprzedaz zalegacza — strata swiadoma (tag 33)'
    WHEN Profit_Estimated <= 0 THEN '4. BLAD WYCENY — stratne juz w planie'
    ELSE                            '5. blad wykonania — plan byl zyskowny'
  END AS Klasa,
  COUNT(*)                     AS Zamowien,
  ROUND(SUM(Profit_Actual), 0) AS Strata_PLN,
  ROUND(AVG(Profit_Actual), 2) AS Srednia,
  ROUND(100 * SAFE_DIVIDE(SUM(Profit_Actual), SUM(SUM(Profit_Actual)) OVER ()), 1) AS Proc_straty
FROM s
GROUP BY Klasa
ORDER BY Klasa;
