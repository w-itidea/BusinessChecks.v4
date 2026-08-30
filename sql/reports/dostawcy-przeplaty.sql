-- CHECK: przeplaty AssignSupplier — kupilismy drozej, choc tanszy dostawca miescil sie w terminie
-- @opis Ile PLN przepłacamy, bo AssignSupplier wybiera szybszego zamiast tańszego dostawcę (tag 41).
--
-- Zrodlo: BIData.opi_OrderProfitTag, TagId 41. System sam taguje kazde zamowienie, przy ktorym
-- kupiono u dostawcy X, choc dostawca Y mial taniej I OBAJ miescili sie w terminie wysylki.
-- Note ma zawsze ten sam format (generowany przez opi.UpdateOrderProfitTags):
--   "Przeplata ok. 1.26 PLN (3 linii). EAN ...: kupilismy u Ateneum po 21.38 (ETA ...),
--    a Platon mial po 21.00 (ETA ...), termin ... AssignSupplier wybral szybszego zamiast
--    tanszego, choc obaj miescili sie w terminie."
-- Regexy ponizej parsuja ten format; gdy format Note sie zmieni, kolumny wyjda NULL —
-- to sygnal do poprawy checku, nie prawda o biznesie (patrz skill: podejrzanie okragly wynik).
--
-- Diagnostyka 2026-08-28 (okno 60 dni): ~4,0 tys. PLN przeplat, z czego 65% to jeden wzorzec
-- "kupiono u Ateneum, Platon mial taniej" (830 zamowien, 2601 PLN). Pelny wynik i decyzja:
-- runs/2026-08-28-amazon-spoznione-i-przeplaty.md

DECLARE dni_wstecz INT64 DEFAULT 7;
DECLARE min_zamowien INT64 DEFAULT 3;  -- pary rzadsze niz to laduja w wierszu zbiorczym "inne"

WITH tagi AS (
  SELECT
    CustomerOrderId,
    SAFE_CAST(REGEXP_EXTRACT(Note, r'Przep[łl]ata ok\. ([0-9]+\.?[0-9]*) PLN') AS FLOAT64) AS przeplata_pln,
    REGEXP_EXTRACT(Note, r'kupili[śs]my u ([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż ]+?) po')             AS kupiono_u,
    REGEXP_EXTRACT(Note, r'a ([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż ]+?) mia[łl]')                     AS tanszy_byl
  FROM `polish-bookstores-group.BIData.opi_OrderProfitTag`
  WHERE CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
    AND TagId = 41
),
pary AS (
  SELECT
    COALESCE(kupiono_u, '?')  AS kupiono_u,
    COALESCE(tanszy_byl, '?') AS tanszy_byl,
    COUNT(*)                  AS n,
    SUM(przeplata_pln)        AS suma_pln,
    AVG(przeplata_pln)        AS srednia_pln,
    MAX(przeplata_pln)        AS max_pln
  FROM tagi
  GROUP BY 1, 2
)
SELECT
  IF(n >= min_zamowien, kupiono_u,  'inne')                       AS Kupiono_u,
  IF(n >= min_zamowien, tanszy_byl, '—')                          AS Tanszy_byl,
  SUM(n)                                                          AS Zamowien,
  ROUND(SUM(suma_pln), 0)                                         AS Przeplata_PLN,
  ROUND(SUM(suma_pln) / SUM(n), 2)                                AS Srednio_PLN,
  ROUND(MAX(max_pln), 0)                                          AS Max_PLN
FROM pary
GROUP BY 1, 2
ORDER BY Przeplata_PLN DESC
