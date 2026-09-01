-- CHECK: kierunki, ktore systematycznie traca (kraj docelowy, okno kwartalne)
-- @opis Do których krajów wysyłka jest trwale nierentowna — przegląd tygodniowy, nie dzienny.
-- @cisza-gdy-pusto
--
-- PO CO OSOBNO OD stratne-daily:
-- pojedyncze stratne zamowienie to zdarzenie; stratny KIERUNEK to decyzja handlowa.
-- Widac go dopiero na duzej probce i nie zmienia sie z dnia na dzien — dlatego okno 90 dni
-- i przeglad RAZ W TYGODNIU. Codzienne powtarzanie tej samej listy krajow to szum.
--
-- ✅ FAKT [2026-09-01] (90 dni, kraje z >=20 zamowieniami, plik stratne_kierunki.sql):
--   BR  42 zam.  45,2% stratnych  -1 767 zl  (-42,08 zl/zam.)  18 z 19 strat ZAPLANOWANYCH
--   CY  81 zam.  64,2% stratnych    -546 zl   (-6,74 zl/zam.)  44 z 52 strat ZAPLANOWANYCH
--   MT 120 zam.  45,0% stratnych    -340 zl   (-2,84 zl/zam.)  47 z 54 strat ZAPLANOWANYCH
-- Tylko te trzy kierunki wychodza na minus. W kazdym strata jest w wiekszosci ZAPLANOWANA,
-- czyli cena dla tego kierunku nie pokrywa wysylki — to problem cennika, nie logistyki.
-- Brazylia sama w sobie to ok. 7 000 zl rocznie.
--
-- ⚠️ Profit_Actual, NIGDY Profit_ActualFull (ten pomija LineHaulCost dla UK).

DECLARE dni           INT64 DEFAULT 90;
DECLARE min_zamowien  INT64 DEFAULT 20;   -- ponizej tego jeden pech wyglada jak trend
DECLARE dzien_raportu INT64 DEFAULT 2;    -- 1=niedziela ... 2=poniedzialek

SELECT
  COALESCE(ShippingCountryIso2, '??')                              AS Kraj,
  COUNT(*)                                                         AS Zamowien,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(Profit_Actual < 0), COUNT(*)),1) AS Proc_stratnych,
  ROUND(SUM(Profit_Actual), 0)                                     AS Wynik_PLN,
  ROUND(AVG(Profit_Actual), 2)                                     AS Sr_na_zam,
  -- Ile strat bylo widac juz na wejsciu. Wysoki udzial = poprawiamy CENNIK, nie logistyke.
  COUNTIF(Profit_Actual < 0 AND Profit_Estimated <= 0)             AS Zaplanowanych,
  COUNTIF(Profit_Actual < 0)                                       AS Stratnych
FROM `polish-bookstores-group.BIData.opi_OrderProfit`
WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni DAY)
  AND OrderStatusId <> 40
  AND IsDoneCalculating
  -- Raz w tygodniu. Check jest w codziennym jobie, ale odzywa sie tylko w poniedzialek;
  -- w pozostale dni zwraca zero wierszy i @cisza-gdy-pusto usuwa go z wiadomosci.
  AND EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = dzien_raportu
GROUP BY Kraj
HAVING Zamowien >= min_zamowien AND Wynik_PLN < 0
ORDER BY Wynik_PLN;
