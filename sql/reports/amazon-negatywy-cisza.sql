-- CHECK: czy dane o opiniach w ogole jeszcze plyna
-- @opis Alarm, gdy od dłuższego czasu nie przyszła ŻADNA negatywna opinia — brak negatywów bywa dobrą wiadomością, ale trwała cisza zwykle znaczy, że zepsuł się pipeline.
-- @cisza-gdy-pusto
--
-- 🔴 DLACZEGO TO OSOBNY CHECK, A NIE LOGIKA W RUNNERZE (uwaga Wojtka 2026-09-01):
-- „jak przychodzi raport a nie ma negatywow to chyba nie problem? dopiero jak przez jakis
-- czas nie bedzie — to problem".
-- Pusty wynik ma DWA znaczenia — „nie ma problemow" i „dane przestaly plywac" — a runner
-- ich nie rozrozni i nie powinien zgadywac. Rozroznia je pytanie zadane wprost w SQL:
-- nie „ile jest negatywow", tylko „ile dni minelo od ostatniego".
--
-- ⚠️ GET_SELLER_FEEDBACK_DATA oddaje WYLACZNIE oceny 1-3 (sprawdzone 2026-08-30 na surowych
-- plikach z 5 rynkow). Brak wierszy w tej tabeli NIE znaczy „klienci sa zadowoleni" —
-- znaczy „nie przyszla zadna zla opinia", co przy naszym wolumenie jest podejrzane.

DECLARE prog_dni INT64 DEFAULT 4;   -- tyle dni ciszy uznajemy za awarie, nie za spokoj

SELECT
  'opinie klientow (GET_SELLER_FEEDBACK_DATA)'                     AS Zrodlo,
  IFNULL(CAST(MAX(feedbackDate) AS STRING), 'NIGDY')               AS Ostatnia_opinia,
  IFNULL(DATE_DIFF(CURRENT_DATE(), MAX(feedbackDate), DAY), 9999)  AS Dni_ciszy,
  COUNT(*)                                                         AS Opinii_lacznie,
  FORMAT('cisza dluzsza niz %d dni — sprawdz pobieranie raportu', prog_dni) AS Co_zrobic
FROM `rd-basenv.account_health.ah_seller_feedback`
HAVING Dni_ciszy > prog_dni;
