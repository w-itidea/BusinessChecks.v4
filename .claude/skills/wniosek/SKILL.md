---
name: wniosek
description: Zapisanie ustalenia z analizy do runs/ w repo businesschecks.v4 — gdy padnie „zapisz wniosek", „zanotuj ustalenie", „nie zgub tego", albo gdy właśnie skończyła się analiza z konkretnym rezultatem i decyzją. Też: dopisanie odpowiedzi, która przyszła na wcześniej zadane pytanie.
---

# Wniosek

Check odpowiada „ile". `runs/` odpowiada **„i co z tego"** — bo to właśnie ginie.
Liczba zawsze się przeliczy; interpretacja, decyzja i to, czego jeszcze nie wiemy,
nie odtworzą się z niczego.

Plik: `runs/RRRR-MM-DD-temat.md`. Po zapisaniu **dopisz wiersz do indeksu** w `runs/README.md`.

## Szablon

```markdown
# Tytuł — RRRR-MM-DD

**Pytanie:** co chcieliśmy wiedzieć
**Zmierzone czym:** nazwa checku + okno danych (żeby dało się powtórzyć)

## Liczby
(tabela, nie proza)

## Wniosek
2–4 zdania. Co z tego wynika.

## Decyzja
Co postanowiliśmy ZROBIĆ — albo świadomie NIE robić — i dlaczego.

## Zastrzeżenia
Czego ten pomiar NIE dowodzi.

## Otwarte
Pytania bez odpowiedzi + do kogo poszły + gdzie czekamy.

## Ślady
Linki: ClickUp, wiadomość na Slacku, PR, plik SQL, numery przykładowych zamówień.
```

## Cztery zasady, bez których to nie działa

1. **Zastrzeżenia są obowiązkowe.** Wniosek bez granic swojej ważności jest za pół roku
   cytowany jako pewnik. Najczęstsze u nas: krótkie okno, atrybucja korelacyjna, brak
   grupy kontrolnej, „to różnica estymacji, nie pieniądze do odzyskania".

2. **Decyzja „świadomie nie robimy" jest warta zapisu tak samo jak „robimy".** Inaczej
   ktoś wróci za miesiąc z tym samym pomysłem jako świeżym. Zapisz też *dlaczego* odrzucone.

3. **Odpowiedzi dopisuj do ISTNIEJĄCEGO pliku, nie zakładaj nowego.** Pytanie wysłane na
   Slacka i odpowiedź sprzed trzech dni to jedno ustalenie — rozdzielone są bezużyteczne.
   Gdy przychodzi odpowiedź: znajdź plik z tym pytaniem w sekcji „Otwarte", wpisz odpowiedź
   pod nim, zaktualizuj status w indeksie.

4. **Każda liczba z nazwą checku.** Bez tego za miesiąc nikt nie odtworzy, czy filtr
   wykluczał anulowane i z której kolumny profitu liczono.

## Co jeszcze warto zapisać, choć się nie prosi

Pułapki techniczne, które kosztowały czas — „`market` już zawiera prefiks `AZ-`, doklejenie
drugiego cicho zeruje złączenia". To są rzeczy, których nikt nie notuje, bo w momencie
odkrycia wydają się oczywiste, a za dwa miesiące kosztują ten sam dzień jeszcze raz.

I **własne pomyłki w rozumowaniu**, jeśli miały konsekwencje: „zbudowałem mirror pod
»ile tracimy«, nie pod »dlaczego«, więc zabrakło tabeli tagów". To jest informacja
o tym, jak myśleliśmy — najdroższa do odtworzenia.

## Czego tu NIE zapisywać

- **Faktów o schemacie bazy** → `~/.claude/CLAUDE.md`
- **Automatyzacji cyklicznych** → `~/.claude/AUTOMATYZACJE.md`
- **Zadań do wykonania** → ClickUp (lista Artura `901219738011`, Wojtka `901219037435`),
  a w `runs/` tylko link
