# Order Profit - Checklist

**Data:** ____-__-__
**Analizuje:** _______________
**Okres:** ostatnie ___ dni

---

## 1. Stratne zamowienia

Uruchom: `sql/diagnostic/weekly-losses.sql` (podmien [DAYS])

- [ ] Sprawdzono stratne zamowienia z okresu
- [ ] Liczba stratnych: ___

> result:
> (wklej top 5 najgorszych)

---

## 2. Analiza najgorszych zamowien

Dla kazdego stratnego zamowienia z kroku 1 (zacznij od najgorszego):

### Zamowienie: ___________

- [ ] Sprawdzono podstawowe dane (`sql/diagnostic/basic-order-info.sql`)
  - Profit: ___ PLN
  - Wartosc zamowienia: ___ PLN
  - Marketplace: ___

- [ ] Sprawdzono skladowe kosztow (`sql/diagnostic/cost-breakdown.sql`)
  - Koszty wysylki: ___ PLN
  - Koszty platnosci: ___ PLN
  - Koszty marketplace: ___ PLN
  - Koszty obslugi: ___ PLN

- [ ] Sprawdzono pozycje/produkty (`sql/diagnostic/item-analysis.sql`)
  - Ktore pozycje stratne: ___
  - Glowna przyczyna: [ ] cena zakupu | [ ] koszty posrednie | [ ] koszty wysylki

- [ ] Sprawdzono tagi problemow (`sql/diagnostic/order-tags.sql`)
  - Tagi: ___

> result:
> (krotki opis co znaleziono)

---

## 3. Problematyczne produkty

Uruchom: `sql/reports/problematic-products.sql` (podmien [DAYS])

- [ ] Sprawdzono produkty z powtarzajacymi sie stratami (min 3x)
- [ ] Liczba problematycznych EAN-ow: ___

> result:
> (top 5 najgorszych EAN-ow z przyczyna)

---

## 4. Estymacje vs rzeczywistosc

Uruchom: `sql/diagnostic/shipping-estimation-diff.sql`

- [ ] Sprawdzono roznice estymacji wysylki vs rzeczywistosc
- [ ] Zamowienia z roznica > 50%: ___

> result:

---

## 5. Koszty marketplace

Uruchom: `sql/diagnostic/marketplace-cost-analysis.sql`

- [ ] Sprawdzono zamowienia z kosztami marketplace > 20%
- [ ] Liczba anomalii: ___

> result:

---

## 6. Podsumowanie i akcje

- [ ] Zidentyfikowano glowne przyczyny strat
- [ ] Wypisano akcje do podjecia

**Glowne przyczyny:**
1. ___
2. ___
3. ___

**Akcje:**
- [ ] ___
- [ ] ___
- [ ] ___

---

**Status:** [ ] W trakcie | [ ] Zakonczone
**Zakonczono:** ____-__-__
