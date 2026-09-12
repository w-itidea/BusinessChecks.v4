-- czy w sierpniu realnie zwolnila realizacja (zrodlo niezalezne od tagow)
SELECT DATE_TRUNC(DATE(CreatedOnUtc), WEEK(MONDAY)) Tydzien,
  COUNT(*) Zam,
  ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(ShippedDateUtc, PaidDateUtc, HOUR),100)[OFFSET(50)],1) Mediana_h,
  ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(ShippedDateUtc, PaidDateUtc, HOUR),100)[OFFSET(90)],1) p90_h,
  ROUND(100*AVG(IF(TIMESTAMP_DIFF(ShippedDateUtc, PaidDateUtc, HOUR) > 48, 1, 0)),1) Pct_ponad_48h
FROM `polish-bookstores-group.BIData.azymut_CustomerOrder`
WHERE CreatedOnUtc >= TIMESTAMP('2026-06-01')
  AND CreatedOnUtc < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 DAY)
  AND OrderStatusId <> 40 AND ShippedDateUtc IS NOT NULL AND PaidDateUtc IS NOT NULL
GROUP BY 1 ORDER BY 1
