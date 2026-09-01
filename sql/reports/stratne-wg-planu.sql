-- CHECK: bledy w WYCENIE — zamowienia stratne juz w planie, bez zwrotu i bez wyprzedazy
-- @opis Zamówienia, które wyceniliśmy na stratę i taką stratą się skończyły — po odsianiu zwrotów i świadomych wyprzedaży. Każde ma wskazaną przyczynę.
-- @cisza-gdy-pusto
--
-- ⭐ KRYTERIUM ARTURA (Slack 2026-08-28): „Jesli zamowienie zrealizowalo sie tak jak
-- PriceOffer zakladal, a nadal bylo stratne, to konkretna klasa problemu i wymaga wyjasnienia."
-- ⭐ UZUPELNIENIE WOJTKA (2026-09-01): „w planie tez sa bledy i masz je wylapywac (...)
-- szukaj przyczyn (...) sa tez tagi np. wyprzedaz zalegacza to strata planowana. patrz na tagi."
--
-- 🔴 DLACZEGO TAGI SA TU KONIECZNE — inaczej check klamie:
-- ✅ FAKT [2026-09-01] (n=631 zamowien z Profit_Estimated<=0 / 30 dni, stratne_zwroty_kontrola.sql):
--   tag 22 ZWROT            227 zam.  -18 499 zl   przychod nizszy od planu o 122,71 zl
--   tag 33 wyprzedaz zalegacza 63 zam.   -921 zl   strata SWIADOMA, nie blad
--   bez tych tagow          335 zam.   -3 277 zl   <- DOPIERO TO jest blad wyceny
-- Bez odsiania tagow „strata zaplanowana" wychodzi -23 008 zl i w 80% sa to zwroty,
-- czyli zupelnie inny problem (jakosc/opisy), z innym wlascicielem. Pierwsza wersja tego
-- checku tego nie odsiewala i podawala zawyzona liczbe siedmiokrotnie.
--
-- ✅ FAKT [2026-09-01] przyczyny wewnatrz tych 335 (stratne_przyczyny_planu.sql):
--   cena ponizej kosztu towaru       8 zam.  -318 zl  (-39,73/zam.)  <- nie ma prawa sie zdarzyc
--   wysylka drozsza niz cala marza  27 zam.  -759 zl  (-28,10/zam.)
--   prowizja marketplace > 25%       7 zam.   -38 zl
--   suma drobnych                  293 zam. -2 163 zl  (-7,38/zam.)  <- ogon, do wzorcow tygodniowych
-- Ten check pokazuje TRZY pierwsze grupy — konkretna przyczyna i konkretna kwota.
-- Ogon idzie do stratne-wzorce (tygodniowo), bo pojedynczo nie da sie z nim nic zrobic.
--
-- ⚠️ Profit_Actual, NIGDY Profit_ActualFull (ten pomija LineHaulCost dla UK).
-- ⚠️ OrderProfit NIE lapie recznych refundow bankowych z KSI_RefundRequest — realna strata
--    ze zwrotow jest WYZSZA niz to, co widac w tagu 22.
--
-- @link Zamowienie https://panel.fkwt.pl/Order3.aspx?OrderId={}

DECLARE dni_wstecz  INT64   DEFAULT 1;
DECLARE tolerancja  NUMERIC DEFAULT 3.0;  -- zl; ponizej = wykonanie zgodne z planem
DECLARE ile_pokazac INT64   DEFAULT 12;

WITH stratne AS (
  SELECT o.*,
    CASE
      WHEN o.fOrderTotal < o.ProductCost                                      THEN '1. cena < koszt towaru'
      WHEN o.ShippingCost > (o.fOrderTotal - o.ProductCost)                   THEN '2. wysylka > cala marza'
      WHEN SAFE_DIVIDE(o.MarketplaceCost, NULLIF(o.fOrderTotal,0)) > 0.25     THEN '3. prowizja > 25%'
      WHEN SAFE_DIVIDE(o.PaymentCost, NULLIF(o.fOrderTotal,0)) > 0.10         THEN '4. platnosci > 10%'
      ELSE                                                                         '5. suma drobnych'
    END AS Przyczyna,
    -- Tagi pomocnicze: co system sam zauwazyl przy tym zamowieniu.
    -- 24=zle wymiary, 10=towar drozszy niz szacowano, 1=wysylka drozsza, 17=zly kierunek,
    -- 21=rabat, 35=WarehouseRequest do dostawcy, 13=koszt towaru zerowy.
    (SELECT STRING_AGG(DISTINCT CAST(t.TagId AS STRING) ORDER BY CAST(t.TagId AS STRING))
     FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` t
     WHERE t.CustomerOrderId = o.CustomerOrderId
       AND t.TagId IN (1, 10, 13, 16, 17, 21, 24, 35, 37, 38)) AS Tagi
  FROM `polish-bookstores-group.BIData.opi_OrderProfit` o
  WHERE o.OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND o.OrderStatusId <> 40
    AND o.IsDoneCalculating
    AND o.Profit_Actual < 0
    -- ⚠️ Zamowienia o ZEROWEJ wartosci to wysylki zastepcze i reklamacje — pelny koszt bez
    -- przychodu. Zawsze spelniaja „cena < koszt towaru", wiec bez tego filtra zalewaja liste
    -- falszywymi bledami wyceny. ✅ FAKT [2026-09-01]: 220 zam. / -18 312 zl / 30 dni
    -- (stratne_zerowe.sql) — to 60% calej straty i ZUPELNIE inny problem: jakosc i zwroty.
    AND o.fOrderTotal > 0
    AND o.Profit_Estimated <= 0                                    -- strate bylo widac w planie
    AND ABS(o.Profit_Actual - o.Profit_Estimated) <= tolerancja     -- wykonanie planu nie zepsulo
    -- ⚠️ ODSIEW: zwrot to nie blad wyceny, wyprzedaz zalegacza to strata swiadoma.
    AND NOT EXISTS (SELECT 1 FROM `polish-bookstores-group.BIData.opi_OrderProfitTag` t
                    WHERE t.CustomerOrderId = o.CustomerOrderId AND t.TagId IN (22, 33))
)
SELECT
  CustomerOrderId                                    AS Zamowienie,
  Przyczyna,
  IFNULL(Tagi, '—')                                  AS Tagi,
  IdBookstore                                        AS Rynek,
  COALESCE(ShippingCountryIso2, '??')                AS Kraj,
  ROUND(fOrderTotal, 2)                              AS Wartosc,
  ROUND(ProductCost, 2)                              AS Towar,
  ROUND(ShippingCost, 2)                             AS Wysylka,
  ROUND(Profit_Actual, 2)                            AS Strata
FROM stratne
WHERE Przyczyna <> '5. suma drobnych'    -- ogon idzie do wzorcow tygodniowych
QUALIFY ROW_NUMBER() OVER (ORDER BY Profit_Actual ASC) <= ile_pokazac
ORDER BY Strata;
