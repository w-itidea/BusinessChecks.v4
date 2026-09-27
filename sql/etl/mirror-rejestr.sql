-- CHECK: czy mirror odswieza WSZYSTKO, co obiecal odswiezac.
-- @opis Alarm, gdy tabela z rejestru ETL nie istnieje w BigQuery albo stoi dłużej niż jej próg — odzywa się też, gdy w mirrorze pojawi się tabela, której nikt nie zgłosił do rejestru.
-- @cisza-gdy-pusto
--
-- 🔴 PO CO TO JEST — historia, ktora sie powtorzyla trzy razy:
--   * `ofi_PriceOffer` stal w mirrorze od 2026-07-21, bo trigger mial zle `args`.
--   * `azymut_produkty_azymut` i `_platon` staly od 2026-09-10, bo commit 96860a0 dodal je do
--     `tables.json`, ale nie do `job.yaml` — a do tego kryl sie bug, przez ktory tabela bez
--     watermarku dawala sie zsynchronizowac TYLKO raz.
--   * `azymut_ShipmentMethod` i `ShipmentMethodPrice` sa w rejestrze od tygodni i NIE ISTNIEJA
--     w BQ w ogole.
-- Wszystkie trzy przypadki objawialy sie IDENTYCZNIE: job konczyl sie exit(0), trigger byl
-- ENABLED, podsumowanie wygladalo dobrze. Zaden nie zostal wykryty przez alarm — tylko
-- przypadkiem, przy innej pracy. Pelna lista wpadek: etl/README.md, sekcja "Edukacja bledow".
--
-- ⚠️ CZYM SIE ROZNI OD `mirror-health.sql`: ten drugi pyta o WIEK DANYCH w kluczowych tabelach
-- (MAX kolumny czasu) i o duplikaty klucza — dokladnie, ale tylko dla DZIESIECIU tabel
-- wypisanych w nim z nazwy. Ten check pyta o COS INNEGO: czy ETL w ogole dotknal tabeli,
-- i obejmuje KAZDA pozycje rejestru automatycznie. Lista, ktora trzeba pamietac aktualizowac,
-- jest tym samym rodzajem dziury, ktory mamy tu zamykac — dlatego jej tu nie ma.
--
-- Zrodlo prawdy: `BIData.etl_rejestr` — odwzorowanie `etl/tables.json` wystawiane do BQ przy
-- KAZDYM przebiegu `etl/sync.py` (funkcja zapisz_rejestr). Prog per tabela: pole
-- `prog_wieku_dni` w rejestrze (9999 = swiadomie nie pilnujemy, np. baseline `fin_*`
-- z zamrozonego zrodla Optimy albo tabela ustawien ruszana recznie).

DECLARE prog_domyslny INT64 DEFAULT 2;   -- ETL chodzi co 8 h, wiec dwie doby to juz zastoj

WITH rejestr AS (
  SELECT target, zrodlo, watermark, IFNULL(prog_wieku_dni, prog_domyslny) AS prog_dni
  FROM `polish-bookstores-group.BIData.etl_rejestr`
),
w_bq AS (
  -- Tabele przesiadkowe ETL (`*_staging`) zyja tylko w trakcie przebiegu — nie sa danymi.
  -- `etl_rejestr` to metadane samego checku, nie mirror.
  SELECT table_id,
         DATE(TIMESTAMP_MILLIS(last_modified_time)) AS zmodyfikowano,
         DATE_DIFF(CURRENT_DATE(), DATE(TIMESTAMP_MILLIS(last_modified_time)), DAY) AS wiek_dni,
         row_count
  FROM `polish-bookstores-group.BIData.__TABLES__`
  WHERE NOT ENDS_WITH(table_id, '_staging')
    AND table_id NOT IN ('etl_rejestr')
)
SELECT * FROM (
  -- 1. Obiecana w rejestrze, a w BQ jej nie ma. Najgrozniejszy przypadek: zapytania nie
  --    "zwracaja starych danych", tylko wywalaja sie na nieistniejacej tabeli — albo, gorzej,
  --    ktos pisze widok, ktory nigdy nie zadzialal, i nie wie dlaczego.
  SELECT
    r.target                                        AS Tabela,
    '❌ NIE ISTNIEJE w BQ'                           AS Problem,
    CAST(NULL AS DATE)                              AS Zmodyfikowano,
    CAST(NULL AS INT64)                             AS Wiek_dni,
    CAST(NULL AS INT64)                             AS Wierszy,
    FORMAT('%s nigdy nie trafilo do BQ — dopisz --table do job.yaml albo zaloz trigger', r.zrodlo) AS Zrobic
  FROM rejestr r
  LEFT JOIN w_bq b ON b.table_id = r.target
  WHERE b.table_id IS NULL

  UNION ALL

  -- 2. Jest, ale ETL jej nie dotknal dluzej, niz na to pozwalamy.
  SELECT
    r.target,
    '⚠️ ZASTOJ',
    b.zmodyfikowano,
    b.wiek_dni,
    b.row_count,
    FORMAT('prog %d dni przekroczony — sprawdz args joba i czy sync tej tabeli nie pada cicho', r.prog_dni)
  FROM rejestr r
  JOIN w_bq b ON b.table_id = r.target
  WHERE b.wiek_dni > r.prog_dni

  UNION ALL

  -- 3. Jest w mirrorze, ale nie ma jej ani w rejestrze, ani na liscie znanych wyjatkow.
  --    Tabele dokladane innym kanalem niz ETL nie sa bledem — ale maja byc UDOKUMENTOWANE,
  --    bo inaczej nikt nie wie, skad sie biora i kto je odswieza.
  --
  -- ⚠️ Dlaczego lista wyjatkow, a nie "zglaszaj wszystko": trzy tabele spoza ETL istnieja
  -- legalnie i check wysylalby o nich wiadomosc KAZDEGO dnia. Alarm, ktory zawsze wyje,
  -- przestaje cokolwiek znaczyc — ta sama zasada, ktora w mirror-health.sql wylaczyla
  -- ofi_AmazonFeedProductSettings z progu zastoju. Nowa tabela spoza rejestru nadal sie
  -- odezwie, bo na tej liscie jej nie bedzie.
  SELECT
    b.table_id,
    'ℹ️ poza rejestrem ETL',
    b.zmodyfikowano,
    b.wiek_dni,
    b.row_count,
    'brak w etl/tables.json — dopisz albo udokumentuj, skad sie bierze'
  FROM w_bq b
  LEFT JOIN rejestr r ON r.target = b.table_id
  WHERE r.target IS NULL
    AND b.table_id NOT IN (
      -- statyczne kohorty testowe, zakladane raz pod konkretna analize i celowo zamrozone:
      'fosa_ab_cohort',           -- test A/B fosy BOL, 20 476 EAN, 2026-07
      'platon_wydobco_cohort',    -- 7 734 EAN wyd. obcojezycznych od Platona, 2026-08
      -- kolektor Cloudflare, zasilany wlasnym skryptem etl/cf_crawl.py (nie przez sync.py):
      'cf_crawl_daily'
    )
)
ORDER BY CASE Problem WHEN '❌ NIE ISTNIEJE w BQ' THEN 1 WHEN '⚠️ ZASTOJ' THEN 2 ELSE 3 END,
         Wiek_dni DESC
