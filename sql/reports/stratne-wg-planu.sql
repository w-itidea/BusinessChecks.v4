-- CHECK: straty ZAPLANOWANE — oferta byla stratna juz w chwili zamowienia
-- @opis Zamówienia, które zrealizowały się zgodnie z planem, a mimo to przyniosły stratę — czyli źle wyceniona oferta, nie wpadka wykonania.
-- @cisza-gdy-pusto
--
-- ⭐ KRYTERIUM ARTURA (Slack, 2026-08-28): „Jesli zamowienie zrealizowalo sie tak jak
-- PriceOfferToCustomerOrder / PriceOffer.Json zakladalo, a nadal bylo stratne, to jest to
-- konkretna klasa problemu i wymaga wyjasnienia — takie zamowienia chcemy dostawac."
--
-- 🔴 PO CO OSOBNY CHECK, skoro jest stratne-daily:
-- stratne-daily miesza dwie rzeczy o ROZNYCH WLASCICIELACH i roznym lekarstwie:
--   • zla WYCENA  — sprzedalismy dokladnie tak, jak policzylismy, i to bylo stratne
--   • zle WYKONANIE — plan byl zyskowny, ale wysylka/koszt towaru go zjadly
-- Pierwsze naprawia sie w cenie minimalnej i regulach ofertowych. Drugie w logistyce.
-- Wrzucone do jednej tabeli daja 50 pozycji dziennie, ktorych nikt nie przeglada.
--
-- ✅ FAKT [2026-09-01] (n = 1119 stratnych zamowien / 30 dni, plik stratne_klasy.sql):
--   plan stratny, wykonanie zgodne     354 zam.  -10 071 zl   odchylka od planu -0,13 zl
--   plan stratny, wykonanie gorsze     277 zam.  -12 937 zl   odchylka +3,68 zl
--   plan zyskowny, zjadla realizacja   468 zam.   -7 463 zl   odchylka -26,45 zl
-- Czyli 75% calej straty (-23 008 zl) bylo ZAPLANOWANE. Ten check pokazuje wlasnie te.
--
-- Zrodlo: BIData.opi_OrderProfit — kolumny *_Estimated to stan z chwili zamowienia,
-- bez sufiksu to rzeczywiste rozliczenie. Roznica miedzy nimi = odchylka wykonania.
-- ⚠️ Profit_Actual, NIGDY Profit_ActualFull (ten pomija LineHaulCost dla UK).
--
-- @link Zamowienie https://panel.fkwt.pl/Order3.aspx?OrderId={}

DECLARE dni_wstecz  INT64   DEFAULT 1;
DECLARE tolerancja  NUMERIC DEFAULT 3.0;   -- zl; ponizej = "wykonalo sie zgodnie z planem"
DECLARE prog_straty NUMERIC DEFAULT -5;    -- ponizej tego warto sie zajac; drobnica to szum
DECLARE ile_pokazac INT64   DEFAULT 12;

SELECT
  CustomerOrderId                                        AS Zamowienie,
  IdBookstore                                            AS Rynek,
  COALESCE(ShippingCountryIso2, '??')                    AS Kraj,
  FORMAT_TIMESTAMP('%m-%d %H:%M', OrderCreatedOnUtc)     AS Utworzono,
  NumOfItems                                             AS Szt,
  ROUND(fOrderTotal, 2)                                  AS Wartosc,
  ROUND(Profit_Estimated, 2)                             AS Plan,
  ROUND(Profit_Actual, 2)                                AS Wynik,
  ROUND(Profit_Actual - Profit_Estimated, 2)             AS Odchylka,
  ROUND(ProfitMargin, 1)                                 AS Marza_pct
FROM `polish-bookstores-group.BIData.opi_OrderProfit`
WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
  AND OrderStatusId <> 40
  AND IsDoneCalculating
  AND Profit_Actual < prog_straty
  -- Sedno: plan tez byl stratny, a wykonanie go NIE zepsulo. Wina lezy w wycenie.
  AND Profit_Estimated <= 0
  AND ABS(Profit_Actual - Profit_Estimated) <= tolerancja
-- BigQuery nie przyjmuje zmiennej w LIMIT ("expects an integer literal or parameter"),
-- wiec ograniczamy przez QUALIFY — tak samo jak stratne-daily.
QUALIFY ROW_NUMBER() OVER (ORDER BY Profit_Actual ASC) <= ile_pokazac
ORDER BY Wynik;
