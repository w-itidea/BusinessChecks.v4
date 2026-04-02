# Order Profit - Definicje checkow automatycznych

Kazdy check to SQL + progi + akcja. Analyzer uruchamia SQL,
porownuje wyniki z progami, i generuje raport.

## CHECK: weekly-losses

**Cel:** Wykryj stratne zamowienia z ostatniego tygodnia
**SQL:** `sql/reports/weekly-losses.sql` z DAYS=7
**Progi:**
- CRITICAL: Profit < -50 PLN
- WARNING: Profit < -20 PLN
- INFO: Profit < 0

**Akcja na CRITICAL:**
- Sprawdz skladowe kosztow (cost-breakdown.sql)
- Sprawdz pozycje (item-analysis.sql)
- Sprawdz tagi (order-tags.sql)
- Wygeneruj podsumowanie z przyczyna i rekomendacja

## CHECK: problematic-products

**Cel:** Znajdz produkty ktore regularnie generuja straty
**SQL:** `sql/reports/problematic-products.sql` z DAYS=30
**Progi:**
- CRITICAL: SumaStrat < -200 PLN lub LiczbaStrat >= 10
- WARNING: LiczbaStrat >= 5

**Akcja na CRITICAL:**
- Sprawdz historie cen (price-history.sql)
- Sprawdz mapowanie wysylki (shipment-method-mapping.sql)
- Rekomenduj: zmiana ceny / wylaczenie oferty / zmiana dostawcy

## CHECK: shipping-estimation-diff

**Cel:** Wykryj duze roznice miedzy estymacja a rzeczywistymi kosztami wysylki
**SQL:** `sql/diagnostic/shipping-estimation-diff.sql` z DAYS=7
**Progi:**
- CRITICAL: roznica > 100%
- WARNING: roznica > 50%

**Akcja na CRITICAL:**
- Sprawdz metode wysylki dla problematycznych EAN-ow
- Sprawdz czy taryfa przewoznika sie zmienila
- Rekomenduj aktualizacje estymacji

## CHECK: marketplace-cost-anomalies

**Cel:** Wykryj zamowienia z anomalnie wysokimi kosztami marketplace
**SQL:** `sql/diagnostic/marketplace-cost-analysis.sql` z DAYS=7
**Progi:**
- CRITICAL: koszty marketplace > 25% wartosci zamowienia
- WARNING: koszty marketplace > 20%

**Akcja na CRITICAL:**
- Sprawdz referral fee vs closing fee breakdown
- Porownaj z norma dla danego marketplace
- Rekomenduj: zmiana kategorii / zmiana marketplace
