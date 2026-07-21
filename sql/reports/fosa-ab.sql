-- CHECK: test A/B „fosa" — +4% ExtraMargin (grupa 1) vs kontrola (grupa 0), BOL-NL.
-- Zastepuje ~/.claude/cron/fosa_ab_slack.sh.
--
-- ⚠️ POPRAWIONE WYSWIETLANIE. Stary raport sumowal surowe wartosci z okien o ROZNEJ dlugosci
-- (baseline 30 dni vs okres testu ~14 dni) i stawial je obok siebie. Wygladalo to tak, jakby
-- obie grupy spadly, podczas gdy po normalizacji na dobe kontrola ROSLA, a test stal w miejscu.
-- Tu wszystko jest per dobe, a roznica-w-roznicach policzona, nie zostawiona do liczenia w glowie.
--
-- Weryfikacja grup (2026-07-21): grupa 1 ma ExtraMargin = 0.04 na 10 195 z 10 254 EAN-ow,
-- grupa 0 nie ma ani jednego. Etykiety sa poprawne, grupy NIE sa zamienione.
-- Zanieczyszczenie: 103 EAN-y przejete przez pilota MS_repriceing_BolBuyBox (56 z testu,
-- 47 z kontroli) — 0,5% kohorty.

DECLARE start_testu DATE DEFAULT DATE '2026-07-07';
DECLARE base_od     DATE DEFAULT DATE '2026-06-07';
DECLARE nasz        STRING DEFAULT '1834699';

WITH okna AS (
  SELECT
    DATE_DIFF(start_testu, base_od, DAY)             AS dni_baseline,
    DATE_DIFF(CURRENT_DATE(), start_testu, DAY)      AS dni_testu
),
sprzedaz AS (
  SELECT
    oip.EAN,
    SUM(IF(DATE(op.OrderCreatedOnUtc) >= start_testu, oip.Quantity, 0))    AS szt_test,
    SUM(IF(DATE(op.OrderCreatedOnUtc) >= start_testu, oip.ItemProfit, 0))  AS prof_test,
    SUM(IF(DATE(op.OrderCreatedOnUtc) >= start_testu,
           oip.UnitSalesPriceNet * oip.Quantity, 0))                       AS rev_test,
    SUM(IF(DATE(op.OrderCreatedOnUtc) <  start_testu, oip.Quantity, 0))    AS szt_base,
    SUM(IF(DATE(op.OrderCreatedOnUtc) <  start_testu, oip.ItemProfit, 0))  AS prof_base
  FROM `polish-bookstores-group.BIData.opi_OrderItemProfit` oip
  JOIN `polish-bookstores-group.BIData.opi_OrderProfit`     op
       ON op.CustomerOrderId = oip.CustomerOrderId
  WHERE op.IdBookstore = 'BOL-NL'
    AND op.OrderStatusId <> 40
    AND DATE(op.OrderCreatedOnUtc) >= base_od
  GROUP BY oip.EAN
)
SELECT
  IF(c.grp = 1, 'TEST +4%', 'KONTROLA')                                        AS Grupa,
  COUNT(*)                                                                     AS EAN,
  -- per dobe, bo okna maja rozna dlugosc
  ROUND(SUM(IFNULL(s.szt_base, 0))  / ANY_VALUE(o.dni_baseline), 2)            AS Szt_dzien_baseline,
  ROUND(SUM(IFNULL(s.szt_test, 0))  / NULLIF(ANY_VALUE(o.dni_testu), 0), 2)    AS Szt_dzien_test,
  ROUND(SUM(IFNULL(s.prof_base, 0)) / ANY_VALUE(o.dni_baseline), 2)            AS Zysk_dzien_baseline,
  ROUND(SUM(IFNULL(s.prof_test, 0)) / NULLIF(ANY_VALUE(o.dni_testu), 0), 2)    AS Zysk_dzien_test,
  -- zmiana wzgledem wlasnego baseline — to jest to, co porownujemy miedzy grupami
  ROUND(SAFE_DIVIDE(
      SUM(IFNULL(s.prof_test, 0)) / NULLIF(ANY_VALUE(o.dni_testu), 0),
      SUM(IFNULL(s.prof_base, 0)) / ANY_VALUE(o.dni_baseline)) * 100 - 100, 1) AS Zysk_zmiana_pct,
  ROUND(SAFE_DIVIDE(SUM(IFNULL(s.prof_test, 0)),
                    SUM(IFNULL(s.rev_test, 0))) * 100, 1)                      AS Marza_pct,
  COUNTIF(bb.RetailerId = nasz)                                                AS BB_trzymamy,
  -- surowe sztuki, zeby bylo widac jak maly to wolumen (16 vs 28 = szum)
  SUM(IFNULL(s.szt_test, 0))                                                   AS Szt_surowo_test
FROM `polish-bookstores-group.BIData.fosa_ab_cohort` c
CROSS JOIN okna o
LEFT JOIN sprzedaz s ON s.EAN = c.ean
LEFT JOIN `polish-bookstores-group.BIData.mka_BolBuyBox` bb
       ON bb.Ean = c.ean AND bb.MarketplaceId = 'BOL-NL' AND bb.HasOffer
GROUP BY c.grp
ORDER BY c.grp DESC
