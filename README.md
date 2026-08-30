# BusinessChecks

System kontroli biznesowych na danych w BigQuery. Jeden check = jeden plik SQL,
liczony w chmurze, wysyłany na Slacka. Bez VPN, bez włączonego laptopa, bez AI w pętli.

> **Skąd się wziął.** Wcześniej analizy żyły jako ~1000 jednorazowych plików SQL w
> `~/.claude/projects/ClaudeSQLs/` i sześć lokalnych cronów odpalających `claude -p` z
> promptem w środku. Każda analiza umierała po sesji; każdy cron wymagał włączonego laptopa,
> VPN-a i zalogowanego CLI, a wynik był nieporównywalny między dniami (model za każdym razem
> inaczej grupował). Ten projekt zamienia to na: **warstwę danych** (mirror do BigQuery),
> **deterministyczny runner** (SQL → tabelka → Slack) i **automat w chmurze** (Cloud Run,
> niezależny od laptopa).

---

## Architektura

```
SQL Server (za VPN)                    BigQuery @ europe-west3
  BIData.opi.*        ──ETL co 8h──▶     polish-bookstores-group.BIData.*
  BIData.ofi.*                              │
  azymut.dbo.*                              │  (joinuje się natywnie — ten sam region)
                                            ▼
  itideatestproject.bol_ew3.*  ────────▶  runner/run_check.py
  AwsMarketPlace.*             ────────▶     │  SQL → dry-run (koszt) → wykonaj → tabelka
  amazon_catalog.*             ────────▶     ▼
                                          Slack (bot ola)
```

- **ETL** (`etl/`) — mirror SQL Server → BQ, sidecar `cloudflared` (bez VPN). Cloud Run co 8 h.
- **Runner** (`runner/`) — wykonuje check: `--dry_run` liczy koszt, twardy limit skanu,
  blokada `SELECT *` na dużych tabelach, wysyłka botem `ola`.
- **Checki** (`sql/reports/`) — jeden plik SQL na check. Klasyfikacja w SQL, nie w prompcie.

---

## ✅ Co działa (stan 2026-07-23)

### Dane w BQ — `polish-bookstores-group.BIData` @ europe-west3

| Tabela | Wierszy | Źródło | Odświeżanie |
|---|---|---|---|
| `opi_OrderProfit` | 1,56 mln | `BIData.opi.OrderProfit` | co 8 h |
| `opi_OrderItemProfit` | 2,42 mln | `BIData.opi.OrderItemProfit` | co 8 h |
| `opi_ShippingCost` | 1,54 mln | `BIData.opi.ShippingCost` | co 8 h |
| `opi_OrderProfitTag` | 0,67 mln | `BIData.opi.OrderProfitTag` — **tabela przyczyn** | co 8 h |
| `ofi_PriceOffer` | 14,77 mln | `BIData.ofi.PriceOffer` | **raz dziennie** (5:40) — koszt |
| `ofi_AmazonFeedProductSettings` | 96 tys. | żywa tabela ustawień oferty | co 8 h |
| `azymut_BookstoreProductPA` | 1,31 mln | `azymut.dbo.BookstoreProductPA` | co 8 h |
| `azymut_SupplierPA` | 5,35 mln | `azymut.dbo.SupplierPA` — dostępność/cena per dostawca × EAN | co 8 h |
| `azymut_CustomerOrder` | 3,19 mln | `azymut.dbo.CustomerOrder` — **zanonimizowany** (patrz niżej) | co 8 h |
| `platon_wydobco_cohort` | 7,7 tys. | statyczna kohorta listy Platona | — |
| `fosa_ab_cohort` | 20 tys. | statyczna kohorta testu A/B | — |

#### Anonimizacja `azymut_CustomerOrder`

Mirror zamówień nie zawiera danych osobowych. `etl/sync.py` maskuje je **w SELECT wysyłanym do
SQL Servera**, a nie po pobraniu — dzięki temu PII nie trafia ani do pliku NDJSON na dysku, ani
do pamięci procesu. Tryby deklaruje się w `tables.json` w kluczu `mask`:

| Tryb | Działanie | Kolumny |
|---|---|---|
| `xxx` | wartość → `'xxx'`, `NULL` zostaje `NULL` | imię, nazwisko, firma (billing + shipping) |
| `email_domain` | `jan.kowalski@gmail.com` → `xxx@gmail.com` | `BillingEmail`, `ShippingEmail` |

Domena zostaje celowo — pozwala analizować udział marketplace'ów (`verkopen.bol.com`) bez
identyfikowania osoby. Twarde PII (karty, IP, telefony, ulice, NIP, pola tekstowe swobodne) jest
**wykluczone**, nie maskowane. Miasto/kod/kraj zostawione świadomie — potrzebne do analiz
kierunków wysyłki; bez nazwiska i ulicy nie wskazują osoby, ale to quasi-identyfikatory, więc nie
łączyć ich z zewnętrznymi zbiorami. Maska wskazująca nieistniejącą kolumnę **przerywa przebieg** —
lepiej głośny błąd niż ciche zsynchronizowanie PII po literówce.

### Automat w chmurze (`erp-production-438714`)

Konto serwisowe: `businesschecks@erp-production-438714.iam.gserviceaccount.com`.

| Trigger (europe-central2) | Harmonogram | Co robi |
|---|---|---|
| `bidata-bq-sync-trigger` | co 8 h (00/08/16:10) | ETL — 8 tabel `BIData`/`azymut` → BQ |
| `bidata-bq-sync-priceoffer` | 5:40 | ETL — sam `ofi_PriceOffer` (jego MERGE = 75% kosztu) |
| `businesschecks-daily-trigger` | 8:03 codziennie | raport stratnych (3 checki) → DM Wojtka |
| `businesschecks-bol-trigger` | pon+czw 8:07 | pilot BOL buy-box |
| `businesschecks-fosa-trigger` | pon 8:21 | test A/B fosa |
| `businesschecks-platon-trigger` | pon 8:27 | monitor listy Platon / wyd. obcojęzyczne (do 2026-11-04) |

> ⚠️ Cloud Scheduler **nie obsługuje `europe-north1`** — joby stoją w europe-north1,
> triggery muszą być w `europe-central2`.

### Checki

| Check | Co liczy | Skan | Uwaga |
|---|---|---|---|
| `stratne-daily` | stratne zamówienia z doby + przyczyna + próg istotności | 0,00 GB | zastępuje `stratne_slack.sh` |
| `stratne-wzorce` | agregat strat per przyczyna i rynek | 0,00 GB | — |
| `stratne-przyczyny` | przyczyny z `opi_OrderProfitTag` (dlaczego, nie co) | 0,08 GB | — |
| `rozjazd-wyceny` | rozjazd estymacji vs rzeczywistość na **wszystkich** zamówieniach | 0,06 GB | 91% pieniędzy w zyskownych |
| `rozjazd-wysylki-wzorce` | gdzie estymacja wysyłki myli się systematycznie | 0,09 GB | — |
| `bol-buybox` | pilot BOL buy-box + propagacja forced ceny | 0,07 GB | zastępuje `bol_buybox_slack.sh` |
| `fosa-ab` | test A/B fosa (+4% ExtraMargin), diff-in-diff per dobę | 0,15 GB | zastępuje `fosa_ab_slack.sh` |
| `buybox-sale-profitability` | Buy Box + zyskowność kohorty sale EU | 0,78 GB | — |
| `platon-wydobco-ekspozycja` | ile z oferty Platona realnie wystawiamy, wg przedziałów stanu | 0,18 GB | wartownik formatu feedu |
| `platon-wydobco-sprzedaz` | sprzedaż i realizacja listy vs **reszta katalogu** | 0,20 GB | kontrola sezonowa w wyniku |

Koszt całości: ~18 zł/mies. (storage grosze + skany; `bq load` darmowy).

### Wnioski z analiz — `runs/`

Trwały zapis ustaleń (co zmierzone, wniosek, **decyzja**, **zastrzeżenia**, otwarte pytania).
Patrz `runs/README.md`. Trzy pierwsze: rozjazd wyceny (~44 tys. zł/mies.), test sale EU
(747 Buy Boxów → 2 sztuki), przyczyny strat wg tagów.

---

## 🔵 Co do zrobienia

- [ ] **Mirror `azymut_WarehouseRequest` (append-log) — zweryfikować i wdrożyć.** Kod gotowy
      (tryb `append_log` w `etl/sync.py`, wpis w `tables.json`, widok
      `sql/etl/azymut-warehouserequest-current.sql`), ale **nazwy kolumn zgadnięte** — przed
      deployem na VPN: `python3 -m etl.sync --table azymut_WarehouseRequest --describe`,
      poprawić nazwy, pierwszy sync, założyć widok. Potem uzupełnić kolumny w
      `sql/reports/dostawcy-eta.sql` (pomiar ETA dostawców — warunek zmiany AssignSupplier,
      patrz `runs/2026-08-28-amazon-spoznione-i-przeplaty.md`).

- [x] ✅ **Checki BOL przełączone z mirrora na `itideatestproject.bol_ew3`** (2026-08-26).
      `bol-buybox` i `fosa-ab` czytają `BolBuyBox_current` / `our_offers_current`; oba mirrory
      (`mka_BolBuyBox`, `azymut_BolOffersFirstOffer`) usunięte z ETL i z BigQuery. Pokrycie
      zweryfikowane (BuyBox 1:1; 18,5 tys. „brakujących" ofert = phantomy azymuta). Patrz
      `docs/bol-ew3.md`.
- [ ] **Wyłączyć stare crony lokalne** — `stratne_slack.sh` i `bol_buybox_slack.sh` chodzą
      **równolegle** z chmurą do porównania. Wyłączyć po 2–3 zielonych przebiegach chmury.
      `fosa_ab_slack.sh` już wygasł sam (self-limit 5).
- [ ] **Rutyna claude.ai + konektor BigQuery** — żeby sprawdzać checki z przeglądarki i żeby
      rutyna „analiza stratnych" liczyła z BQ zamiast scrapować własne digesty ze Slacka.
      Blokada: autoryzacja konektora BigQuery na koncie. Patrz `docs/skille-i-rutyny.md`.
- [ ] **Dopracować klasyfikację `inne / zlozone`** — przy progu istotności kubeł jest już
      użyteczny, ale to nadal ~połowa pieniędzy bez dominującej przyczyny (patrz
      `runs/2026-07-21-przyczyny-strat.md`).
- [ ] **Zbieranie odpowiedzi ze Slacka** — gdy człowiek odpowie na pytanie automatu w wątku,
      zapisać odpowiedź (→ ClickUp jako zadanie, gdy implikuje zmianę). Wymaga `groups:history`
      dla bota `ola` albo rutyny czytającej jako Wojtek. Patrz `docs/skille-i-rutyny.md`.

---

## Struktura

```
etl/              # mirror SQL Server → BigQuery (sync.py, tables.json, job.yaml, Dockerfile)
runner/           # run_check.py — wykonanie checku → Slack; job.yaml (raport dzienny)
sql/reports/      # checki (jeden plik = jeden check)
sql/diagnostic/   # SQL-e do ręcznego drążenia (nie wysyłane)
runs/             # wnioski z analiz — trwały zapis ustaleń (patrz runs/README.md)
docs/             # architektura, bol-ew3, jak robić skille i rutyny
knowledge/        # baza wiedzy domenowej
.claude/skills/   # skille: businesscheck, wniosek
cloudbuild.yaml   # build obrazu ETL+runner → Artifact Registry
checklists/, analyzer/   # ⚠️ pozostałość po wersji "checklisty MD" — nieużywane
```

---

## Uruchomienie

```bash
cd ~/RiderProjects/businesschecks.v4

# check lokalnie
python3 -m runner.run_check --check stratne-daily              # policz i pokaż
python3 -m runner.run_check --check stratne-daily --send U03787T2DTR   # + Slack DM
python3 -m runner.run_check --check stratne-daily --dry-run    # sam koszt skanu

# ETL lokalnie (wymaga VPN + SQL_USER/SQL_PASS)
SQL_USER=claude_readonly SQL_PASS='...' python3 -m etl.sync --all
```

Szczegóły ETL: [`etl/README.md`](etl/README.md). Skille i rutyny: [`docs/skille-i-rutyny.md`](docs/skille-i-rutyny.md).

## Jak dodać check

1. Napisz SQL w `sql/reports/<nazwa>.sql`. **Filtry obowiązkowe:** `OrderStatusId <> 40`
   (anulowane), `IsDoneCalculating` (profit domknięty). Parametry na górze jako `DECLARE`.
2. **Próg dobierz na danych, nie z sufitu** — najpierw diagnostyka na tygodniu
   (`sql/diagnostic/`), potem próg do checku dobowego.
3. **Nigdy `SELECT *` na dużej tabeli** — runner to blokuje (na `ofi_PriceOffer` to 14,5 GB
   vs 0,85 GB). Wypisz kolumny.
4. Test: `python3 -m runner.run_check --check <nazwa> --dry-run` → potem bez `--dry-run`.
5. Automat: dorzuć trigger wskazujący na `businesschecks-daily` z override args (wzór w
   `runner/job.yaml`).

Pułapki BigQuery, filtry i zasady kosztowe: skill [`.claude/skills/businesscheck/SKILL.md`](.claude/skills/businesscheck/SKILL.md).
