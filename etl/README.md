# ETL — SQL Server → BigQuery

Zasila dataset **`polish-bookstores-group.BIData`** @ **`europe-west3`** (single-region, ten sam
co `amazon_catalog` i `AwsMarketPlace` — dzięki temu wszystko joinuje się natywnie i bez opłat
za transfer między regionami).

## Po co

Żeby checki i raporty nie wymagały VPN-a ani włączonego laptopa, a dane były dostępne z chmury
(Cloud Run, rutyny, konektor BigQuery w claude.ai). Dopóki `opi.*` żyło wyłącznie w SQL Serverze
za VPN-em, każdy automat musiał albo chodzić na Twoim komputerze, albo obchodzić brak danych —
np. scrapując własne wiadomości ze Slacka.

## Tabele

| Target w BQ | Źródło | PK | Watermark |
|---|---|---|---|
| `opi_OrderProfit` | `BIData.opi.OrderProfit` | `CustomerOrderId` | `LastUpdatedOnUtc` |
| `opi_OrderItemProfit` | `BIData.opi.OrderItemProfit` | `Id` | `LastUpdateOnUtc` |
| `opi_ShippingCost` | `BIData.opi.ShippingCost` | `CustomerOrderId` | `LastUpdatedOnUtc` |
| `ofi_PriceOffer` | `BIData.ofi.PriceOffer` | `Id` | `LastUpdatedOnUtc` |
| `azymut_BookstoreProductPA` | `azymut.dbo.BookstoreProductPA` | `EAN` | `LastModifiedOnUtc` |

Kolumny i klucz główny są **wykrywane z katalogu źródła** przy każdym przebiegu — dodanie kolumny
w SQL Serverze nie wymaga zmiany kodu. Konfiguracja (`tables.json`) trzyma tylko to, czego nie da
się wywnioskować: watermark, partycję, klastrowanie i wykluczenia.

## Czym różni się od poprzedniej wersji

Poprzedni ETL (`ItIdea.Amazon.Catalog/etl/priceoffer_sync.sh`) nigdy nie wystartował — `price_offer`
ma `lastModifiedTime` z **2026-07-16**, a `price_offer_staging` 233 tys. wierszy z tamtego wieczora,
czyli został puszczony raz, ręcznie. Poprawione:

1. **NDJSON zamiast TSV.** `Reason` i `Notes` zawierają znaki, które rozwalają TSV. Stary skrypt
   wycinał je `REPLACE`-ami — czyli zapisywał do BQ dane inne niż w źródle. JSON nie ma tego problemu.
2. **MERGE po prawdziwym PK (`Id`), nie po `(bookstore_id, our_ean)`.** Stary klucz nie jest unikalny:
   67 507 par ma duplikaty, dedup „najniższy `PriceMin`" wyrzucał 69 257 wierszy (0,47%).
   Wyrzucał je jednak **systematycznie** — oferty Prime (`_PR`) mają wyższy `PriceMin`, więc
   przegrywały dedup **zawsze**. Tabela `amazon_catalog.price_offer` nie zawiera więc ofert Prime.
3. **Bezpiecznik kosztowy.** Każde zapytanie idzie najpierw jako `--dry_run`; jeśli skan przekracza
   `MAX_SCAN_GB` (domyślnie 20 GB), przebieg jest przerywany zamiast zapłacić.
4. **Nakładka watermarku** (10 min) — MERGE jest idempotentny, więc powtórzenie wiersza jest
   nieszkodliwe, a zgubienie go na granicy sekundy już nie.
5. **Partition pruning w MERGE** — dotyka tylko partycji obecnych w delcie, nie całej tabeli.
6. **Jeden błąd nie zabija przebiegu** — tabele są niezależne, błąd jest raportowany i idzie dalej.

## Uruchomienie lokalne

```bash
cd ~/RiderProjects/businesschecks.v4
SQL_USER=claude_readonly SQL_PASS='...' python3 -m etl.sync --all
SQL_USER=... SQL_PASS=... python3 -m etl.sync --table opi_OrderProfit    # jedna tabela
python3 -m etl.sync --all --dry-run                                      # bez ruszania danych
```

Wymaga VPN wg-prog (lokalnie), `pymssql` i zalogowanego `bq`.

## Wdrożenie (Cloud Run Job, co 8h)

`etl/job.yaml` — wzorzec z `ItIdea.Supplier.Bots` (sidecar `cloudflared` → `sql.fkwt.pl`),
więc job nie potrzebuje VPN-a ani włączonego laptopa. Komendy deployu w nagłówku pliku.

**Przed pierwszym deployem trzeba potwierdzić dwie rzeczy** (obie wymagają uprawnień, których
automat nie ma):

1. Sekret z hasłem readonly do SQL Server — `job.yaml` zakłada
   `db-mssql-azymut-readonly-password`; jeśli nie istnieje, trzeba go założyć.
2. Service Account `supplier-bots@erp-production-438714` musi mieć `roles/bigquery.dataEditor`
   **na projekcie `polish-bookstores-group`** — to jest nadanie cross-project i łatwo je przeoczyć,
   bo job żyje w `erp-production-438714`, a pisze do innego projektu.

## Koszty

`bq load` jest darmowy. Płacisz za storage (grosze miesięcznie) i za **skanowane kolumny**.

BigQuery jest kolumnowy — koszt zależy od tego, co wybierzesz, a nie od rozmiaru tabeli.
Zmierzone na `ofi_PriceOffer` (14,77 mln wierszy):

| Zapytanie | Skan |
|---|---|
| `SELECT *` | **14,53 GB** |
| `SELECT Id, BookstoreId, OurEan, PriceMin, Price` | **0,85 GB** |
| `SELECT Reason` | 11,49 GB (79% objętości tabeli) |

Wniosek: **nie ma po co rozbijać tabeli, żeby odciąć grube kolumny** — wystarczy ich nie wybierać.
Rozważaliśmy wyniesienie `Reason` do osobnej tabeli; to byłby JOIN i drugi obiekt do utrzymania
w zamian za efekt, który storage kolumnowy daje za darmo. Odrzucone.

Dlatego `runner/run_check.py` **blokuje `SELECT *`** na dużych mirrorach — 17-krotna różnica
w koszcie bierze się z jednego znaku i nikt jej nie zauważy w code review.

Pozostały realny koszt to MERGE w delcie: `UPDATE SET` dotyka wszystkich kolumn, więc te 11,5 GB
`Reason` faktycznie przelatuje przy każdym przebiegu. `PriceOffer` jest gorąca — **8,3 mln z 14,8 mln
wierszy zmienia się w ciągu doby** — co daje ok. **26 zł/mies.** przy synchronizacji co 8 h.
To ~2% obecnego rachunku za BigQuery; świadomie nie optymalizowane dalej.

Bezpieczniki: `MAX_SCAN_GB` (domyślnie 20 GB) przerywa przebieg zamiast zapłacić, a każde zapytanie
idzie najpierw jako `--dry_run`.
