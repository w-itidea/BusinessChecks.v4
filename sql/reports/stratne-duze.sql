-- CHECK: BARDZO DUZE straty z ostatniej doby — codzienna lista do reakcji tego samego dnia.
-- @opis Zamówienia, które wczoraj straciły naprawdę dużo. Krótka lista, każda pozycja warta reakcji.
-- @cisza-gdy-pusto
--
-- ⏱ RYTM DZIENNY (decyzja Wojtka 2026-09-12): „codziennie masz wysylac tylko b. duze straty".
-- Pelna analiza strat przeniesiona na poniedzialek (stratne-daily, okno 8 dni).
-- Tutaj zostaje tylko to, co nie moze poczekac do poniedzialku.
--
-- 🔢 SKAD PROG -100 zl (zmierzone 2026-09-12, 30 dni, scratchpad/prog.sql):
--     prog     zam./dzien   % calej straty
--     -50        11,5           61,0%
--     -75         5,9           41,6%
--    -100         3,4           29,2%   <- wybrane
--    -150         1,1           13,8%
--    -200         0,6            9,0%
-- Przy -100 dostajesz srednio TRZY zamowienia dziennie i lapiesz 29% calej kwoty strat.
-- Nizszy prog (-50) to 11-12 pozycji dziennie — czyli znowu lista, ktora sie przewija
-- bez czytania, a o to wlasnie byla pretensja. Wyzszy (-200) milczy przez wiekszosc dni.
-- Reszta strat NIE ginie: ogon idzie do poniedzialkowego raportu.
--
-- Filtry obowiazkowe: OrderStatusId <> 40 (anulowane), IsDoneCalculating (profit domkniety).
--
-- @link Zamowienie https://panel.fkwt.pl/Order3.aspx?OrderId={}

DECLARE dni_wstecz      INT64   DEFAULT 1;
DECLARE prog_straty     NUMERIC DEFAULT -100;  -- „b. duze straty" — patrz tabelka wyzej
DECLARE prog_istotnosci NUMERIC DEFAULT -100;  -- rowny progowi: nie przepuszczamy drobnicy bez przyczyny
DECLARE ile_pokazac     INT64   DEFAULT 15;

SELECT * FROM (
SELECT
  CustomerOrderId                                        AS Zamowienie,
  IdBookstore                                            AS Rynek,
  CASE ShippingCountryIso2
    WHEN 'DE' THEN 'Niemcy'     WHEN 'FR' THEN 'Francja'    WHEN 'IT' THEN 'Wlochy'
    WHEN 'ES' THEN 'Hiszpania'  WHEN 'NL' THEN 'Holandia'   WHEN 'BE' THEN 'Belgia'
    WHEN 'PL' THEN 'Polska'     WHEN 'SE' THEN 'Szwecja'    WHEN 'AT' THEN 'Austria'
    WHEN 'IE' THEN 'Irlandia'   WHEN 'GB' THEN 'W.Brytania' WHEN 'UK' THEN 'W.Brytania'
    WHEN 'DK' THEN 'Dania'      WHEN 'FI' THEN 'Finlandia'  WHEN 'PT' THEN 'Portugalia'
    WHEN 'LU' THEN 'Luksemburg' WHEN 'CZ' THEN 'Czechy'     WHEN 'MT' THEN 'Malta'
    WHEN 'CY' THEN 'Cypr'       WHEN 'GR' THEN 'Grecja'     WHEN 'HU' THEN 'Wegry'
    WHEN 'RO' THEN 'Rumunia'    WHEN 'SK' THEN 'Slowacja'   WHEN 'SI' THEN 'Slowenia'
    WHEN 'HR' THEN 'Chorwacja'  WHEN 'BG' THEN 'Bulgaria'   WHEN 'EE' THEN 'Estonia'
    WHEN 'LT' THEN 'Litwa'      WHEN 'LV' THEN 'Lotwa'      WHEN 'NO' THEN 'Norwegia'
    WHEN 'CH' THEN 'Szwajcaria'
    ELSE COALESCE(ShippingCountryIso2, '??')
  END                                                    AS Kraj,
  FORMAT_TIMESTAMP('%m-%d %H:%M', OrderCreatedOnUtc)     AS Utworzono,
  NumOfItems                                             AS Szt,
  ROUND(fOrderTotal, 2)                                  AS Wartosc,
  ROUND(Profit_Actual, 2)                                AS Strata,
  ROUND(ProfitMargin, 1)                                 AS Marza_pct,
  CASE
    WHEN fOrderTotal < ProductCost                                     THEN 'sprzedaz ponizej kosztu towaru'
    WHEN ShippingCost > (fOrderTotal - ProductCost)                    THEN 'wysylka zjada marze'
    WHEN SAFE_DIVIDE(MarketplaceCost, NULLIF(fOrderTotal, 0)) > 0.25   THEN 'koszty marketplace > 25%'
    WHEN SAFE_DIVIDE(PaymentCost, NULLIF(fOrderTotal, 0)) > 0.10       THEN 'koszty platnosci > 10%'
    ELSE 'inne / zlozone'
  END                                                    AS Przyczyna
FROM `polish-bookstores-group.BIData.opi_OrderProfit`
WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
  AND OrderStatusId <> 40
  AND IsDoneCalculating
  AND Profit_Actual < prog_straty
)
WHERE Przyczyna <> 'inne / zlozone' OR Strata <= prog_istotnosci
-- BigQuery nie przyjmuje zmiennej w LIMIT ("expects an integer literal or parameter"),
-- wiec ograniczenie robimy przez QUALIFY — parametr zostaje sterowalny.
QUALIFY ROW_NUMBER() OVER (ORDER BY Strata ASC) <= ile_pokazac
ORDER BY Strata ASC
