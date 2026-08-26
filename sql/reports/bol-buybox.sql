-- CHECK: pilot BOL buy-box — czy odzyskujemy Buy Box i czy forced cena dociera do oferty.
-- @opis Czy pilot repricingu na BOL odzyskuje buy-box i czy wymuszona cena faktycznie dociera do oferty.
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

WITH pilot AS (
  SELECT OurEan, ROUND(Price, 2) AS forced_price
  FROM `polish-bookstores-group.BIData.ofi_AmazonFeedProductSettings`
  WHERE BookstoreId = 'BOL-NL' AND TestGroupName = grupa AND fIsActive = 1
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
zlaczone AS (
  SELECT
    p.OurEan, p.forced_price,
    bb.RetailerId, bb.FulfilmentMethod, bb.BestOfferPrice, bb.HasOffer, bb.LastCheckedUtc,
    po.Price AS po_price, po.PriceMin AS po_pricemin,
    ob.cena_w_ofercie_bol
  FROM pilot p
  LEFT JOIN `itideatestproject.bol_ew3.BolBuyBox_current` bb
         ON bb.Ean = p.OurEan AND bb.MarketplaceId = 'BOL-NL'
  LEFT JOIN `polish-bookstores-group.BIData.ofi_PriceOffer` po
         ON po.SKU = p.OurEan AND po.BookstoreId = 'BOL-NL'
  LEFT JOIN oferta_bol ob
         ON ob.Ean = p.OurEan
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
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M', MAX(LastCheckedUtc))           AS BB_ostatni_check
FROM (SELECT *, (RetailerId IS NULL OR NOT HasOffer) AS Ean_brak FROM zlaczone)
