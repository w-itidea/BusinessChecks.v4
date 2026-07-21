# Wnioski (`runs/`)

Check odpowiada na pytanie „ile". Ten katalog odpowiada na „i co z tego" — bo to właśnie
ginie. Liczba zawsze się przeliczy; **interpretacja, decyzja i to, czego jeszcze nie wiemy,
nie odtworzy się z niczego.**

Dotąd wnioski żyły w transkrypcie rozmowy (kasowanym po ~30 dniach), w pojedynczej
wiadomości na Slacku albo w czyjejś głowie. Efekt był taki, że za dwa miesiące nikt nie
pamiętał, czy „stratne AZ-CA" liczono z `Profit_Actual` czy `Profit_ActualFull` — więc
liczyło się od nowa, trochę inaczej, i wyniki nie były porównywalne.

## Konwencja

Jeden plik = jedno ustalenie. Nazwa: `RRRR-MM-DD-temat.md`.

Sekcje (pomiń te, które nie mają treści — pusty nagłówek jest gorszy niż jego brak):

```markdown
# Tytuł — data

**Pytanie:** co chcieliśmy wiedzieć
**Zmierzone czym:** nazwa checku (żeby dało się powtórzyć) + okno danych
**Liczby:** tabela, nie proza
**Wniosek:** 2–4 zdania. Co z tego wynika.
**Decyzja:** co postanowiliśmy ZROBIĆ (albo świadomie nie robić) i dlaczego
**Zastrzeżenia:** czego ten pomiar NIE dowodzi
**Otwarte:** pytania bez odpowiedzi + do kogo poszły + gdzie czekamy na odpowiedź
**Ślady:** linki — ClickUp, wiadomość na Slacku, PR, plik SQL
```

## Zasady, które robią różnicę

1. **Zastrzeżenia są obowiązkowe.** Wniosek bez granic swojej ważności jest za pół roku
   cytowany jako pewnik. Najczęstsze u nas: krótkie okno, atrybucja korelacyjna,
   brak grupy kontrolnej.
2. **Odpowiedzi dopisujemy do tego samego pliku**, nie zakładamy nowego. Pytanie wysłane
   na Slacka i odpowiedź, która przyszła trzy dni później, to jedno ustalenie — rozdzielone
   są bezużyteczne.
3. **Liczba zawsze z nazwą checku.** Bez tego nie wiadomo, jak ją powtórzyć, i za miesiąc
   nikt nie odtworzy, czy filtr wykluczał anulowane.
4. **Decyzja „świadomie nie robimy" jest warta zapisu tak samo jak „robimy".** Inaczej
   ktoś (często ja) wróci za miesiąc z tym samym pomysłem jako świeżym.

## Indeks

| Data | Ustalenie | Status |
|---|---|---|
| 2026-07-21 | [Rozjazd wyceny wysyłki — ~44 tys. zł/mies.](2026-07-21-rozjazd-wyceny-wysylki.md) | ⏳ czeka na odpowiedź Artura |
| 2026-07-21 | [Test sale EU — Buy Box wrócił, sprzedaż nie](2026-07-21-sale-test-eu.md) | ✅ zamknięte, decyzja podjęta |
| 2026-07-21 | [Przyczyny strat wg tagów systemowych](2026-07-21-przyczyny-strat.md) | 🔵 do działania |
