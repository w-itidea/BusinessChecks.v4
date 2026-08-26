-- CHECK: sale test EU — Buy Box + ZYSKOWNOSC
-- @opis Czy przecena 2 424 SKU z 17.07 realnie przełożyła się na buy-box, sztuki i zysk.
--
-- Pytanie: z 2424 SKU wypchnietych na sale (2026-07-17) ile wygrywa Buy Box,
--          ORAZ ile zamowien / sztuk / zysku te wygrane BB faktycznie wygenerowaly.
--
-- Zrodla (wszystkie europe-west3, wiec joinuja sie natywnie):
--   amazon_catalog.sale_test_pushed   — kohorta pushnieta na sale (market, sku, our_price, sale_price)
--   BIData.ofi_PriceOffer             — mapowanie SKU -> ASIN (mirror BIData, ma SKU i Asin)
--   AwsMarketPlace.AmazonPriceLatest  — OurOffer.IsBuyBoxWinner (stan biezacy)
--   BIData.opi_OrderItemProfit        — zysk per pozycja (EAN)
--   BIData.opi_OrderProfit            — rynek, data, status zamowienia
--
-- UWAGA metodologiczna: to jest atrybucja KORELACYJNA, nie przyczynowa. Liczymy sprzedaz
-- EAN-ow z kohorty w oknie sale. Bez grupy kontrolnej nie wiadomo, ile z tego bylo sie
-- sprzedalo i bez obnizki. Traktowac jako kierunek, nie dowod.

DECLARE start_sale DATE  DEFAULT DATE '2026-07-17';   -- dzien pushu sale
DECLARE dni_przed INT64  DEFAULT 14;                  -- okno baseline do porownania

WITH kohorta AS (
  SELECT
    market,
    marketplace_id,
    -- UWAGA: kolumna `market` JUZ zawiera prefiks (np. 'AZ-NL'). Doklejanie 'AZ-' dawalo
    -- 'AZ-AZ-NL' i ciche wyzerowanie WSZYSTKICH zlaczen — wynik wygladal jak "brak sprzedazy".
    market                                      AS id_bookstore,
    sku,
    REGEXP_EXTRACT(sku, r'^([0-9]+)')           AS ean,
    our_price,
    sale_price,
    SAFE_DIVIDE(our_price - sale_price, our_price) AS obnizka_pct
  FROM `polish-bookstores-group.amazon_catalog.sale_test_pushed`
  WHERE REGEXP_CONTAINS(sku, r'^[0-9]+')
),

-- SKU -> ASIN z mirrora PriceOffer (bierzemy najswiezszy wiersz per SKU+rynek)
sku_asin AS (
  SELECT BookstoreId, SKU, ANY_VALUE(Asin HAVING MAX LastUpdatedOnUtc) AS asin
  FROM `polish-bookstores-group.BIData.ofi_PriceOffer`
  WHERE Asin IS NOT NULL
  GROUP BY BookstoreId, SKU
),

-- Buy Box: czy NASZA oferta trzyma BB na tym ASIN-ie i TYM rynku.
-- OurOffer jest tablica (ARRAY<STRUCT>), nie pojedynczym rekordem -> UNNEST.
-- Zlaczenie MUSI isc po (ASIN, MarketplaceID): sam ASIN zaciagnalby oferty ze wszystkich rynkow.
bb AS (
  SELECT
    k.market, k.sku, k.ean,
    (SELECT LOGICAL_OR(o.IsBuyBoxWinner) FROM UNNEST(p.OurOffer) o) AS wygrywa_bb
  FROM kohorta k
  JOIN sku_asin sa       ON sa.BookstoreId = k.id_bookstore AND sa.SKU = k.sku
  JOIN `polish-bookstores-group.AwsMarketPlace.AmazonPriceLatest` p
                         ON p.ASIN = sa.asin AND p.MarketplaceID = k.marketplace_id
),

-- Sprzedaz i zysk EAN-ow z kohorty, w oknie sale i w oknie baseline
sprzedaz AS (
  SELECT
    op.IdBookstore                                        AS id_bookstore,
    oip.EAN                                               AS ean,
    IF(DATE(op.OrderCreatedOnUtc) >= start_sale, 'sale', 'baseline') AS okno,
    COUNT(DISTINCT op.CustomerOrderId)                    AS zamowien,
    SUM(oip.Quantity)                                     AS sztuk,
    SUM(oip.ItemProfit)                                   AS zysk_pln,
    SUM(oip.UnitSalesPriceNet * oip.Quantity)             AS przychod_pln
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit` oip
  JOIN `polish-bookstores-group.BIData.opi_OrderProfit`     op
       ON op.CustomerOrderId = oip.CustomerOrderId
  WHERE op.OrderCreatedOnUtc >= TIMESTAMP(DATE_SUB(start_sale, INTERVAL dni_przed DAY))
    AND op.OrderStatusId <> 40                     -- 40 = anulowane, zawsze wykluczamy
  GROUP BY 1, 2, 3
)

SELECT
  k.market                                                       AS Rynek,
  COUNT(DISTINCT k.sku)                                           AS SKU_w_tescie,
  COUNTIF(bb.wygrywa_bb)                                          AS BB_wygrane,
  ROUND(SAFE_DIVIDE(COUNTIF(bb.wygrywa_bb), COUNT(bb.sku)) * 100, 1) AS BB_win_pct,
  ROUND(AVG(k.obnizka_pct) * 100, 1)                              AS Sr_obnizka_pct,

  -- zyskownosc w oknie sale
  SUM(IF(s.okno = 'sale', s.zamowien, 0))                         AS Zamowien_sale,
  SUM(IF(s.okno = 'sale', s.sztuk, 0))                            AS Sztuk_sale,
  ROUND(SUM(IF(s.okno = 'sale', s.zysk_pln, 0)), 2)               AS Zysk_sale_PLN,
  ROUND(SAFE_DIVIDE(SUM(IF(s.okno = 'sale', s.zysk_pln, 0)),
                    SUM(IF(s.okno = 'sale', s.przychod_pln, 0))) * 100, 1) AS Marza_sale_pct,

  -- to samo sprzed obnizki (baseline), zeby bylo z czym porownac
  SUM(IF(s.okno = 'baseline', s.sztuk, 0))                        AS Sztuk_baseline,
  ROUND(SUM(IF(s.okno = 'baseline', s.zysk_pln, 0)), 2)           AS Zysk_baseline_PLN,
  ROUND(SAFE_DIVIDE(SUM(IF(s.okno = 'baseline', s.zysk_pln, 0)),
                    SUM(IF(s.okno = 'baseline', s.przychod_pln, 0))) * 100, 1) AS Marza_baseline_pct

FROM kohorta k
LEFT JOIN bb        ON bb.market = k.market AND bb.sku = k.sku
LEFT JOIN sprzedaz s ON s.ean = k.ean AND s.id_bookstore = k.id_bookstore
GROUP BY k.market
ORDER BY BB_win_pct DESC
