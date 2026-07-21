# Przyczyny strat wg tagów systemowych — 2026-07-21

**Pytanie:** kubeł mówi RODZAJ straty („wysyłka zjada marżę"). Co mówi POWÓD?

**Zmierzone czym:** `stratne-przyczyny` (join do `opi_OrderProfitTag`), okno 7 dni,
238 stratnych zamówień, −1 932 zł.

## Liczby

| Tag | Zam. | Strata | **Śr./zam.** | Mechanizm |
|---|---|---|---|---|
| 1 | 83 | −523 zł | −6,30 | rozjazd kosztu wysyłki vs estymacja |
| 10 | 48 | −465 zł | −9,69 | rozjazd kosztu towaru |
| 16 | 45 | −448 zł | −9,95 | wycena 63,48 → realnie 82,37 |
| 33 | 16 | −273 zł | **−17,04** | towar kupiony >365 dni przed sprzedażą |
| 13 | 29 | −245 zł | −8,43 | rozjazd kosztu towaru |
| **40** | 6 | −176 zł | **−29,38** | stock z awaryjnego przyjęcia MiZ (bez faktury) |
| 21 | 11 | −163 zł | −14,81 | discount |
| 17 | 20 | −162 zł | −8,08 | kierunek (FI, CH) |
| **24** | 4 | −130 zł | **−32,58** | wymiary zgadywane — „Pewność 577,95%" |
| 43 | 24 | −98 zł | −4,10 | Prime→Paket: wycena 7,83 zł, realnie 17 zł |

## Wniosek

**Te dwie kolumny opisują różne problemy i trzeba je czytać osobno.**

Po **łącznej stracie** dominuje rozjazd estymacji (tagi 1, 10, 13, 16 = −1 680 z ~2 170 zł).
Wyciek systemowy: dużo drobnych ubytków po −6 do −10 zł. Naprawa poprawia wszystko po trochu.
→ ciąg dalszy w [rozjazd wyceny wysyłki](2026-07-21-rozjazd-wyceny-wysylki.md), gdzie okazało
się, że to samo zjawisko zjada 5,7× więcej na zamówieniach **zyskownych**.

Po **stracie na zamówienie** kolejność jest odwrotna: wymiary zgadywane (−32,58),
awaryjny stock MiZ (−29,38), zalegacze >365 dni (−17,04). Rzadkie, ciężkie, **każde
do zablokowania punktowo**.

Najmocniejszy pojedynczy wniosek: przy tagu 24 system **sam wie**, że wymiary są zmyślone —
zapisuje „Pewność 577,95%" — i mimo to sprzedaje po cenie policzonej z tych wymiarów.
To nie jest brak informacji, tylko **informacja niewykorzystana**. Dołożenie marży
bezpieczeństwa albo wstrzymanie oferty przy niskiej pewności wymiarów to zmiana jednego
warunku, nie projekt.

## Decyzja

- Do zrobienia (nie zrobione): reguła na produkty z guesstymowanymi wymiarami — marża
  bezpieczeństwa albo wstrzymanie oferty. **Najtańsza pozycja z całej listy.**
- Tagi 33 i 40 to sygnały procesowe (zalegacze, przyjęcia bez faktury), nie cenowe —
  do rozmowy z zakupami, nie do naprawy w cenniku.

## Zastrzeżenia

- Okno 7 dni. Tagi 24 i 40 mają po 4–6 zamówień — kierunek wiarygodny, wielkość efektu nie.
- Współwystępowanie ≠ przyczynowość: zamówienie może mieć kilka tagów naraz, a suma strat
  per tag je wtedy powiela. Do rankingu „który mechanizm boli", nie do sumowania.

## Ślady

- Check: `sql/reports/stratne-przyczyny.sql`, diagnostyka: `sql/diagnostic/stratne-tagi.sql`
- Słownik tagów: `~/.claude/ORDER_PROFIT_TAG_COMPLETE_GUIDE.md`
- Uwaga techniczna: `opi_OrderProfitTag` **nie było** w pierwszym projekcie ETL — mirror
  zbudowano pod „ile tracimy", nie pod „dlaczego". Dołożone 2026-07-21.
