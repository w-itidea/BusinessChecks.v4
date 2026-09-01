-- CHECK: wysylki zastepcze i reklamacje — najwieksza pojedyncza pozycja strat
-- @opis Zamówienia o zerowej wartości, czyli pełny koszt bez przychodu — kto, dokąd i za ile wysyłamy powtórnie. Przegląd tygodniowy.
-- @cisza-gdy-pusto
--
-- 🔴 TU SIEDZI PIENIADZ. ✅ FAKT [2026-09-01] (30 dni, stratne-struktura):
--   wysylki zastepcze / reklamacje  220 zam.  -18 312 zl  = 60,7% CALEJ straty
--   blad wykonania                  453 zam.   -7 155 zl  = 23,7%
--   blad wyceny                     334 zam.   -3 276 zl  = 10,9%
-- Jedna piata stratnych zamowien odpowiada za trzy piate straty — i nie ma to nic wspolnego
-- ani z cennikiem, ani z logistyka. To jakosc, opisy i zwroty. W skali roku ~220 000 zl.
--
-- ⚠️ To NIE sa anulowane zamowienia (te odsiewa OrderStatusId <> 40). To realnie wyslany
-- towar, za ktory nikt nie zaplacil — powtorka po zagubieniu, uszkodzeniu albo reklamacji.
-- ⚠️ OrderProfit NIE lapie recznych refundow bankowych z KSI_RefundRequest — realna kwota
--    jest WYZSZA niz ta ponizej.
--
-- Grupujemy po rynku i kraju, bo pojedyncza wysylka zastepcza to zdarzenie, a ich SKUPISKO
-- w jednym kierunku to sygnal (zly przewoznik, zle pakowanie, zly opis produktu).
-- Raport tygodniowy — w pozostale dni cisza.
-- ⚠️ Profit_Actual, NIGDY Profit_ActualFull.

DECLARE dni           INT64 DEFAULT 7;
DECLARE dzien_raportu INT64 DEFAULT 2;   -- 1=niedziela, 2=poniedzialek

SELECT
  IdBookstore                                 AS Rynek,
  COALESCE(ShippingCountryIso2, '??')         AS Kraj,
  COUNT(*)                                    AS Wysylek,
  ROUND(SUM(Profit_Actual), 0)                AS Koszt_PLN,
  ROUND(AVG(Profit_Actual), 2)                AS Sr_koszt,
  ROUND(AVG(ShippingCost), 2)                 AS Sr_wysylka,
  ROUND(AVG(ProductCost), 2)                  AS Sr_towar
FROM `polish-bookstores-group.BIData.opi_OrderProfit`
WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni DAY)
  AND OrderStatusId <> 40
  AND IsDoneCalculating
  AND Profit_Actual < 0
  AND fOrderTotal <= 0                        -- pelny koszt, zero przychodu
  AND EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = dzien_raportu
GROUP BY Rynek, Kraj
HAVING Wysylek >= 2
ORDER BY Koszt_PLN;
