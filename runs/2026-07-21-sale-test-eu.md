# Test sale EU — Buy Box wrócił, sprzedaż nie — 2026-07-21

**Pytanie:** czy obniżki (sale na 2424 SKU, push 2026-07-17, 6 rynków) odzyskały sprzedaż?

**Zmierzone czym:** `buybox-sale-profitability`, kohorta `amazon_catalog.sale_test_pushed`
× `AwsMarketPlace.AmazonPriceLatest` (Buy Box) × `BIData.opi_*` (zysk), okno sale 4 doby
vs baseline 14 dni przed.

## Liczby

| Rynek | SKU | BB wygrane | BB win% | Śr. obniżka | Sztuk (4 doby) | Zysk |
|---|---|---|---|---|---|---|
| AZ-UK | 386 | 171 | 44,5% | 7,0% | 1 | 14,25 zł |
| AZ-ES | 48 | 18 | 43,9% | 15,0% | 0 | — |
| AZ-IT | 71 | 23 | 35,9% | 15,0% | 0 | — |
| AZ-NL | 1 243 | 377 | 30,5% | 4,7% | 0 | — |
| AZ-BE | 560 | 144 | 25,9% | 4,2% | 1 | 29,63 zł |
| AZ-FR | 116 | 14 | 12,5% | 13,9% | 0 | — |

**2 424 SKU · 747 odzyskanych Buy Boxów · 2 sprzedane sztuki w 4 doby.**

Baseline 14 dni przed obniżką: 7 sztuk. Po normalizacji na dobę: **0,5 szt./dzień przed,
0,5 szt./dzień po.** Zero zmiany.

## Wniosek

**Buy Box wrócił (31% kohorty), sprzedaż nie drgnęła.** Buy Box to prawo do sprzedaży,
nie popyt.

W handoffie z 2026-07-20 zapisano „Test wyszedł" — ale mierzono tam **wyłącznie wygrywanie
Buy Boxa**, nie sprzedaż. Przy pełnym pomiarze wniosek jest odwrotny.

Dane same to zapowiadały: w kohorcie „martwy stan na Amazonie" **70% pozycji miało znikomy
albo żaden salesrank**. To był problem zakupowy, nie cenowy — obniżka nie mogła go naprawić.

## Decyzja

- **NIE rozszerzamy sale na US/AU/CA** (następny krok z handoffu). Na tych danych byłoby to
  oddanie marży na towarze, którego nikt nie szuka.
- Dźwigni szukać w ekspansji **Prime/SFP na NL/BE/FR** (osobny temat) i po stronie zakupowej.
- Sale wygasa sam po 14 dniach — nie trzeba nic cofać.

## Zastrzeżenia

- **Okno 4 doby, 2 sztuki — to jest za mało na statystykę.** Ale efekt nie jest „mały",
  tylko żaden: przy 2 424 SKU na 6 rynkach brak choćby kilkunastu sztuk sam w sobie jest
  sygnałem.
- Atrybucja korelacyjna, **brak grupy kontrolnej** — nie wiadomo, ile z tych 2 sztuk
  sprzedałoby się i bez obniżki.
- Sprawdzone i wykluczone: to **nie jest** opóźnienie pipeline'u profitu. Każde zamówienie
  z 17–20.07 ma komplet pozycji w `opi_OrderItemProfit` (1015/1015, 1118/1118, 1263/1263).

## Ślady

- Check: `sql/reports/buybox-sale-profitability.sql`
- Kohorta: `polish-bookstores-group.amazon_catalog.sale_test_pushed`
- Pułapka przy liczeniu: kolumna `market` **już zawiera** prefiks (`AZ-NL`); doklejenie
  `AZ-` dawało `AZ-AZ-NL` i ciche wyzerowanie wszystkich złączeń — wynik wyglądał
  identycznie jak „brak sprzedaży". Warto pamiętać przy następnej analizie tej tabeli.
