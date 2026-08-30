# Spóźnione Amazon: małe pieniądze w objawie, realne w przepłatach AssignSupplier — 2026-08-28

**Pytanie:** kanał #zakupy-na-magazyn codziennie krzyczy „spóźnione / brak orderowalnego
dostawcy" — ile na tym realnie tracimy, czy mamy dostawcę i gdzie kupić najtaniej,
i który dostawca generuje najwięcej problemów (obiecany stan, który się nie ziścił)?

**Zmierzone czym:** `sql/diagnostic/amazon-spoznione-dostawcy.sql` (snapshot, okno 120 dni),
`sql/reports/dostawcy-przeplaty.sql` (tag 41, okno 60 dni), ad-hoc na `azymut_CustomerOrder`
(late dispatch 30 dni, wysłane, `OrderStatusId <> 40`, `NOT Deleted`).

## Liczby

**1. Spóźnione teraz (niewysłane po `ShipLatestDateUtc`) — snapshot 2026-08-28:**

| Rynek | Spóźnione | Wartość (waluta lokalna) |
|---|---|---|
| AZ-DE | 7 | ~219 |
| AZ-UK | 4 | ~99 |
| AZ-FR | 3 | ~62 |
| AZ-US / AZ-ES | 1 / 1 | ~93 |
| **Razem** | **16** | **~470** |

Z 18 EAN-ów na tych zamówieniach: **6 bez żadnego dostawcy ze stanem** (prawdziwy „brak
orderowalnego dostawcy"), 12 ma dostawcę — w tym zamówienie `139277168` (AZ-US, 77 h po
terminie) z **11 dostawcami ze stanem** — to nie problem sourcingu, tylko procesu.

**2. Late Dispatch Rate (wysłane po terminie / wysłane, 30 dni):** AZ-DE 0,14%, AZ-UK 0,13%,
AZ-FR 0,16%, reszta ≤0,52%. Próg kary Amazona: 4%. **Metryki konta są zdrowe.**

**3. Przepłaty AssignSupplier (tag 41, 60 dni): ~4,0 tys. PLN (~2 tys. PLN/mies.):**

| Kupiono u | Tańszy był | Zamówień | Przepłata PLN |
|---|---|---|---|
| Ateneum | Platon | 830 | 2 601 |
| Ateneum | MiZ | 224 | 977 |
| Ateneum | Liber | 79 | 133 |
| pozostałe pary | — | 148 | ~290 |

Note taga mówi wprost: *„AssignSupplier wybrał szybszego zamiast tańszego, **choć obaj
mieścili się w terminie**"* — to nie trade-off termin/cena, tylko decyzja algorytmu.

## Wniosek

Objaw z kanału (spóźnione zamówienia) to grosze i jest procesowo ogarnięty — LDR 30× poniżej
progu kary, wisi 16 sztuk. Realny, powtarzalny wyciek siedzi krok wcześniej, w wyborze
dostawcy: ~2 tys. PLN/mies. przepłat, z czego 65% to jeden wzorzec „Ateneum zamiast Platona".
Przyczyny źródłowej spóźnień („stan u dostawcy, który się nie ziścił") **nie da się policzyć
z obecnego mirrora** — `SupplierPA` jest nadpisywany (stan bieżący, bez historii), a tag 35
(WarehouseRequest do dostawcy) jest tworzony **wyłącznie dla Libri** (1 616 wpisów od 2026-02,
100% „do Libri").

## Decyzja

1. **Nie budujemy alertu na spóźnione Amazon** — sygnał już istnieje (raport na
   #zakupy-na-magazyn), pieniądze małe, metryki zdrowe. Świadomie odpuszczone.
2. **Do działania:** reguła w `AssignSupplier` — gdy obaj dostawcy mieszczą się w terminie,
   wybieraj tańszego (albo próg: przepłata > X PLN → tańszy). Kod poza tym repo (FKWT,
   `ITidea_WarehouseRequest_AssignSupplier`); temat pod kanał
   #zakupy-nowe-algorytmy-zakupowe-maria-wojtek-jedrzej-artur-supplier.
3. Check `dostawcy-przeplaty` zostaje w repo jako miernik: po zmianie algorytmu suma
   przepłat powinna spaść w okolice zera — to będzie dowód skuteczności.

## Zastrzeżenia

- Kwoty przepłat parsowane regexem z `Note` — mierzą to, co algorytm sam o sobie raportuje
  (delta cen katalogowych dostawców), nie zweryfikowany koszt faktury.
- Możliwe, że wybór droższego-szybszego bywa celowy (bufor ryzyka dostawcy). Tag twierdzi,
  że obaj mieścili się w terminie, ale „termin wg ETA" ≠ „termin dotrzymany" — patrz Otwarte.
- Snapshot 16 spóźnionych to stan z jednego dnia, nie średnia.
- LDR liczony z mirrora (`ShippedDateUtc` vs `ShipLatestDateUtc`), nie z panelu Seller Central —
  Amazon może liczyć odrobinę inaczej (np. strefy czasowe cutoffów).

## Otwarte

- **Ranking wiarygodności dostawców** (obiecany stan → nie dowieźli): wymaga mirrora
  `WarehouseRequest` (zamówienie → dostawca → czy zrealizował) — bez niego atrybucja
  spóźnienia do dostawcy istnieje tylko dla Libri (tag 35).
  → **2026-08-28, zbudowane (czeka na weryfikację):** tryb `append_log` w `etl/sync.py`
  (log przyrostowy bez MERGE — historia wersji zostaje, stan bieżący daje widok `_current`;
  duża/gorąca tabela, lekcja `ofi_PriceOffer`), wpis w `tables.json`, widok w
  `sql/etl/azymut-warehouserequest-current.sql`, szkielet pomiaru w
  `sql/reports/dostawcy-eta.sql`. **Nazwy kolumn zgadnięte** — źródło za VPN; przed deployem
  `python3 -m etl.sync --table azymut_WarehouseRequest --describe` i poprawka nazw.
- Czy ETA dostawców (DispatchDays w SupplierPA) jest wiarygodna per dostawca? Jeśli Platon
  systematycznie łamie własne ETA, „wybieraj tańszego" może zwiększyć spóźnienia — to trzeba
  zmierzyć PRZED zmianą AssignSupplier (na mirrorze WarehouseRequest).
- Dlaczego tag 35 tylko dla Libri — celowe (pilot?) czy niedokończone? Nikt nie zapytany.

## Ślady

- SQL: `sql/reports/dostawcy-przeplaty.sql`, `sql/diagnostic/amazon-spoznione-dostawcy.sql`
- Przykładowe zamówienia: przepłata — Note taga 41 z EAN 9788387313586 (Ateneum 21.38 vs
  Platon 21.00); spóźnione z 11 dostawcami — `139277168` (AZ-US); bez dostawcy — `888477114`,
  `890042119` (AZ-DE).
- Kontekst Slack: #zakupy-na-magazyn (raporty „Amazon — spóźnienia i zagrożenia" — uwaga:
  szły z tożsamości „Watchdog" przez błędne ID zamiast botem `ola`).
