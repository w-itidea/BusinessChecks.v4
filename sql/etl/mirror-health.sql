-- CHECK: zdrowie mirrora SQL Server -> BigQuery.
--
-- Po co. Zepsuty mirror nie wyglada na zepsuty — wyglada na dane. Przy dokladaniu
-- azymut_CustomerOrder (2026-08-26) load padl w polowie przez limit 4000 partycji i zostawil
-- 1,5 mln wierszy, ktore w kazdym zapytaniu wygladaly poprawnie. Gdyby nikt nie porownal
-- licznikow ze zrodlem, checki liczylyby sie na polowie danych i nikt by sie nie dowiedzial.
--
-- Ten check wychwytuje dwie rzeczy, ktore widac WYLACZNIE po stronie BQ (bez VPN-a do zrodla):
--   1) DUPLIKATY KLUCZA — MERGE dedupikuje staging, ale NIE tabele docelowa. Wiersze
--      zdublowane przy pelnym ladowaniu zostaja tam na zawsze i cicho mnoza wyniki JOIN-ow.
--      Zrodlo: skan `WITH (NOLOCK)` na zywej tabeli potrafi zwrocic ten sam wiersz dwa razy
--      przy podziale stron. Na CustomerOrder dalo to 3 duplikaty na 3,19 mln (2026-08-26).
--   2) ZASTOJ — ETL chodzi co 8 h, wiec watermark starszy niz prog oznacza, ze mirror stanal.
--      Objaw jest niemy: zapytania dzialaja, tylko odpowiadaja o wczorajszym swiecie.
--
-- Czego ten check NIE zrobi: nie porowna licznikow ze zrodlem, bo w chmurze nie ma dostepu do
-- SQL Servera. Braki wykryje tylko posrednio (przez zastoj), duplikaty — wprost.

DECLARE prog_zastoju_h INT64 DEFAULT 12;   -- ETL co 8 h, wiec 12 h to juz opoznienie

-- ⚠️ Wiek watermarku NIE zawsze znaczy awarie — moze znaczyc, ze zrodlo sie nie zmienia.
-- ofi_AmazonFeedProductSettings ma MAX(LastModifiedOnUtc) = 2026-07-07 rowniez W ZRODLE
-- (95 922 wiersze po obu stronach, zgodnie co do wiersza), bo to tabela ustawien, ruszana
-- rzadko i recznie. Bez tego wyjatku check krzyczalby codziennie o zdrowej tabeli, a alarm,
-- ktory zawsze wyje, przestaje cokolwiek znaczyc. Sprawdzone u zrodla 2026-08-26.
-- Jesli kiedys zacznie byc aktualizowana czesto — usun ja z tej listy.

WITH stan AS (
  SELECT 'opi_OrderProfit' AS Tabela, COUNT(*) AS Wierszy, COUNT(DISTINCT CustomerOrderId) AS Unikalnych,
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdatedOnUtc), HOUR) AS Wiek_h
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  UNION ALL SELECT 'opi_OrderItemProfit', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdateOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit`
  UNION ALL SELECT 'opi_ShippingCost', COUNT(*), COUNT(DISTINCT CustomerOrderId),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdatedOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.opi_ShippingCost`
  UNION ALL SELECT 'opi_OrderProfitTag', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(CreatedOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.opi_OrderProfitTag`
  UNION ALL SELECT 'ofi_PriceOffer', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdatedOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.ofi_PriceOffer`
  UNION ALL SELECT 'ofi_AmazonFeedProductSettings', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastModifiedOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.ofi_AmazonFeedProductSettings`
  UNION ALL SELECT 'azymut_BookstoreProductPA', COUNT(*), COUNT(DISTINCT EAN),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastModifiedOnUtc), HOUR)
  FROM `polish-bookstores-group.BIData.azymut_BookstoreProductPA`
  UNION ALL SELECT 'azymut_SupplierPA', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdated), HOUR)
  FROM `polish-bookstores-group.BIData.azymut_SupplierPA`
  UNION ALL SELECT 'azymut_CustomerOrder', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdateDateUtc), HOUR)
  FROM `polish-bookstores-group.BIData.azymut_CustomerOrder`
  UNION ALL SELECT 'azymut_BookstoreProduct', COUNT(*), COUNT(DISTINCT Id),
         TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), MAX(LastUpdatedUtc), HOUR)
  FROM `polish-bookstores-group.BIData.azymut_BookstoreProduct`
)
SELECT
  Tabela,
  Wierszy,
  Wierszy - Unikalnych                                        AS Duplikaty_klucza,
  Wiek_h                                                      AS Wiek_danych_h,
  CASE
    WHEN Wierszy - Unikalnych > 0 AND Wiek_h > prog_zastoju_h THEN '❌ duplikaty + zastoj'
    WHEN Wierszy - Unikalnych > 0                             THEN '❌ duplikaty klucza'
    WHEN Tabela = 'ofi_AmazonFeedProductSettings'             THEN '✅ (tabela ustawien — rzadko zmieniana, wiek nie jest alarmem)'
    WHEN Wiek_h > prog_zastoju_h                              THEN '⚠️ zastoj — ETL stanal?'
    ELSE '✅'
  END                                                         AS Status
FROM stan
ORDER BY (Wierszy - Unikalnych) DESC, Wiek_h DESC
