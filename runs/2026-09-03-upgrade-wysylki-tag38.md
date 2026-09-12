# Upgrade wysyłki (tag 38) — cena dowiezienia obietnicy platformy — 2026-09-03

**Pytanie:** ile kosztuje wymuszony upgrade metody wysyłki „bo minął ShipLatestDateUtc"
i co go wywołuje. Punkt wyjścia: tag 38 w `stratne-przyczyny` (13 zam., −68,86 zł/tydz.).

**Zmierzone czym:** ad hoc na `opi_OrderProfitTag` × `opi_OrderProfit` × `opi_ShippingCost`
(okna 60 dni i szereg tygodniowy od czerwca) + kontrola niezależna na
`azymut_CustomerOrder` (PaidDateUtc → ShippedDateUtc). Pliki: `sql/diagnostic/upgrade-*.sql`.

## Liczby

### 1. Skala — wybuch od 3 sierpnia, trwa

| Tydzień (data zamówienia) | Zamówień | Upgrade | % |
|---|---|---|---|
| 2026-06-29 | 7 979 | 77 | 0,97% |
| 2026-07-13 | 7 985 | 94 | 1,18% |
| 2026-07-27 | 7 718 | 385 | 4,99% |
| **2026-08-03** | 8 221 | 1 133 | **13,78%** |
| 2026-08-10 | 8 621 | 1 821 | **21,12%** |
| 2026-08-17 | 9 413 | 1 246 | 13,24% |
| 2026-08-24 | 7 282 | 903 | 12,40% |

Sierpień: **5 864 zamówień = 14,8% całości**. Wszystkie rynki naraz (AZ-DE 16,2%,
AZ-FR 33,4%, AZ-ES 41,6%, AZ-IT 37,9%, CDIS 48,8%) — nie jeden kanał.

### 2. Magazyn NIE zwolnił (kontrola niezależna od tagów)

| Tydzień | Mediana płatność→wysyłka | p90 | % > 48 h |
|---|---|---|---|
| 2026-07-13 | 29 h | 65 h | 23,4% |
| 2026-08-03 | 32 h | 74 h | 26,9% |
| 2026-08-24 | 30 h | 78 h | 30,2% |

Płasko przez cały czerwiec–sierpień. Tag 34 (DispatchDate przekroczony) też płaski:
190 / 201 / 207 zamówień w VI / VII / VIII.

### 3. ❌ OBALONE (2026-09-03, tego samego dnia): „skróciła się obietnica"

Godziny od zamówienia do `ShipLatestDateUtc` (z Note tagu 38):

| Miesiąc | n | mediana | **p10** |
|---|---|---|---|
| 2026-05 | 301 | 58 h | 49 h |
| 2026-06 | 807 | 54 h | 48 h |
| 2026-07 | 373 | 56 h | 47 h |
| **2026-08** | 5 864 | 52 h | **30 h** |

Wyciągnąłem z tego wniosek, że skróciliśmy obietnicę. **Błąd metodyczny:** p10 liczony
**tylko na zamówieniach otagowanych**, a w sierpniu zmienił się skład tej populacji — reguła
zaczęła egzekwować termin platformy. Spadek p10 to przesunięcie składu, nie zmiana polityki.
Liczba zamówień z terminem PLATFORM prawie się nie ruszyła (VII: 29 081 → VIII: 33 705);
zmieniło się to, ile z nich reguła podniosła (400 → 5 943). Zamówienia z `ShipDeadlineSource
= DISPATCHDATE` (ok. 8 tys./mies.) nie dostały **ani jednego** upgrade'u.

### 4. Dopłata — kontrola: kraj docelowy + przedział wagowy, 60 dni

| Metoda po upgrade | Zam. | Koszt | Kontrfaktyk UNTR/MINI | Dopłata | Suma 60 d |
|---|---|---|---|---|---|
| PostNL SIGN | 1 046 | 22,93 | 17,12 | **+5,81** | +6 074 zł |
| DHL Paket Crossborder | 36 | 31,60 | 20,62 | +10,98 | +395 zł |
| PostNL TRCK | 31 | 28,58 | 18,42 | +10,16 | +315 zł |
| PostNL TRPL | 41 | 21,44 | 17,09 | +4,35 | +178 zł |

**~7 tys. zł / 60 dni ≈ 3,5 tys. zł/mies.** — i to **dolna granica**: dla kierunków
niemieckich (Kleinpaket, DP Großbrief, Paket Germany, łącznie ~1,9 tys. zamówień) nie ma
kontrfaktyku, bo UNTR/MINI w ogóle tam nie jeździ.

Dodatkowo: **~40% zamówień z tagiem 38 i tak jedzie UNTR/MINI** (25% w V, 40–42% w VI–VIII,
stabilnie) — tag mówi „odrzucono", ale finalnie wybrano tanią metodę.


### 5. Czy to wina dostawcy? NIE — kolejność jest odwrotna

Sierpień 2026, `BIData.dbo.OrderFulfilmentInfo2` (etapy realizacji, źródło niezależne od tagów):

| | Zam. | % wymagało zakupu | śr. h na towar | pakownia | margines do terminu | % wysłane po terminie | **% dostarczone po terminie** |
|---|---|---|---|---|---|---|---|
| UPGRADE | 5 943 | 66,9% | **25,5 h** | 16,8 h | −10 h | 20,8% | **0,1%** |
| BAZA | 36 115 | 74,8% | 36,4 h | 13,8 h | −36,5 h | 6,5% | 0,9% |

Zamówienia z upgrade'em **rzadziej** wymagały zakupu i czekały na towar **o 11 h krócej**.
Wolniejsza była za to nasza pakownia (16,8 vs 13,8 h).

Base rate per dostawca (tylko zamówienia wymagające zakupu, n ≥ 200):

| Dostawca | Zam. | % z upgrade'em | śr. h na towar |
|---|---|---|---|
| MiZ | 1 658 | 16,9% | 30,0 |
| Ateneum | 20 919 | 14,5% | 33,1 |
| Platon | 5 783 | 10,8% | 35,0 |
| Olesiejuk (DRESSLER) | 1 348 | 1,7% | 47,3 |
| Liber | 375 | 0,8% | 64,4 |
| Libri | 374 | 0,0% | — |

**Im szybszy dostawca, tym więcej upgrade'ów.** Dyskryminatorem jest ciasność terminu
platformy, nie wydajność dostawcy: do szybkich dostawców trafiają zamówienia z ostrym
terminem, do wolnych — z luźnym. Uczciwe zastrzeżenie na korzyść tezy „to dostawca":
dla tych 67%, które wymagają zakupu, czekanie na towar to i tak **największy pojedynczy blok
zegara** (25,5 h z ~43 h) — lead time jest realnym składnikiem, po prostu nie odróżnia
zamówień podniesionych od reszty.

### 6. Mechanizm robi to, po co go włączono

Dostawy po terminie: **0,1% wśród upgrade'owanych vs 0,9% w bazie** — 9× mniej.

## Wniosek

Upgrade nie jest przyczyną straty ani objawem awarii — jest **ceną dowiezienia obietnicy
platformy**, płaconą świadomie od sierpnia. Nie stoi za nim ani zwolniony magazyn
(mediana płatność→wysyłka płaska: 29–32 h przez całe lato), ani spóźniony dostawca
(upgrade'owane zamówienia czekają na towar **krócej**, a najwolniejsi dostawcy generują
ich najmniej).

Rachunek: **~3,5 tys. zł/mies. dopłaty do przewoźników za 9× niższy odsetek spóźnionych
dostaw** (0,1% vs 0,9%). To jedyna liczba, której brakowało pod tą decyzją.

## ODPOWIEDŹ (2026-09-03, Wojtek): to była nasza świadoma zmiana

**Skrócenie terminu włączyliśmy sami w sierpniu.** Nie ma incydentu, nie ma regresu,
nie ma pytania do IT. Dane układają się dokładnie w tę wersję: reguła `ChooseShippingMethod`
tagowała już w maju–lipcu (301 / 807 / 373 zam.), więc nie ona jest nowa — nowy jest
**krótszy termin** (p10 obietnicy 47 h → 30 h) przy niezmienionym wykonaniu (30–32 h).

To przesuwa całe pytanie: **3,5 tys. zł/mies. to nie wyciek, tylko cena zakupu szybszej
obietnicy.** Pytanie brzmi już nie „co się zepsuło", tylko „czy to się zwraca" — a tego
ten pomiar NIE rozstrzyga (patrz Zastrzeżenia).

## Decyzja

- Nie ruszamy reguły `ChooseShippingMethod` — działa poprawnie, robi dokładnie to, po co jest.
- **Zostawiamy krótszy termin.** Zmiana jest zamierzona; ten dokument dostarcza do niej
  brakujący cennik: ~3,5 tys. zł/mies. dopłaty do przewoźników przy 12–21% zamówień
  łapiących wymuszoną zmianę metody.
- Do sprawdzenia osobno (nie zrobione): czy szybsza obietnica zarobiła więcej niż te
  3,5 tys. zł — przez buy-box / konwersję na rynkach, gdzie udział upgrade'ów jest
  najwyższy (CDIS 49%, AZ-ES 42%, AZ-IT 38%, AZ-FR 33%).

## Zastrzeżenia

- **Pierwsze podejście do dopłaty było błędne** i dało wynik odwrotny: porównanie do średniej
  UNTR/MINI *na rynku* (bez kontroli kraju i wagi) sugerowało, że upgrade jest **tańszy**
  o 0,14 zł/zam. To mieszało gabaryty i kierunki (MINI = format listowy; Kleinpaket jeździ
  tylko do DE). Prawidłowa kontrola to **kraj docelowy × przedział wagowy**.
- Dopłata to koszt realny minus koszt hipotetyczny — nie pozycja z faktury przewoźnika.
- p10 obietnicy liczony **tylko na zamówieniach otagowanych** (te, które przekroczyły termin),
  więc pokazuje kierunek zmiany, nie rozkład w całej populacji.
- Wrzesień: 2 dni danych, pominięty.
- **Ten pomiar wycenia koszt zmiany, nie jej bilans.** Nie ma tu żadnej miary przychodu
  z szybszej obietnicy (buy-box, konwersja, mniej anulacji), więc nie wolno go cytować
  jako „zmiana kosztowała nas 3,5 tys. zł" bez dopisku „strona kosztowa".

## Otwarte

- ~~Co i kto zmienił w terminie wysyłki na przełomie lipca/sierpnia?~~ **Odpowiedziane:
  zmiana własna, włączona w sierpniu (Wojtek, 2026-09-03).**
- Czy szybsza obietnica zwraca 3,5 tys. zł/mies.? Uczciwe zmierzenie tego wymaga kontroli
  sezonowej i grupy odniesienia — bez tego porównanie „przed/po sierpniu" nic nie rozstrzygnie.
- Dlaczego 40% otagowanych i tak jedzie UNTR/MINI — reguła jest przeliczana ponownie,
  czy tag zostaje po nieaktualnej decyzji? To jedyny wątek, który nadal wygląda na usterkę.

## Ślady

- Raport źródłowy: `sql/reports/stratne-przyczyny.sql` (tam tag 38 widać jako 13 zam./tydz.)
- Powiązane: [rozjazd wyceny wysyłki](2026-07-21-rozjazd-wyceny-wysylki.md),
  [tag 35 Libri](2026-09-03-libri-tag35.md)
