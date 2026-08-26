-- CHECK: ekspozycja listy "wydawnictwa obcojezyczne" Platona (kohorta 7 734 EAN, kontakt: K. Grzybowska).
--
-- Kontekst 1 — korekta stanu. Supplier.QtyCorrection to plaski bufor bezpieczenstwa odejmowany
-- od stanu dostawcy. Dla Platona (224) wynosil -3; 2026-08-14 zmieniony na -1.
--
-- Kontekst 2 — ⚠️ ZMIANA FORMATU U DOSTAWCY, 2026-08-25. Do 24.08 Platon podawal stany w
-- KUBELKACH: w calej SupplierPA istnialy tylko wartosci 0/1/3/6/21/51, gdzie "3" znaczylo
-- realnie 3-5 szt. Dlatego plaski bufor -3 zerowal dwa dolne kubelki i wycinal ~75% jego oferty.
-- 25.08 format sie zmienil — pojawily sie wartosci 2,4,5,13,101,201 (34 463 epizody tego dnia,
-- potwierdzone w SupplierPA_History). Dzis stany wygladaja na REALNE, nie kubelkowane.
-- Konsekwencja: stara argumentacja "kubelek 3 = 3-5 szt" juz NIE obowiazuje. Dlatego ten check
-- grupuje po PRZEDZIALACH stanu, nie po kubelkach, i pilnuje liczby roznych wartosci w feedzie —
-- jesli spadnie do ~5, dostawca wrocil do kubelkowania i bufor znowu zacznie wycinac oferte.
--
-- Po co: regresja konfiguracji dostawcy jest niema — nic sie nie wywala, po prostu znikaja oferty.

DECLARE platon INT64 DEFAULT 224;

WITH stan AS (
  SELECT
    c.EAN,
    IFNULL(MAX(sp.iloscDostepna), 0)      AS stan_dostawcy,
    IFNULL(MAX(pa.fAll_StockQuantity), 0) AS nasz_stan,
    MAX(IF(c.SprInni IN ('>10','>20','>30','>40','>50','>80','>100','>150','>200','>300'), 1, 0)) AS ma_popyt
  FROM `polish-bookstores-group.BIData.platon_wydobco_cohort` c
  LEFT JOIN `polish-bookstores-group.BIData.azymut_SupplierPA` sp
         ON sp.EAN = c.EAN AND sp.SupplierId = platon
  LEFT JOIN `polish-bookstores-group.BIData.azymut_BookstoreProductPA` pa
         ON pa.EAN = c.EAN
  GROUP BY c.EAN
),
format_feedu AS (
  -- wartownik formatu: ~5 roznych wartosci = dostawca znowu kubelkuje (patrz naglowek)
  SELECT COUNT(DISTINCT iloscDostepna) AS roznych_wartosci
  FROM `polish-bookstores-group.BIData.azymut_SupplierPA`
  WHERE SupplierId = platon AND iloscDostepna > 0
)
SELECT
  CASE
    WHEN s.stan_dostawcy = 0 THEN '0. brak u Platona'
    WHEN s.stan_dostawcy = 1 THEN '1. dokladnie 1 szt (bufor je w calosci)'
    WHEN s.stan_dostawcy = 2 THEN '2. 2 szt'
    WHEN s.stan_dostawcy BETWEEN 3 AND 5   THEN '3. 3-5 szt'
    WHEN s.stan_dostawcy BETWEEN 6 AND 20  THEN '4. 6-20 szt'
    ELSE '5. 21+ szt'
  END                                                                   AS Stan_u_dostawcy,
  COUNT(*)                                                              AS Pozycji,
  COUNTIF(s.nasz_stan > 0)                                              AS Wystawiamy,
  ROUND(SAFE_DIVIDE(COUNTIF(s.nasz_stan > 0), COUNT(*)) * 100, 1)       AS Proc_wystawionych,
  COUNTIF(s.ma_popyt = 1)                                               AS Z_popytem,
  COUNTIF(s.ma_popyt = 1 AND s.nasz_stan = 0)                           AS Z_popytem_NIEwystawione,
  ANY_VALUE(f.roznych_wartosci)                                         AS Format_feedu_roznych_wartosci
FROM stan s
CROSS JOIN format_feedu f
GROUP BY Stan_u_dostawcy
ORDER BY Stan_u_dostawcy
