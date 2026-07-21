---
name: businesscheck
description: Odpalanie i pisanie checków biznesowych na BigQuery (repo businesschecks.v4) — gdy padnie „odpal check", „ile straciliśmy", „sprawdź stratne / marże / buy box", „dodaj check", albo gdy trzeba coś policzyć na danych z BIData/opi/ofi. Zawiera pułapki BigQuery i zasady kosztowe, które kosztowały już realne godziny.
---

# Business check

Check = **jeden plik SQL** w `sql/reports/` (raportowe) albo `sql/diagnostic/` (drążenie).
Uruchamiany runnerem, który liczy koszt PRZED wykonaniem.

```bash
cd ~/RiderProjects/businesschecks.v4
python3 -m runner.run_check --check <nazwa>                    # policz i pokaż
python3 -m runner.run_check --check <nazwa> --dry-run          # sam koszt skanu
python3 -m runner.run_check --check <nazwa> --send U03787T2DTR # + Slack DM Wojtka
```

## Dane

`polish-bookstores-group.BIData` @ **europe-west3** — mirror SQL Servera, odświeżany
Cloud Run Jobem co 8 h (`ofi_PriceOffer` raz dziennie).

| Tabela | Klucz | Uwagi |
|---|---|---|
| `opi_OrderProfit` | `CustomerOrderId` | partycja po `OrderCreatedOnUtc` — **filtruj po niej**, wtedy skan ~0 |
| `opi_OrderItemProfit` | `Id` | pozycje; `EAN`, `ItemProfit`, `UnitSalesPriceNet` |
| `opi_ShippingCost` | `CustomerOrderId` | `fShippingCostTotal` vs `ShippingCostTotal_EstimatedPreShipments` |
| `opi_OrderProfitTag` | `Id` | **tabela PRZYCZYN** — czemu zamówienie poszło źle |
| `ofi_PriceOffer` | `Id` | 14,7 mln wierszy; `Reason` = 79% objętości |
| `azymut_BookstoreProductPA` | `EAN` | stany, ceny, prognozy |

Joinuje się natywnie z `amazon_catalog` i `AwsMarketPlace` (ten sam region).

## Filtry obowiązkowe

```sql
AND OrderStatusId <> 40      -- 40 = anulowane, ZAWSZE wykluczaj
AND IsDoneCalculating        -- profit domknięty; bez tego liczysz niedoliczone zamówienia
```

## Zasady kosztowe

1. **Zawsze `--dry-run` przed pierwszym uruchomieniem nowego checku.** Runner i tak robi
   dry-run wewnętrznie i przerywa powyżej 20 GB, ale koszt trzeba zobaczyć świadomie.
2. **Nigdy `SELECT *` wprost na dużej tabeli.** Runner to blokuje. BigQuery jest kolumnowy:
   na `ofi_PriceOffer` gwiazdka to **14,53 GB**, pięć konkretnych kolumn — **0,85 GB**.
   Nie rozbijaj tabel, żeby odciąć grube kolumny; po prostu ich nie wybieraj.
3. **Filtruj po kolumnie partycjonującej**, gdy tabela ją ma. Dobowy check na
   `opi_OrderProfit` kosztuje 0,000 GB.

## Pułapki BigQuery (każda kosztowała już czas)

- **`bq` krztusi się SQL-em zaczynającym się od `--`** — komentarz bierze za flagę i wpada
  w `RecursionError`. Runner podaje zapytanie przez stdin; jeśli wołasz `bq` ręcznie, użyj
  `bq query ... < plik.sql`.
- **`LIMIT` nie przyjmuje zmiennej** („expects an integer literal"). Zamiast tego:
  `QUALIFY ROW_NUMBER() OVER (ORDER BY x) <= zmienna`.
- **`MERGE` nie przyjmuje podzapytania w warunku złączenia** („Unsupported subquery with
  table in join predicate"). Policz wartość osobno i wstaw jako literał.
- **`OurOffer` w `AmazonPriceLatest` to TABLICA**, nie rekord → `UNNEST`.
  I złączenie musi iść po **`(ASIN, MarketplaceID)`** — sam ASIN miesza rynki.
- **`sale_test_pushed.market` już zawiera prefiks** (`AZ-NL`). Doklejenie `AZ-` daje
  `AZ-AZ-NL` i **ciche wyzerowanie wszystkich złączeń** — wynik wygląda jak „brak sprzedaży".

## Gdy wynik jest podejrzanie okrągły

Same zera albo wszystko `NULL` to prawie zawsze **złączenie w próżnię**, nie prawda o biznesie.
Zanim ogłosisz wniosek: sprawdź, czy wartości kluczy po obu stronach naprawdę wyglądają
tak samo (patrz pułapka z prefiksem wyżej).

## Pisząc nowy check

- **Próg dobierz na danych, nie z sufitu.** Najpierw diagnostyka na tygodniu — rozkład,
  rozbicie, udziały — dopiero potem próg do checku dobowego. Tak powstał próg istotności
  w `stratne-daily` (`sql/diagnostic/stratne-inne-rozklad.sql`).
- **Klasyfikacja przyczyn w SQL, nie w prompcie.** Te same progi za każdym razem = wyniki
  porównywalne między dniami. Model wchodzi dopiero przy eskalacji.
- **Parametry na górze** jako `DECLARE`, komentarze po polsku.
- Po zmierzeniu czegoś istotnego → zapisz ustalenie skillem **`wniosek`**. Liczba się
  odtworzy, interpretacja nie.
