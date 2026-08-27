-- CHECK: pilot BOL buy-box — czy odzyskujemy Buy Box i czy forced cena dociera do oferty.
-- @opis Czy pilot repricingu na BOL trzyma buy-box, czy cena dociera do oferty i czy z tego realnie coś się sprzedaje.
-- Zastepuje pierwsza czesc ~/.claude/cron/bol_buybox_slack.sh (bol_quickwin_KONTROLA.sql).
--
-- Baza wyjsciowa pilota (2026-06-29): wszystkie EAN-y mialy konkurenta na FBR, my drozsi, bez BB.
-- Mierzymy dwie rzeczy naraz:
--   1. WYNIK   — ile Buy Boxow jest teraz nasze
--   2. PROPAGACJA — czy forced cena z ustawien faktycznie weszla do PriceOffer i do zywej oferty BOL
--      (bez tego "nie odzyskalismy BB" moze znaczyc po prostu "cena nigdzie nie doszla")
--
-- REGION (2026-08-26): dane BOL przeniesione przez Szymona do `itideatestproject.bol_ew3`
-- @ europe-west3 — ten sam region co BIData, wiec joinuja sie natywnie. Czytamy widok
-- `BolBuyBox_current` (najswiezszy snapshot per EAN, ~112 tys.) — odpowiednik dawnego mirrora
-- `BIData.mka_BolBuyBox`, ktory zostal wycofany. Historia dzienna dostepna w bazowej tabeli
-- `bol_ew3.BolBuyBox`, gdyby check mial kiedys liczyc trend.

DECLARE nasz      STRING  DEFAULT '1834699';
DECLARE grupa     STRING  DEFAULT 'MS_repriceing_BolBuyBox20260629';
DECLARE krok      NUMERIC DEFAULT 0.02;   -- o tyle schodzimy ponizej konkurenta przy re-undercut

-- KOHORTA: tylko pozycje, ktore realnie mamy czym wystawic.
-- 134 z 523 EAN-ow pilota (25,6%) jest zablokowanych na BOL od 2026-03-02 regula
-- "Blokada zabawek na BOL" — procka daje im Quantity = 0, wiec nigdy nie trafily
-- na rynek. Liczone w mianowniku zanizaly wynik pilota: 100/485 = 20,6% zamiast
-- 100/368 = 27,2%. Zweryfikowane 2026-08-27 na bol_ew3.competing_offers: 133 z nich
-- ANI RAZU nie pojawily sie w drabinie od startu pilota 29.06.
-- Regula ogolna: okazja w drabinie konkurencji nie jest dowodem, ze mamy tam oferte.
WITH pilot AS (
  SELECT s.OurEan, ROUND(s.Price, 2) AS forced_price
  FROM `polish-bookstores-group.BIData.ofi_AmazonFeedProductSettings` s
  JOIN `polish-bookstores-group.BIData.ofi_PriceOffer` p
    ON p.BookstoreId = s.BookstoreId AND p.OurEan = s.OurEan
  WHERE s.BookstoreId = 'BOL-NL' AND s.TestGroupName = grupa AND s.fIsActive = 1
    AND NOT COALESCE(p.IsBlocked, FALSE) AND p.Quantity > 0
),
-- nasza zywa oferta na BOL: w bol_ew3 moze byc kilka ofert per EAN (rozne kondycje),
-- wiec skladamy do jednej ceny per EAN (najnizsza sprzedawalna) — odpowiednik dawnego
-- "first offer" z BolOffersFirstOffer.
oferta_bol AS (
  SELECT Ean, MIN(BundlePrice) AS cena_w_ofercie_bol
  FROM `itideatestproject.bol_ew3.our_offers_current`
  WHERE MarketplaceId = 'BOL-NL'
  GROUP BY Ean
),
-- SPRZEDAZ pilota (dodane 2026-08-26): sam buy-box nie jest celem, tylko droga.
-- Bez tego check odpowiadal "mamy BB", ale nie "czy z tego cokolwiek wynika".
sprzedaz AS (
  SELECT oip.EAN,
         SUM(oip.Quantity)   AS szt_30d,
         SUM(oip.ItemProfit) AS zysk_30d
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit` oip
  JOIN `polish-bookstores-group.BIData.opi_OrderProfit` op
    ON op.CustomerOrderId = oip.CustomerOrderId
  WHERE op.OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND op.OrderStatusId <> 40          -- anulowane nie liczą się do skutku
    AND op.IdBookstore LIKE 'BOL%'      -- tylko BOL: sprzedaż na innych rynkach nie jest zasługą pilota
  GROUP BY oip.EAN
),
zlaczone AS (
  SELECT
    p.OurEan, p.forced_price,
    bb.RetailerId, bb.FulfilmentMethod, bb.BestOfferPrice, bb.HasOffer, bb.LastCheckedUtc,
    po.Price AS po_price, po.PriceMin AS po_pricemin,
    ob.cena_w_ofercie_bol,
    sp.szt_30d, sp.zysk_30d
  FROM pilot p
  LEFT JOIN `itideatestproject.bol_ew3.BolBuyBox_current` bb
         ON bb.Ean = p.OurEan AND bb.MarketplaceId = 'BOL-NL'
  LEFT JOIN `polish-bookstores-group.BIData.ofi_PriceOffer` po
         ON po.SKU = p.OurEan AND po.BookstoreId = 'BOL-NL'
  LEFT JOIN oferta_bol ob
         ON ob.Ean = p.OurEan
  LEFT JOIN sprzedaz sp
         ON sp.EAN = p.OurEan
)
SELECT
  COUNT(*)                                                          AS Pilot_EAN,
  COUNTIF(RetailerId = nasz)                                        AS MY_mamy_BB,
  COUNTIF(RetailerId <> nasz AND FulfilmentMethod = 'FBR')          AS Konkurent_FBR,
  COUNTIF(RetailerId <> nasz AND FulfilmentMethod = 'FBB')          AS Konkurent_FBB,
  COUNTIF(Ean_brak)                                                 AS Brak_snapshotu,
  COUNTIF(ABS(po_price - forced_price) < 0.01)                      AS Forced_w_PriceOffer,
  COUNTIF(ABS(cena_w_ofercie_bol - forced_price) < 0.02)            AS Forced_w_zywej_ofercie,
  COUNTIF(RetailerId <> nasz AND BestOfferPrice < forced_price)     AS Konkurent_zszedl_nizej,
  -- ile pozycji kwalifikuje sie do re-undercutu: konkurent tanszy, ale zejscie o krok
  -- nadal miesci sie nad nasza cena minimalna (czyli nie schodzimy ponizej kosztu)
  COUNTIF(RetailerId <> nasz
          AND HasOffer
          AND BestOfferPrice < forced_price
          AND BestOfferPrice - krok >= po_pricemin)                 AS Do_re_undercutu,
  -- SKUTEK: czy z buy-boxa cokolwiek wynika (30 dni, tylko BOL, bez anulowanych)
  COUNTIF(szt_30d > 0)                                              AS EAN_ze_sprzedaza_30d,
  IFNULL(SUM(szt_30d), 0)                                           AS Sztuk_30d,
  ROUND(IFNULL(SUM(zysk_30d), 0), 0)                                AS Zysk_30d_PLN,
  COUNTIF(RetailerId = nasz AND IFNULL(szt_30d, 0) = 0)             AS Mamy_BB_ale_zero_sprzedazy,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(LastCheckedUtc))           AS BB_ostatni_check
FROM (SELECT *, (RetailerId IS NULL OR NOT HasOffer) AS Ean_brak FROM zlaczone)
