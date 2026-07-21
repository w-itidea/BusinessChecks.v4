-- CHECK: pilot BOL buy-box — czy odzyskujemy Buy Box i czy forced cena dociera do oferty.
-- Zastepuje pierwsza czesc ~/.claude/cron/bol_buybox_slack.sh (bol_quickwin_KONTROLA.sql).
--
-- Baza wyjsciowa pilota (2026-06-29): wszystkie EAN-y mialy konkurenta na FBR, my drozsi, bez BB.
-- Mierzymy dwie rzeczy naraz:
--   1. WYNIK   — ile Buy Boxow jest teraz nasze
--   2. PROPAGACJA — czy forced cena z ustawien faktycznie weszla do PriceOffer i do zywej oferty BOL
--      (bez tego "nie odzyskalismy BB" moze znaczyc po prostu "cena nigdzie nie doszla")
--
-- UWAGA REGION: prawdziwe, historyczne dane BOL zyja w `itideatestproject.bol` @ EU
-- (BolBuyBox: 4,6 mln wierszy z partycjonowaniem dziennym). NIE da sie ich zjoinowac
-- z profitem, bo BIData jest @ europe-west3, a BigQuery nie laczy przez regiony.
-- Dlatego czytamy mirror stanu biezacego `BIData.mka_BolBuyBox`. Historii tu nie ma.

DECLARE nasz      STRING  DEFAULT '1834699';
DECLARE grupa     STRING  DEFAULT 'MS_repriceing_BolBuyBox20260629';
DECLARE krok      NUMERIC DEFAULT 0.02;   -- o tyle schodzimy ponizej konkurenta przy re-undercut

WITH pilot AS (
  SELECT OurEan, ROUND(Price, 2) AS forced_price
  FROM `polish-bookstores-group.BIData.ofi_AmazonFeedProductSettings`
  WHERE BookstoreId = 'BOL-NL' AND TestGroupName = grupa AND fIsActive = 1
),
zlaczone AS (
  SELECT
    p.OurEan, p.forced_price,
    bb.RetailerId, bb.FulfilmentMethod, bb.BestOfferPrice, bb.HasOffer, bb.LastCheckedUtc,
    po.Price AS po_price, po.PriceMin AS po_pricemin,
    bofo.BundlePricesPrice AS cena_w_ofercie_bol
  FROM pilot p
  LEFT JOIN `polish-bookstores-group.BIData.mka_BolBuyBox` bb
         ON bb.Ean = p.OurEan AND bb.MarketplaceId = 'BOL-NL'
  LEFT JOIN `polish-bookstores-group.BIData.ofi_PriceOffer` po
         ON po.SKU = p.OurEan AND po.BookstoreId = 'BOL-NL'
  LEFT JOIN `polish-bookstores-group.BIData.azymut_BolOffersFirstOffer` bofo
         ON bofo.Ean = p.OurEan
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
