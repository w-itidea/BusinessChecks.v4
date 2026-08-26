-- location: EU
-- CHECK: miesieczny monitoring kosztow GCP — konto Karta TW (billing export @ EU).
--
-- Zrodlo: polish-bookstores-group.oferta_produkcyjny_billing (resource-level).
-- Dataset lezy w EU (multi-region), NIE europe-west3 — stad naglowek `-- location: EU`
-- (runner odpala job w tym regionie). Workspace (US) jest osobno, maly i stabilny — pominiety.
--
-- Klasyfikacja policzona w SQL, nie w prompcie: RAZEM z VAT, MoM, r/r, TOP5 uslug + "pod obserwacja".
-- Invoice = VAT (23%); brutto = suma z Invoice, a gdy VAT jeszcze niezaksiegowany -> netto*1,23.
-- Uruchamiane co miesiac (3. dnia — billing ma 1-2 dni lagu + korekty po koncu miesiaca).

DECLARE cm STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH));   -- zamkniety
DECLARE pm STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 2 MONTH));   -- poprzedni
DECLARE ym STRING DEFAULT FORMAT_DATE('%Y%m', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 13 MONTH));  -- rok temu

WITH base AS (
  SELECT
    invoice.month       AS mc,
    service.description  AS svc,
    sku.description      AS sku,
    SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS net
  FROM `polish-bookstores-group.oferta_produkcyjny_billing.gcp_billing_export_resource_v1_01F457_F3A85E_2D9D9D`
  WHERE _PARTITIONTIME >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 13 MONTH))
    AND invoice.month IN (cm, pm, ym)
  GROUP BY 1, 2, 3
),
gross AS (   -- brutto (z VAT) per miesiac
  SELECT mc,
    IF(SUM(IF(svc = 'Invoice', net, 0)) > 0, SUM(net), SUM(IF(svc <> 'Invoice', net, 0)) * 1.23) AS g
  FROM base GROUP BY mc
),
svc_m AS (   -- per usluga (bez VAT) per miesiac
  SELECT mc, svc, SUM(net) AS net FROM base WHERE svc <> 'Invoice' GROUP BY 1, 2
),
wynik AS (
  -- 1) RAZEM z VAT + MoM + r/r
  SELECT 1 AS ord, 0.0 AS ord2,
    CONCAT('RAZEM · Karta TW ', cm, ' z VAT') AS pozycja,
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
  -- 3) POD OBSERWACJA — nazwane metryki (zamkniety vs poprzedni miesiac)
  SELECT 3, -w.cur, CONCAT('OBS · ', w.label),
    CONCAT(CAST(CAST(ROUND(w.cur) AS INT64) AS STRING), ' zl'),
    CONCAT('poprz. ', IFNULL(CONCAT(CAST(CAST(ROUND(w.prev) AS INT64) AS STRING), ' zl'), '—'),
      IF(w.prev IS NULL OR w.prev = 0, '', CONCAT(' (', FORMAT('%+.0f%%', (w.cur - w.prev) / w.prev * 100), ')')))
  FROM (
    SELECT 'BigQuery zapytania (MERGE)' AS label,
      (SELECT SUM(net) FROM base WHERE mc = cm AND sku LIKE 'Analysis%') AS cur,
      (SELECT SUM(net) FROM base WHERE mc = pm AND sku LIKE 'Analysis%') AS prev
    UNION ALL SELECT 'Dataplex (sierota data-prep)',
      (SELECT SUM(net) FROM base WHERE mc = cm AND sku LIKE 'Dataplex Premium Processing%'),
      (SELECT SUM(net) FROM base WHERE mc = pm AND sku LIKE 'Dataplex Premium Processing%')
    UNION ALL SELECT 'Compute Engine (search PoC)',
      (SELECT SUM(net) FROM base WHERE mc = cm AND svc = 'Compute Engine'),
      (SELECT SUM(net) FROM base WHERE mc = pm AND svc = 'Compute Engine')
    UNION ALL SELECT 'Cloud Storage (po Archive)',
      (SELECT SUM(net) FROM base WHERE mc = cm AND svc = 'Cloud Storage'),
      (SELECT SUM(net) FROM base WHERE mc = pm AND svc = 'Cloud Storage')
  ) w
)
SELECT pozycja, pln, zmiana
FROM wynik
ORDER BY ord, ord2
