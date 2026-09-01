-- CHECK: pokrycie raportow Amazona — czy dane o koncie w ogole do nas doplywaja.
-- @opis Ktorych raportow Amazona brakuje i na ktorych rynkach jestesmy slepi. Cisza nie znaczy spokoj.
-- @cisza-gdy-pusto
--
-- Po co ten check istnieje (2026-08-31):
-- Maszyneria pobierania raportow dziala od lat, ale NIKT nad nia nie stal. Skutki, wykryte recznie:
--   * tabela V2SellerPerformanceReport stala od 2026-06-01 — trzy miesiace, nikt nie zauwazyl
--   * AZ-PL i AZ-IE NIGDY nie byly pobierane — rok, nikt nie zauwazyl
--   * feedback per-rynek: 8 sukcesow na 3 938 prob na AZ-UK — nikt nie zauwazyl
--   * ODR Belgii rosl 0,385% -> 1,601% miesiac po miesiacu — nikt nie zauwazyl
--
-- 🔴 KLUCZOWA DECYZJA PROJEKTOWA (uwaga Wojtka 2026-08-31):
-- Check NIE porownuje sie z kolejka zamowien ani ze strumieniem zdarzen SQS. Oba mowia tylko
-- o tym, CO SIE WYDARZYLO. Jesli nikt nigdy nie zamowil raportu dla AZ-PL, to nie ma ani
-- statusu, ani bledu, ani notyfikacji — cisza wyglada identycznie jak spokoj. Dokladnie
-- dlatego PL i IE byly niewidoczne przez rok.
-- Dlatego porownujemy z JAWNIE ZADEKLAROWANA lista ponizej: te rynki, te raporty, ta czestotliwosc.
-- Brak jest wtedy bledem, a nie brakiem danych. Dodajesz rynek -> dopisz go tutaj.

DECLARE oczekiwane ARRAY<STRUCT<raport STRING, rynek STRING, max_dni INT64>> DEFAULT [
  -- Zdrowie konta: codziennie, na kazdym rynku gdzie sprzedajemy
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-DE', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-UK', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-FR', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-IT', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-ES', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-NL', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-BE', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-SE', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-PL', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-IE', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'NA',    2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'FE',    2),
  -- Komentarze: codziennie, bo to wejscie do ODR
  ('GET_SELLER_FEEDBACK_DATA', 'AZ-DE', 2), ('GET_SELLER_FEEDBACK_DATA', 'AZ-UK', 2),
  ('GET_SELLER_FEEDBACK_DATA', 'AZ-FR', 2), ('GET_SELLER_FEEDBACK_DATA', 'AZ-IT', 2),
  ('GET_SELLER_FEEDBACK_DATA', 'AZ-ES', 2), ('GET_SELLER_FEEDBACK_DATA', 'AZ-NL', 2),
  ('GET_SELLER_FEEDBACK_DATA', 'AZ-BE', 2), ('GET_SELLER_FEEDBACK_DATA', 'AZ-SE', 2),
  ('GET_SELLER_FEEDBACK_DATA', 'AZ-PL', 2), ('GET_SELLER_FEEDBACK_DATA', 'AZ-IE', 2),
  -- Zwroty: co kilka dni wystarczy, ale nie moga zniknac
  ('GET_FLAT_FILE_RETURNS_DATA_BY_RETURN_DATE', 'AZ-DE', 4),
  ('GET_FLAT_FILE_RETURNS_DATA_BY_RETURN_DATE', 'AZ-UK', 4),
  ('GET_FLAT_FILE_RETURNS_DATA_BY_RETURN_DATE', 'AZ-FR', 4),
  ('GET_FLAT_FILE_RETURNS_DATA_BY_RETURN_DATE', 'AZ-IT', 4),
  ('GET_FLAT_FILE_RETURNS_DATA_BY_RETURN_DATE', 'AZ-ES', 4)
];

WITH mamy AS (
  -- Co realnie u nas wyladowalo. Liczy sie tylko udane pobranie — wiersz FAILED albo EMPTY
  -- jest informacja o problemie, nie o pokryciu.
  --
  -- status IS NULL AND contentBytes > 0 to wiersze sprzed dodania kolumny status (2026-08-31).
  -- Maja tresc, wiec sa prawdziwym pokryciem; bez tego warunku check krzyczalby
  -- "NIGDY NIE POBRANE" na dane, ktore realnie mamy — czyli uczylby ludzi ignorowac alarm.
  SELECT reportType AS raport, market AS rynek,
         MAX(IF(status = 'LANDED' OR (status IS NULL AND contentBytes > 0),
                DATE(fetchedOnUtc), NULL))                                   AS ostatni,
         COUNTIF(status = 'LANDED' OR (status IS NULL AND contentBytes > 0)) AS udanych,
         COUNTIF(status = 'FAILED')                                          AS bledow
  FROM `rd-basenv.amazon_raw.reports`
  GROUP BY raport, rynek
)
SELECT
  o.raport                                                       AS Raport,
  o.rynek                                                        AS Rynek,
  IFNULL(CAST(m.ostatni AS STRING), '—')                         AS Ostatni,
  IFNULL(CAST(DATE_DIFF(CURRENT_DATE(), m.ostatni, DAY) AS STRING), 'NIGDY')
                                                                 AS Dni_temu,
  IFNULL(m.udanych, 0)                                           AS Udanych,
  IFNULL(m.bledow, 0)                                            AS Bledow,
  CASE
    WHEN m.ostatni IS NULL                                                THEN '1. NIGDY NIE POBRANE'
    WHEN DATE_DIFF(CURRENT_DATE(), m.ostatni, DAY) > o.max_dni * 3        THEN '2. MARTWE'
    WHEN DATE_DIFF(CURRENT_DATE(), m.ostatni, DAY) > o.max_dni            THEN '3. SPOZNIONE'
    ELSE                                                                       '4. ok'
  END                                                            AS Stan
FROM UNNEST(oczekiwane) AS o
LEFT JOIN mamy m ON m.raport = o.raport AND m.rynek = o.rynek
-- Milczymy, gdy wszystko dziala. Codzienna tabelka pelna "ok" uczy ludzi
-- ignorowac wiadomosc, a wtedy check przestaje pelnic swoja funkcje.
WHERE m.ostatni IS NULL
   OR DATE_DIFF(CURRENT_DATE(), m.ostatni, DAY) > o.max_dni
ORDER BY Stan, o.raport, o.rynek;