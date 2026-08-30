-- CHECK (SZKIELET): wiarygodnosc ETA dostawcow — obiecane vs dowiezione.
--
-- ⚠️ NIE URUCHAMIAC, dopoki mirror azymut_WarehouseRequest nie przejdzie pierwszego syncu
-- i nazwy kolumn nie zostana zweryfikowane (--describe). Kolumny oznaczone [?] sa ZGADNIETE.
--
-- PO CO: decyzja "AssignSupplier ma wybierac tanszego, gdy obaj mieszcza sie w terminie"
-- (runs/2026-08-28-amazon-spoznione-i-przeplaty.md, ~2 tys. PLN/mies. przeplat) jest bezpieczna
-- TYLKO jesli tansi dostawcy dowoza swoje ETA. Ten check to mierzy: realny lead time per
-- dostawca vs deklarowane DispatchDays. Jesli np. Platon deklaruje 1 dzien, a mediana realna
-- to 4 — "oszczednosc" z przelaczenia zamieni sie w spoznienia.
--
-- POMIAR (projekt):
--   lead time  = TIMESTAMP_DIFF(zamkniecie WR, utworzenie WR, HOUR) / 24
--   obietnica  = azymut_SupplierPA.DispatchDays (stan biezacy; historii obietnic nie ma —
--                po kilku tygodniach logu append bedzie mozna liczyc obietnice z epoki requestu)
--   wynik      = per dostawca: liczba WR, mediana i p90 lead time, DispatchDays,
--                % WR dowiezionych w deklarowanym czasie
--
-- Zrodlo stanu biezacego: WYLACZNIE widok azymut_WarehouseRequest_current (nie surowy log).

DECLARE dni_wstecz INT64 DEFAULT 30;

WITH wr AS (
  SELECT
    SupplierId,                                   -- [?]
    CreatedOnUtc,                                 -- [?]
    CompletedOnUtc,                               -- [?] data zamkniecia/przyjecia WR — NAZWA DO WERYFIKACJI
    TIMESTAMP_DIFF(CompletedOnUtc, CreatedOnUtc, HOUR) / 24.0 AS lead_dni
  FROM `polish-bookstores-group.BIData.azymut_WarehouseRequest_current`
  WHERE CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND CompletedOnUtc IS NOT NULL
),
obietnica AS (
  -- Deklarowany czas dostawy per dostawca (mediana po EAN-ach, stan biezacy)
  SELECT SupplierId, APPROX_QUANTILES(DispatchDays, 2)[OFFSET(1)] AS deklarowane_dni
  FROM `polish-bookstores-group.BIData.azymut_SupplierPA`
  WHERE iloscDostepna > 0
  GROUP BY SupplierId
)
SELECT
  wr.SupplierId                                              AS Dostawca,
  COUNT(*)                                                   AS Requestow,
  o.deklarowane_dni                                          AS Deklaruje_dni,
  ROUND(APPROX_QUANTILES(wr.lead_dni, 2)[OFFSET(1)], 1)      AS Mediana_dni,
  ROUND(APPROX_QUANTILES(wr.lead_dni, 10)[OFFSET(9)], 1)     AS P90_dni,
  ROUND(100 * COUNTIF(wr.lead_dni <= o.deklarowane_dni) / COUNT(*), 1) AS Pct_w_terminie
FROM wr
JOIN obietnica o USING (SupplierId)
GROUP BY wr.SupplierId, o.deklarowane_dni
HAVING COUNT(*) >= 20
ORDER BY Pct_w_terminie ASC
