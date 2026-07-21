# Rozjazd wyceny wysyłki — ~44 tys. zł/mies. — 2026-07-21

**Pytanie:** gonić straty czy utracone marże? Które z nich jest większe.

**Zmierzone czym:** `rozjazd-wyceny` i `rozjazd-wysylki-wzorce`, okno 7 dni,
`ShippingCostTotal_EstimatedPreShipments` vs `fShippingCostTotal`, zamówienia
z `OrderStatusId <> 40` i `IsDoneCalculating`.

## Liczby

| | Zamówień | Zysk netto | Towar ponad wycenę | Wysyłka ponad wycenę |
|---|---|---|---|---|
| stratne | 220 | −1 797 zł | +982 zł | +862 zł |
| **zyskowne** | 7 500 | +164 769 zł | +57 zł | **+9 350 zł** |

Rozjazd wysyłki: **10 212 zł/tydz. ≈ 44 200 zł/mies. ≈ 531 tys. zł/rok.**
Dla porównania wszystkie stratne zamówienia razem: ~7,8 tys. zł/mies.

### Gdzie siedzi (sortowane wg kwoty)

| Metoda | Zam. | Rozjazd | Wycena → realnie | Krotność |
|---|---|---|---|---|
| Royal Mail 48 Parcel Tracked | 1 472 | +2 747 zł | 17,78 → 19,64 | 1,10× |
| DHL Paket Germany | 1 460 | +2 358 zł | 15,98 → 17,59 | 1,10× |
| PostNL SIGN | 681 | +1 853 zł | 23,21 → 25,93 | 1,12× |
| PostNL UNTR | 745 | +1 847 zł | 18,02 → 20,50 | 1,14× |
| DHL Kleinpaket | 970 | +749 zł | 12,09 → 12,86 | 1,06× |
| **FedEx Unified IP PAK** | 10 | +539 zł | 25,55 → 79,43 | **3,11×** |
| FedEx Int Connect Plus | 17 | +493 zł | 73,38 → 102,40 | 1,40× |
| FedEx Unified IP | 19 | +450 zł | 59,77 → 83,44 | 1,40× |

## Wniosek

**Utracone marże, nie straty — 5,7× większe.** I to są dwa różne zjawiska:

Pięć metod o dużym wolumenie myli się **stale o 6–14% w tę samą stronę** — 94% pieniędzy.
Per zamówienie to 0,77–2,72 zł, dlatego nigdy tego nie zauważono. To kalibracja cennika,
nie awaria.

FedEx to osobna sprawa: 1,4×–3,11× to nie jest „za nisko", to jest liczone z czegoś innego
niż rzeczywistość. Mało pieniędzy (46 zam.), ale prawdziwy bug.

Rozjazd **kosztu towaru** praktycznie nie istnieje poza stratnymi (57 zł na 7 500 zamówień
vs 982 zł na 220) — zjawisko ogonowe, nie systemowe. Nie ma sensu go ścigać.

Straty są w całości wyjaśnione rozjazdem: 982 + 862 = 1 844 zł przy 1 797 zł straty.
Zamówienie stratne to po prostu takie, w którym rozjazd przekroczył marżę — nie ma tam
osobnej patologii do odkrycia.

## Decyzja

- **Nie polujemy na stratne zamówienia.** To ogon tego samego rozkładu; naprawa przyczyny
  załatwia jedno i drugie.
- **Nie zmieniamy cennika, dopóki Artur nie odpowie**, czy 6–14% to świadomy margines,
  czy nieaktualne stawki. Zmiana w ciemno psuje `PriceMin` na wszystkich rynkach.

## Zastrzeżenia

- To różnica estymacja vs rzeczywistość, **nie „pieniądze do odzyskania"**. Część rozjazdu
  może być świadomie zaszyta w konserwatywnej wycenie — stąd pytanie do Artura, nie wniosek.
- Okno 7 dni. Sezonowość (dopłaty paliwowe, szczyt świąteczny) nieuwzględniona.
- FedEx: 46 zamówień to mało; kierunek pewny, wielkość efektu — nie.

## Dlaczego to ważniejsze, niż wygląda

`PriceMin` liczy się z **tego samego łańcucha estymacji** (`DefaultShippingCharge` w
`PriceOffer.Reason`). Jeśli wycena myli się systematycznie w dół o 6–14%, to ceny minimalne
na wszystkich rynkach są za niskie mniej więcej o tyle samo. Stawka jest więc dużo wyższa
niż 44 tys. zł/mies. na kosztach.

## Otwarte

Wysłane do **Artura** (Slack DM, zaplanowane na 2026-07-22 07:21, ID `Dr0BJXNYR717`):

1. Skąd bierze się `ShippingCostTotal_EstimatedPreShipments` — która tabela cennika,
   kiedy ostatnio aktualizowana?
2. Czy estymacja uwzględnia dopłatę paliwową i sezonowe, czy tylko stawkę bazową?
3. Czy 6–14% to świadomy margines, czy zdezaktualizowany cennik?
4. `874142114`: paczka **20-gramowa** wyceniona 4,35 zł, rozliczona jako Paket 17,65 —
   czy to wymuszony upgrade Prime→Paket (TagId 43)?
5. FedEx: dziury w `shp.FedExFuelSurcharge` (`X + NULL = NULL`)?
6. FedEx/GB: czy nie rozjeżdża się mapowanie regionu po Brexicie
   (`FedExCountryToRegion2` / `ShipmentMethodRegion`)?
7. `589561235` — 0,54 kg do GB za **81,54 zł** realnie: poprawna stawka FedEx czy błąd
   rozliczenia do reklamacji?

**⚠️ Odpowiedzi dopisać TUTAJ, nie zakładać nowego pliku.**

## Ślady

- Przykłady: `873368112`, `874142114`, `590233236`, `15320314` (kalibracja) ·
  `589561235`, `589450233`, `589286235`, `81850201` (FedEx)
- Checki: `sql/reports/rozjazd-wyceny.sql`, `sql/reports/rozjazd-wysylki-wzorce.sql`
- Powiązany task Artura: [869e2jrq4 — Fedex Rates API](https://app.clickup.com/t/869e2jrq4)
- Powiązany task Wojtka: [869e1ezwe — silnik estymacji kosztu wysyłki](https://app.clickup.com/t/869e1ezwe)
