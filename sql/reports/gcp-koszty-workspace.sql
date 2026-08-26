-- location: US
-- @opis Ile wydaliśmy w GCP w minionym miesiącu (konto FKWT Workspace, region US) i co najbardziej urosło.
-- CHECK: miesieczny monitoring kosztow GCP — konto FKWT Workspace (billing export @ US).
--
-- Zrodlo: erp-production-438714.erp_production_billing (resource-level).
-- Dataset lezy w US — stad naglowek `-- location: US` (runner odpala job w US).
-- Para do `gcp-koszty-miesieczny` (Karta TW/EU); oba checki lecą jednym triggerem -> jedna wiadomosc.
--
-- Konto mniejsze i stabilne: glowne pozycje to Cloud Storage + Secret Manager (Cloud SQL zniknal ~III 2026).
-- Invoice = VAT (23%); brutto = suma z Invoice, a gdy VAT niezaksiegowany -> netto*1,23.

DECLARE cm STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH));   -- zamkniety
DECLARE pm STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 2 MONTH));   -- poprzedni
DECLARE ym STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 13 MONTH));  -- rok temu

WITH base AS (
  SELECT
    invoice.month       AS mc,
    service.description  AS svc,
    sku.description      AS sku,
    SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS net
  FROM `erp-production-438714.erp_production_billing.gcp_billing_export_resource_v1_018973_2B16D0_BA1CCE`
  WHERE _PARTITIONTIME >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 13 MONTH))
    AND invoice.month IN (cm, pm, ym)
  GROUP BY 1, 2, 3
),
gross AS (
  SELECT mc,
    IF(SUM(IF(svc = 'Invoice', net, 0)) > 0, SUM(net), SUM(IF(svc <> 'Invoice', net, 0)) * 1.23) AS g
  FROM base GROUP BY mc
),
svc_m AS (
  SELECT mc, svc, SUM(net) AS net FROM base WHERE svc <> 'Invoice' GROUP BY 1, 2
),
wynik AS (
  -- 1) RAZEM z VAT + MoM + r/r
  SELECT 1 AS ord, 0.0 AS ord2,
    CONCAT('RAZEM · Workspace ', cm, ' z VAT') AS pozycja,
    CONCAT(CAST(CAST(ROUND((SELECT g FROM gross WHERE mc = cm)) AS INT64) AS STRING), ' zl') AS pln,
    CONCAT(
      'MoM ', IF((SELECT g FROM gross WHERE mc = pm) IS NULL, '—',
        FORMAT('%+.0f%%', ((SELECT g FROM gross WHERE mc = cm) - (SELECT g FROM gross WHERE mc = pm)) / (SELECT g FROM gross WHERE mc = pm) * 100)),
      ' / r/r ', IF((SELECT g FROM gross WHERE mc = ym) IS NULL, '—',
        FORMAT('%+.0f%%', ((SELECT g FROM gross WHERE mc = cm) - (SELECT g FROM gross WHERE mc = ym)) / (SELECT g FROM gross WHERE mc = ym) * 100))
    ) AS zmiana

  UNION ALL
  -- 2) TOP 5 uslug zamknietego miesiaca (bez VAT) + MoM per usluga
  SELECT 2, -c.net, CONCAT('TOP · ', c.svc),
    CONCAT(CAST(CAST(ROUND(c.net) AS INT64) AS STRING), ' zl'),
    CONCAT('MoM ', IF(p.net IS NULL OR p.net = 0, '—', FORMAT('%+.0f%%', (c.net - p.net) / p.net * 100)))
  FROM (SELECT svc, net FROM svc_m WHERE mc = cm ORDER BY net DESC LIMIT 5) c
  LEFT JOIN (SELECT svc, net FROM svc_m WHERE mc = pm) p USING (svc)

  UNION ALL
  -- 3) POD OBSERWACJA — metryki wlasciwe dla US (zamkniety vs poprzedni)
  SELECT 3, -w.cur, CONCAT('OBS · ', w.label),
    CONCAT(CAST(CAST(ROUND(w.cur) AS INT64) AS STRING), ' zl'),
    CONCAT('poprz. ', IFNULL(CONCAT(CAST(CAST(ROUND(w.prev) AS INT64) AS STRING), ' zl'), '—'),
      IF(w.prev IS NULL OR w.prev = 0, '', CONCAT(' (', FORMAT('%+.0f%%', (w.cur - w.prev) / w.prev * 100), ')')))
  FROM (
    SELECT 'Cloud Storage' AS label,
      (SELECT SUM(net) FROM base WHERE mc = cm AND svc = 'Cloud Storage') AS cur,
      (SELECT SUM(net) FROM base WHERE mc = pm AND svc = 'Cloud Storage') AS prev
    UNION ALL SELECT 'Secret Manager',
      (SELECT SUM(net) FROM base WHERE mc = cm AND svc = 'Secret Manager'),
      (SELECT SUM(net) FROM base WHERE mc = pm AND svc = 'Secret Manager')
  ) w
)
SELECT pozycja, pln, zmiana
FROM wynik
ORDER BY ord, ord2
