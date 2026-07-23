# BOL — dataset `itideatestproject.bol_ew3` (europe-west3)

**Stan: 2026-07-23 — joiny cross-project DZIAŁAJĄ.** Szymon przeniósł dane BOL z lokalizacji
`EU` (multi-region) do **`europe-west3`**, czyli do tego samego regionu co
`polish-bookstores-group.BIData`, `amazon_catalog` i `AwsMarketPlace`. Zweryfikowane
zapytaniem — złączenie `bol_ew3.BolBuyBox` × `BIData.opi_OrderItemProfit` po `Ean` przechodzi
walidację (wcześniej: `Not found: Dataset ... in location europe-west3`).

## Dlaczego to ważne

Do tej pory pytanie „czy wygrany buy-box na BOL faktycznie zarobił" było niewykonalne — dane
BOL i profit żyły w różnych regionach, a BigQuery nie łączy przez regiony. Obchodziliśmy to
mirrorem `BIData.mka_BolBuyBox` (stan bieżący z SQL Servera, bez historii). Teraz **łączymy
bezpośrednio** żywe dane BOL z historią dzienną z profitem/kosztami/cenami minimalnymi.

## Tabele (wszystkie @ europe-west3, świeże, partycjonowane dziennie z historią)

| Tabela | Wierszy | Klucz / partycja | Zawiera |
|---|---|---|---|
| `BolBuyBox` | 5,0 mln | `Ean` / `LastCheckedUtc` | kto trzyma buy-box, `RetailerId`, `BestOfferPrice`, `FulfilmentMethod`, `HasOffer`, `MarketplaceId` |
| `our_offers` | 6,8 mln | `Ean` / `CapturedDateUtc` | nasze oferty: `OfferId`, `BundlePrice`, `StockAmount`, `FulfilmentType`, `OnHoldByRetailer` |
| `competing_offers` | 2,1 mln | `Ean` / `SnapshotDate` | oferty konkurencji: `RankPosition`, `RetailerId`, `Price`, `FulfilmentMethod`, `BestOffer` |
| `commissions` | 8,1 mln | `Ean` / `CapturedDateUtc` | prowizje + `ReductionsJson` (obniżki czasowe: MaximumPrice/CostReduction) |
| `BolPriceStarBoundary` | 3,6 mln | `Ean` / `LastCheckedUtc` | progi gwiazdek cenowych |
| `BolUnpublishedOffer` | 1,4 mln | `OfferId` / `CapturedDateUtc` | oferty niepublikowane (powody) |
| `product_ranks` | 96 tys. | `Ean` / `RankDate` | pozycje w wyszukiwarce, `Impressions`, `WasSponsored` |
| `sales_forecast` | 20 tys. | `OfferId` | prognoza sprzedaży (`TotalJson`, `PeriodsJson`) |
| `returns` | 1,2 tys. | `Ean` / `RegistrationDateTime` | zwroty: `MainReason`, `DetailedReason` |
| `offer_insights` | 127 tys. | `OfferId` | insighty ofert |
| `search_terms` | 224 | — | frazy wyszukiwania |

Każda tabela ma też widoki `_current` / `_fresh` (najświeższy snapshot bez sięgania po historię).

## Nasz RetailerId na BOL

`1834699` — tym filtrujemy „czy to nasza oferta" w `BolBuyBox.RetailerId` / `competing_offers.RetailerId`.

## Konsekwencja dla checków — DO ZROBIENIA

Check `bol-buybox` (i inne BOL) używa dziś mirrora `BIData.mka_BolBuyBox` (stan bieżący,
bez historii) + `BIData.azymut_BolOffersFirstOffer`. Po weryfikacji, że wszystkie potrzebne
kolumny są w `bol_ew3` (są — sprawdzone), należy:

1. **Przełączyć checki BOL na `itideatestproject.bol_ew3.BolBuyBox`** — zyskujemy historię
   dzienną (5 mln wierszy vs 112 tys. stanu bieżącego) i możliwość analizy trendu buy-boxa
   w czasie, nie tylko „teraz".
2. `our_offers` zastępuje `azymut_BolOffersFirstOffer` (ma `BundlePrice`, `StockAmount`).
3. Po przełączeniu — **usunąć z ETL** `mka_BolBuyBox` i `azymut_BolOffersFirstOffer`
   (`etl/tables.json`), bo staną się martwym mirrorem duplikującym dane.

Mapowanie kolumn (mirror → bol_ew3): `Ean`→`Ean`, `RetailerId`→`RetailerId`,
`BestOfferPrice`→`BestOfferPrice`, `FulfilmentMethod`→`FulfilmentMethod`, `HasOffer`→`HasOffer`,
`MarketplaceId`→`MarketplaceId`, `LastCheckedUtc`→`LastCheckedUtc` — 1:1, bez zmian w logice checku.

## Zasada na przyszłość: europe-west3 to nasz region

Trzy razy w lipcu uderzyliśmy w tę samą ścianę: dataset w `EU` (multi-region) nie joinuje się
z `europe-west3`. `AzymutCopy` (martwe od 2024), `bol` (żywe, przeniesione). **Każdy nowy
dataset, który ma się łączyć z profitem/katalogiem, zakładać w `europe-west3`**, nie w `EU`/`US`.
