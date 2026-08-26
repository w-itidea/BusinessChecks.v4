-- CHECK: sprzedaz i jakosc realizacji listy "wyd. obcojezyczne" Platona vs RESZTA KATALOGU.
--
-- Kontekst: 2026-08-14 Supplier.QtyCorrection dla Platona (224) zmieniony z -3 na -1
-- (szczegoly w platon-wydobco-ekspozycja.sql). Ten check mierzy, czy to sie oplaca
-- i czy nie placimy za to brakami.
--
-- Dlaczego kazdy wiersz ma pare lista/reszta: wzrost sprzedazy sam w sobie nic nie dowodzi,
-- bo moze byc sezonem. Pierwszy pomiar (14-23.08) pokazal +125% na liscie przy JEDNOCZESNYM
-- -13% na reszcie katalogu — dopiero to zestawienie czyni wynik wiarygodnym.
--
-- ⚠️ Odstepstwo od reguly "zawsze OrderStatusId <> 40": anulacje sa tu MIERZONA WIELKOSCIA,
-- wiec kolumna Anulacje_pct liczy sie po pelnym zbiorze. Wszystkie metryki pienieznie
-- i wolumenowe (Egz/Zysk/Marza) filtr <> 40 stosuja.
-- ⚠️ Zysk pokazujemy tylko z IsDoneCalculating (profit domkniety). Kolumna Pct_domkniete
-- mowi, na ilu procentach pozycji ten zysk sie opiera — dla swiezego okna bywa nizsza,
-- wiec Zysk_dzien z ostatnich 7 dni czytaj z ta poprawka, nie jako liczbe ostateczna.

DECLARE base_od DATE DEFAULT DATE '2026-08-04';   -- okno przed zmiana korekty
DECLARE base_do DATE DEFAULT DATE '2026-08-14';   -- dzien wejscia zmiany
DECLARE w1_od   DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);
-- okno "poprzedni tydzien" nie moze siegac przed koniec baseline, inaczej okna sie nakladaja
-- i baseline wychodzi zanizony (na tym sie juz przejechalem przy wersji SQL-Serverowej)
DECLARE w2_od   DATE DEFAULT GREATEST(DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY), DATE '2026-08-14');

WITH poz AS (
  SELECT
    CASE
      WHEN DATE(op.OrderCreatedOnUtc) >= base_od AND DATE(op.OrderCreatedOnUtc) < base_do
           THEN 'A. baseline 04-13.08 (przed zmiana)'
      WHEN DATE(op.OrderCreatedOnUtc) >= w1_od  THEN 'C. ostatnie 7 dni'
      WHEN DATE(op.OrderCreatedOnUtc) >= w2_od  THEN 'B. poprzedni tydzien'
    END                                                       AS Okno,
    IF(c.EAN IS NULL, '2. reszta katalogu', '1. lista Platon') AS Grupa,
    op.OrderStatusId,
    op.IsDoneCalculating,
    oip.Quantity,
    oip.ItemProfit,
    oip.UnitSalesPriceNet,
    co.PaidDateUtc,
    co.ShippedDateUtc
  FROM `polish-bookstores-group.BIData.opi_OrderProfit` op
  JOIN `polish-bookstores-group.BIData.opi_OrderItemProfit` oip
       ON oip.CustomerOrderId = op.CustomerOrderId
  LEFT JOIN `polish-bookstores-group.BIData.platon_wydobco_cohort` c
       ON c.EAN = oip.EAN
  LEFT JOIN `polish-bookstores-group.BIData.azymut_CustomerOrder` co
       ON co.Id = op.CustomerOrderId
  WHERE DATE(op.OrderCreatedOnUtc) >= base_od      -- filtr po kolumnie partycjonujacej
)
SELECT
  Okno,
  Grupa,
  COUNT(*)                                                                     AS Pozycji,
  ROUND(SAFE_DIVIDE(SUM(IF(OrderStatusId <> 40, Quantity, 0)),
        CASE WHEN Okno LIKE 'A.%' THEN DATE_DIFF(base_do, base_od, DAY)
             WHEN Okno LIKE 'C.%' THEN 7
             ELSE DATE_DIFF(w1_od, w2_od, DAY) END), 1)                        AS Egz_dzien,
  ROUND(SAFE_DIVIDE(SUM(IF(OrderStatusId <> 40 AND IsDoneCalculating, ItemProfit, 0)),
        CASE WHEN Okno LIKE 'A.%' THEN DATE_DIFF(base_do, base_od, DAY)
             WHEN Okno LIKE 'C.%' THEN 7
             ELSE DATE_DIFF(w1_od, w2_od, DAY) END), 2)                        AS Zysk_dzien,
  ROUND(SAFE_DIVIDE(
      SUM(IF(OrderStatusId <> 40 AND IsDoneCalculating, ItemProfit, 0)),
      SUM(IF(OrderStatusId <> 40 AND IsDoneCalculating, UnitSalesPriceNet * Quantity, 0))
  ) * 100, 2)                                                                  AS Marza_pct,
  ROUND(SAFE_DIVIDE(COUNTIF(IsDoneCalculating), COUNT(*)) * 100, 1)            AS Pct_domkniete,
  -- anulacje: swiadomie po pelnym zbiorze (to jest mierzona wielkosc, nie zanieczyszczenie)
  ROUND(SAFE_DIVIDE(COUNTIF(OrderStatusId = 40), COUNT(*)) * 100, 2)           AS Anulacje_pct,
  ROUND(SAFE_DIVIDE(COUNTIF(ShippedDateUtc IS NOT NULL), COUNT(*)) * 100, 1)   AS Wyslane_pct,
  ROUND(AVG(IF(ShippedDateUtc IS NOT NULL AND PaidDateUtc IS NOT NULL,
               TIMESTAMP_DIFF(ShippedDateUtc, TIMESTAMP(PaidDateUtc), HOUR) / 24.0,
               NULL)), 2)                                                      AS Sr_dni_do_wysylki
FROM poz
WHERE Okno IS NOT NULL
GROUP BY Okno, Grupa
ORDER BY Okno, Grupa
