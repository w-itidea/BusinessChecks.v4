-- location: EU
-- Interakcja z zestawami Slowianina (GA4) — POCZATEK lejka, ktorego check `slowianin-zestawy` nie widzi.
--
-- ⚠️ DLACZEGO OSOBNY CHECK: GA4 lezy w `neural-sol-390315.analytics_506030493`, region **EU**
-- (multi-region), a mirror BIData w **europe-west3**. BigQuery NIE joinuje miedzy tymi lokalizacjami
-- ("Not found: Dataset ... in location europe-west3"). Stad naglowek `-- location: EU`.
--
-- ⚠️ Wlasciwa property to 506030493 (slowianin.nl + .co.uk, swieze). Pozostale cztery
-- (251675915, 390480447, 391016505, 394319109) STANELY 8-18.08.2026 — wygaszane strumienie
-- z taska 869egk2j9. Nie mierzyc na nich niczego.
--
-- ⛔ CZEGO TU NIE MA — I DLACZEGO TO WAZNE:
-- GA4 nie ma eventu WYSWIETLENIA bloku zestawu. Mamy klikniecia (`nudge_click`, parametry
-- from_ean -> to_product_id), nie ekspozycje. Konwersji "ilu widzialo -> ilu kliknelo" NIE DA SIE
-- policzyc, dopoki Selly nie zacznie wysylac `nudge_view` (punkt 10 listy poprawek w CROSSSELL_BUNDLE.md).
--
-- ⛔ NIE MIERZYC odslonami stron `/zestaw-...`. Zestaw nie jest strona docelowa, tylko blokiem na
-- karcie skladnika — strony zestawow maja ~20 odslon/tydzien i to NIE znaczy, ze bloku nikt nie widzi.
-- Skan HTML 2026-09-02 potwierdzil: 49 z 50 kart z Visible=1 ma wyrenderowany blok zestawu.
-- Ta pomylka raz juz wyprodukowala falszywy wniosek "nikt ich nie widzi, problem to ekspozycja".

DECLARE okno_dni INT64 DEFAULT 7;

WITH ev AS (
  SELECT event_name, user_pseudo_id,
         (SELECT value.string_value FROM UNNEST(event_params) WHERE key='page_location') AS url
  FROM `neural-sol-390315.analytics_506030493.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
        FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL okno_dni DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)
SELECT '1. KLIKNIECIA W BLOK ZESTAWU (nudge_click)' AS Miara,
       FORMAT('%d klikniec / %d uzytkownikow', COUNTIF(event_name='nudge_click'),
              COUNT(DISTINCT IF(event_name='nudge_click', user_pseudo_id, NULL))) AS Wartosc,
       'jedyny twardy sygnal interakcji z zestawem' AS Uwaga
FROM ev
UNION ALL
SELECT '2. TLO: karty produktow', FORMAT('%d view_item / %d uzytkownikow',
       COUNTIF(event_name='view_item'), COUNT(DISTINCT IF(event_name='view_item', user_pseudo_id, NULL))),
       'na tych kartach blok zestawu sie renderuje (skan HTML 02.09: 49/50)' FROM ev
UNION ALL
SELECT '3. TLO: dodania do koszyka', FORMAT('%d add_to_cart', COUNTIF(event_name IN ('add_to_cart','fkwt_add_to_cart'))),
       'caly sklep, nie tylko zestawy' FROM ev
UNION ALL
SELECT '4. TLO: zakupy', FORMAT('%d purchase', COUNTIF(event_name='purchase')), 'caly sklep' FROM ev
UNION ALL
SELECT '5. Klikniec na 1000 odslon karty',
       FORMAT('%.2f', 1000 * SAFE_DIVIDE(COUNTIF(event_name='nudge_click'), COUNTIF(event_name='view_item'))),
       'proxy sily bloku — NIE konwersja (brak eventu wyswietlenia)' FROM ev
UNION ALL
SELECT '6. Odslony stron /zestaw- (kanal marginalny)',
       FORMAT('%d odslon', COUNTIF(event_name='page_view' AND REGEXP_CONTAINS(LOWER(url), r'zestaw'))),
       'NIE traktowac jako miary widocznosci bloku — patrz naglowek' FROM ev
ORDER BY Miara
