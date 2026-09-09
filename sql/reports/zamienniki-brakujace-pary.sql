-- CHECK: ten sam towar pod dwoma kodami, bez wpisanej pary zamiennikow
-- @opis Znajduje kartoteki, które dostawcy opisują jako ten sam produkt (wspólny ISBN-13 z feedu Ceneo), a które u nas nie mają pary w BookstoreProductReplacement. Bez pary stan rozjeżdża się między kodami: magazyn ma towar pod A, sprzedaż widzi zero pod B.
-- @cisza-gdy-pusto
--
-- SKAD TO SIE WZIELO (sesja 2026-09-09): 60 kodow lezalo na polkach WMS bez kartoteki
-- w katalogu. Zadnego z nich nigdy nie sprzedalismy — bez kartoteki nie da sie wystawic.
--
-- ✅ FAKT [2026-09-09]: dyskryminatorem NIE jest tytul.
--   Sprawdzone na 60 sierotach: dopasowanie po samym tytule dalo 135 kandydatow na 13 kodow
--   (np. fraza "Cayenne Turbo" trafia w 23 rozne produkty: inne skale, kolory, producentow).
--   Symbol producenta z Amazona (HWN38, JBK78) nie wystepuje w naszym katalogu ANI RAZU,
--   mimo 1 724 pozycji Hot Wheels. Dziala dopiero para: wspolny identyfikator + zgodnosc opisu.
--
-- ⚠️ fBookstoreProductEan = '-1' to SENTINEL "brak powiazania", nie EAN. Bez tego filtra
--   check zwraca setki fikcyjnych par.

DECLARE min_dostawcow INT64 DEFAULT 2;   -- ile niezaleznych feedow musi potwierdzic ten sam ISBN

WITH ceneo AS (
  SELECT
    fIsbnClear13                                  AS isbn13,
    fBookstoreProductEan                          AS nasz_ean,
    ANY_VALUE(name)                               AS nazwa,
    ANY_VALUE(autor)                              AS autor,
    ANY_VALUE(wydawnictwo)                        AS wydawnictwo,
    COUNT(DISTINCT SupplierId)                    AS dostawcow
  FROM `polish-bookstores-group.BIData.azymut_produkty_generic_ceneo`
  WHERE fIsbnClear13 IS NOT NULL AND LENGTH(fIsbnClear13) = 13
    AND fBookstoreProductEan IS NOT NULL
    AND fBookstoreProductEan NOT IN ('-1', '')          -- sentinel braku powiazania
  GROUP BY isbn13, nasz_ean
),
-- ten sam ISBN-13 wskazujacy na WIECEJ NIZ JEDEN nasz kod = duplikat kartoteki
duble AS (
  SELECT isbn13, COUNT(DISTINCT nasz_ean) AS ile_kodow
  FROM ceneo GROUP BY isbn13 HAVING COUNT(DISTINCT nasz_ean) > 1
),
pary AS (
  SELECT a.isbn13, a.nasz_ean AS ean_a, b.nasz_ean AS ean_b,
         a.nazwa, a.autor, a.wydawnictwo,
         LEAST(a.dostawcow, b.dostawcow) AS dostawcow
  FROM ceneo a
  JOIN ceneo b ON b.isbn13 = a.isbn13 AND b.nasz_ean > a.nasz_ean
  JOIN duble d ON d.isbn13 = a.isbn13
)
SELECT
  p.isbn13                                   AS ISBN13,
  p.ean_a                                    AS Kod_A,
  p.ean_b                                    AS Kod_B,
  SUBSTR(p.nazwa, 0, 60)                     AS Tytul,
  p.autor                                    AS Autor,
  p.wydawnictwo                              AS Wydawnictwo,
  p.dostawcow                                AS Potwierdzen_u_dostawcow,
  'wpisz pare do BookstoreProductReplacement (Type 0)' AS Co_zrobic
FROM pary p
-- zostawiamy tylko te, ktorych pary jeszcze NIE MA (w zadna strone)
LEFT JOIN `polish-bookstores-group.BIData.azymut_BookstoreProductReplacement` r
       ON (r.EAN = p.ean_a AND r.ReplacementEAN = p.ean_b)
       OR (r.EAN = p.ean_b AND r.ReplacementEAN = p.ean_a)
WHERE r.EAN IS NULL
  AND p.dostawcow >= min_dostawcow
ORDER BY p.dostawcow DESC, p.isbn13
LIMIT 200;
