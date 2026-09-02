-- Zestawy rabatowe Slowianina (kup 2 -> -10%): lejek + realna sprzedaz PRZEZ zestaw.
--
-- ⛔ DLACZEGO NIE PO `LastSyncedAt` (poprzednia wersja tego checku, 2026-09-01):
-- LastSyncedAt to "kiedy rura ostatnio dotknela zestawu", NIE "kiedy trafil na sklep".
-- Masowy re-sync 2026-09-01 14:56 przestemplowal 1017 z 1026 definicji naraz, przez co
-- regula "zamowienie liczy sie gdy CreatedOnUtc >= LastSyncedAt" zaczela zwracac 0 i bedzie
-- tak zwracac zawsze. Ten check NIE uzywa juz tej kolumny do pomiaru efektu.
--
-- ✅ METODA (zwalidowana 2026-09-02): rabat zestawowy nie zapisuje sie w zadnej kolumnie
-- rabatowej — DiscountAmount* i CustomerOrderItem.UnitPriceExclTax sa dla SN zerowe w 100%.
-- Rabat zostaje wylacznie jako obnizona OrderItemProfit.UnitSalesPriceNet. Wiec:
--   Rel = UnitSalesPriceNet (PLN netto) / ApiProducts.Price (EUR),  podzielone przez
--         MEDIANE tego stosunku z danego dnia (mediana zjada kurs EUR/PLN i VAT).
--   Rel ~ 1.00 = cena katalogowa,  Rel ~ 0.90 = rabat zestawowy 10%.
--
-- ⚠️ Sam Rel ~0.90 NIE wystarcza: 6,6% pozycji SN ma obnizke ~10% z innych mechanizmow
-- (koszyki, gdzie WSZYSTKIE pozycje maja ten sam wspolczynnik). Dyskryminatorem jest
-- SELEKTYWNOSC — rabat na parze zestawu przy pozostalych pozycjach w pelnej cenie.
-- Dlatego "pewne" liczymy tylko tam, gdzie w koszyku jest pozycja spoza pary z Rel ~1.00.
--
-- ⚠️ ApiProducts.Price to cena BIEZACA, wiec im starsze zamowienie, tym wiecej szumu.
-- Okno 30 dni jest swiadome.

DECLARE okno_dni INT64 DEFAULT 30;
DECLARE dol FLOAT64 DEFAULT 0.86;   -- rabat 10% z marginesem na zaokraglenia
DECLARE gora FLOAT64 DEFAULT 0.94;

WITH zam AS (
  SELECT Id, CreatedOnUtc, DATE(CreatedOnUtc) AS dzien
  FROM `polish-bookstores-group.BIData.azymut_CustomerOrder`
  WHERE IdBookstore LIKE 'SN-%' AND OrderStatusId <> 40
    AND CreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL okno_dni DAY)
),
poz AS (
  SELECT z.Id AS zamowienie, z.dzien, o.EAN,
         SAFE_DIVIDE(o.UnitSalesPriceNet, a.Price) AS stosunek
  FROM zam z
  JOIN `polish-bookstores-group.BIData.opi_OrderItemProfit` o ON o.CustomerOrderId = z.Id
  JOIN `polish-bookstores-group.BIData.selly_ApiProducts`   a ON a.Ean = o.EAN AND a.Price > 0
  WHERE o.UnitSalesPriceNet > 0
),
rel AS (   -- normalizacja mediana dnia zjada kurs EUR/PLN i VAT
  SELECT zamowienie, EAN,
         SAFE_DIVIDE(stosunek, PERCENTILE_CONT(stosunek, 0.5) OVER (PARTITION BY dzien)) AS Rel
  FROM poz
),
zestawy AS (
  SELECT d.Id, MIN(c.Ean) AS ean1, MAX(c.Ean) AS ean2
  FROM `polish-bookstores-group.BIData.selly_BundleDefinitions` d
  JOIN `polish-bookstores-group.BIData.selly_BundleComponents`  c ON c.BundleId = d.Id
  WHERE d.SellySetId IS NOT NULL AND d.Visible
  GROUP BY d.Id HAVING COUNT(*) = 2
),
trafienia AS (
  SELECT s.Id AS zestaw, r1.zamowienie,
         r1.Rel BETWEEN dol AND gora AND r2.Rel BETWEEN dol AND gora AS para_z_rabatem,
         -- czy w koszyku jest cokolwiek spoza pary w pelnej cenie (dyskryminator)
         EXISTS (SELECT 1 FROM rel x WHERE x.zamowienie = r1.zamowienie
                   AND x.EAN NOT IN (s.ean1, s.ean2) AND x.Rel > 0.97) AS kontrast
  FROM zestawy s
  JOIN rel r1 ON r1.EAN = s.ean1
  JOIN rel r2 ON r2.EAN = s.ean2 AND r2.zamowienie = r1.zamowienie
)

SELECT '1. LEJEK' AS Sekcja,
       FORMAT('%d definicji / %d z SellySetId / %d Visible=1',
              (SELECT COUNT(*) FROM `polish-bookstores-group.BIData.selly_BundleDefinitions`),
              (SELECT COUNTIF(SellySetId IS NOT NULL) FROM `polish-bookstores-group.BIData.selly_BundleDefinitions`),
              (SELECT COUNTIF(Visible) FROM `polish-bookstores-group.BIData.selly_BundleDefinitions`)) AS Wartosc,
       'z naszej bazy — NIE dowod, ze dziala w sklepie (brak price>0/visible z API Selly)' AS Uwaga
UNION ALL
SELECT '2. SPRZEDANE PRZEZ ZESTAW (pewne)',
       FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw)),
       FORMAT('para z rabatem + reszta koszyka w pelnej cenie, okno %d dni', okno_dni)
FROM trafienia WHERE para_z_rabatem AND kontrast
UNION ALL
SELECT '3. SPRZEDANE PRZEZ ZESTAW (bez kontrastu)',
       FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw)),
       'para z rabatem, ale koszyk = sama para → moze byc rabat ogolnosklepowy'
FROM trafienia WHERE para_z_rabatem AND NOT kontrast
UNION ALL
SELECT '4. PARA W KOSZYKU, ALE W PELNEJ CENIE',
       FORMAT('%d zamowien / %d zestawow', COUNT(DISTINCT zamowienie), COUNT(DISTINCT zestaw)),
       'klient zlozyl komplet sam — blok zestawu nie zadzialal albo go zignorowal'
FROM trafienia WHERE NOT para_z_rabatem
ORDER BY Sekcja;
