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
  -- NA i FE deklarujemy RYNKAMI, nie regionami: worker w trybie `request` zapisuje marketplace.
  -- Sprzedaz 90 dni (2026-09-02): AZ-CA 1 820, AZ-US 1 012, AZ-AU 765 — zaden nie jest do skreslenia.
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-US', 2), ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-CA', 2),
  ('GET_V2_SELLER_PERFORMANCE_REPORT', 'AZ-AU', 2),
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

-- Rynki regionu — do rozwijania raportow zamawianych REGIONALNIE (patrz nizej).
DECLARE regiony ARRAY<STRUCT<region STRING, rynek STRING>> DEFAULT [
  ('EU','AZ-DE'), ('EU','AZ-UK'), ('EU','AZ-FR'), ('EU','AZ-IT'), ('EU','AZ-ES'),
  ('EU','AZ-NL'), ('EU','AZ-BE'), ('EU','AZ-SE'), ('EU','AZ-PL'), ('EU','AZ-IE'),
  ('NA','AZ-US'), ('NA','AZ-CA'), ('FE','AZ-AU')
];

WITH surowe AS (
  -- Co realnie u nas wyladowalo.
  --
  -- ⚠️ EMPTY LICZY SIE JAKO POKRYCIE. Amazon wygenerowal raport i nie bylo w nim nic —
  -- to znaczy, ze patrzymy i jest czysto, a nie ze jestesmy slepi. Traktowanie pustki
  -- jak braku to dokladnie ten sam blad, przed ktorym ten check ma chronic: 2026-09-01
  -- zamowilismy opinie dla AZ-BE/NL/PL/SE, Amazon oddal puste (potwierdzone krzyzowo
  -- w zdrowiu konta: 0-2 negatywy) — a check pokazywal "NIGDY NIE POBRANE".
  --
  -- status IS NULL AND contentBytes > 0 to wiersze sprzed dodania kolumny status (2026-08-31).
  -- Maja tresc, wiec sa prawdziwym pokryciem; bez tego warunku check krzyczalby
  -- "NIGDY NIE POBRANE" na dane, ktore realnie mamy — czyli uczylby ludzi ignorowac alarm.
  SELECT reportType                                             AS raport,
         market                                                 AS etykieta,
         DATE(fetchedOnUtc)                                     AS dzien,
         status IN ('LANDED', 'EMPTY')
           OR (status IS NULL AND contentBytes > 0)             AS udane,
         status = 'FAILED'                                      AS blad
  FROM `rd-basenv.amazon_raw.reports`
),

-- Raport zamawiany REGIONALNIE ma etykiete 'EU'/'NA'/'FE' i zawiera wiersze ze WSZYSTKICH
-- rynkow regionu — zmierzone 2026-08-31: jeden plik 'EU' = AZ-FR 3, AZ-DE 3, AZ-ES 1.
-- Bez rozwiniecia udane pobranie regionalne wyglada jak brak na kazdym rynku z osobna.
-- Etykiete regionu zostawiamy TAKZE bez zmian (UNION ALL), zeby stare wiersze 'NA'
-- nie zniknely razem z rozwinieciem.
rozwiniete AS (
  SELECT raport, etykieta AS rynek, dzien, udane, blad FROM surowe
  UNION ALL
  SELECT s.raport, r.rynek, s.dzien, s.udane, s.blad
  FROM surowe s
  JOIN UNNEST(regiony) r ON r.region = s.etykieta
),

mamy AS (
  SELECT raport, rynek,
         MAX(IF(udane, dzien, NULL)) AS ostatni,
         COUNTIF(udane)              AS udanych,
         COUNTIF(blad)               AS bledow
  FROM rozwiniete
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