-- CHECK: wzorce strat z ostatniej doby — agregat per przyczyna i rynek.
-- @opis Czy straty z ostatniej doby układają się we wzorzec — agregat per przyczyna i rynek.
-- @cisza-gdy-pusto
--
-- ⏱ RYTM TYGODNIOWY (decyzja Wojtka 2026-09-01): agregat to WZORZEC, a wzorzec
-- nie zmienia sie z dnia na dzien. Codzienne powtarzanie tej samej tabeli uczy ja
-- pomijac. Guard na dzien tygodnia jest w WHERE; poza poniedzialkiem check milczy.
--
-- To jest sekcja "Wzorce" ze starego digestu, policzona zamiast opisana przez model.
-- Odpowiada na pytanie "gdzie systematycznie krwawimy", a nie "co bylo najgorsze wczoraj"
-- (od tego jest stratne-daily).

DECLARE dni_wstecz INT64 DEFAULT 1;

WITH stratne AS (
  SELECT
    IdBookstore,
    Profit_Actual,
    fOrderTotal,
    CASE
      WHEN fOrderTotal < ProductCost                                     THEN 'sprzedaz ponizej kosztu towaru'
      WHEN ShippingCost > (fOrderTotal - ProductCost)                    THEN 'wysylka zjada marze'
      WHEN SAFE_DIVIDE(MarketplaceCost, NULLIF(fOrderTotal, 0)) > 0.25   THEN 'koszty marketplace > 25%'
      WHEN SAFE_DIVIDE(PaymentCost, NULLIF(fOrderTotal, 0)) > 0.10       THEN 'koszty platnosci > 10%'
      ELSE 'inne / zlozone'
    END AS przyczyna
  FROM `polish-bookstores-group.BIData.opi_OrderProfit`
  WHERE EXTRACT(DAYOFWEEK FROM CURRENT_DATE()) = 2
  AND OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND OrderStatusId <> 40
    AND IsDoneCalculating
    AND Profit_Actual < 0
)
SELECT
  przyczyna                                  AS Przyczyna,
  COUNT(*)                                   AS Zamowien,
  ROUND(SUM(Profit_Actual), 2)               AS Strata_PLN,
  ROUND(AVG(Profit_Actual), 2)               AS Srednia_strata,
  ROUND(MIN(Profit_Actual), 2)               AS Najgorsze,
  STRING_AGG(DISTINCT IdBookstore ORDER BY IdBookstore LIMIT 6) AS Rynki
FROM stratne
GROUP BY przyczyna
ORDER BY Strata_PLN ASC