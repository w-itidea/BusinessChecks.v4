# BusinessChecks.v4

Prosty system checklistow biznesowych oparty na plikach Markdown.
Synchronizowany przez git, analizowany automatycznie przez Claude API.

## Jak uzywac

### Reczna analiza (konsola)

1. Skopiuj checklist do nowego pliku z data:
```bash
cp checklists/order-profit.md "runs/order-profit-2026-04-02.md"
```

2. Edytuj plik - odhaczaj kroki, wpisuj wyniki:
```bash
vim "runs/order-profit-2026-04-02.md"
```

3. Commituj i pushuj - drugi user widzi postep:
```bash
git add runs/ && git commit -m "order-profit check 2026-04-02: 3 straty wykryte"
git push
```

### Automatyczny analyzer (scheduler)

Analyzer uruchamia Claude API z checkami zdefiniowanymi w `analyzer/config.yaml`.
Wyniki laduja do `runs/auto/`.

Szczegoly: [analyzer/README.md](analyzer/README.md)

## Struktura

```
etl/              # mirror SQL Server -> BigQuery (dataset BIData @ europe-west3)
runner/           # wykonanie checku: SQL -> BigQuery -> tabelka -> Slack (bot ola)
sql/reports/      # checki (jeden plik = jeden check)
sql/diagnostic/   # SQL-e do recznego drazenia
checklists/       # szablony checklistow do kopiowania i odhaczania
knowledge/        # baza wiedzy - opisy systemow, architektura, przyklady
analyzer/         # config dla wersji z AI (na razie nieuzywany - patrz nizej)
runs/             # wyniki uruchomien
```

## Checki

| Check | Co liczy | Skan | Zastepuje |
|---|---|---|---|
| `stratne-daily` | stratne zamowienia z doby + sklasyfikowana przyczyna | 0,00 GB | `~/.claude/cron/stratne_slack.sh` |
| `stratne-wzorce` | agregat strat per przyczyna i rynek ("gdzie krwawimy systematycznie") | 0,00 GB | sekcja "Wzorce" z tego samego crona |
| `stratne-przyczyny` | PRZYCZYNY strat per tag systemowy (dlaczego, nie co) | 0,08 GB | — (nowy) |
| `buybox-sale-profitability` | Buy Box + zyskownosc kohorty sale EU | 0,78 GB | — (nowy) |

### Kubel vs przyczyna

`stratne-daily` mowi RODZAJ straty ("wysylka zjada marze"). `stratne-przyczyny` mowi POWOD,
bo siega do `opi_OrderProfitTag` — tabeli, w ktorej systemy same zapisuja co poszlo nie tak.

Czytaj obie kolumny osobno, bo opisuja rozne problemy:
- **suma straty** — wyciek systemowy (rozjazd estymacji kosztow: tagi 1/10/13/16, ~77% strat);
  duzo drobnych ubytkow po -6..-10 zl, naprawa poprawia wszystko po trochu
- **srednia na zamowienie** — przypadki rzadkie, ale ciezkie: wymiary zgadywane (tag 24, -32,58/zam.),
  awaryjny stock bez faktury (tag 40, -29,38), zalegacze >365 dni (tag 33, -17,04); kazdy da sie
  zablokowac punktowo

```bash
python3 -m runner.run_check --check stratne-daily              # policz i pokaz
python3 -m runner.run_check --check stratne-daily --send U03787T2DTR   # + Slack
python3 -m runner.run_check --check stratne-daily --dry-run    # sam koszt skanu
```

### Dlaczego bez AI

Stary cron odpalal `claude -p` z promptem, ktory prosil model o policzenie strat i opisanie
wzorcow. To znaczylo: koszt tokenow codziennie, wynik nieporownywalny miedzy dniami (model
za kazdym razem inaczej grupuje) i awaria, gdy laptop byl wylaczony albo VPN padl.

Tu klasyfikacja przyczyny jest w SQL — te same progi zawsze, wiec trendy sa porownywalne.
Model ma sens dopiero przy eskalacji (przekroczony prog CRITICAL), i to jest osobny krok.

⚠️ Klasyfikacja jest celowo prosta i to widac: wiekszosc zamowien wpada w kubel
`inne / zlozone` (36 z 42 w probce), choc wartosciowo dominuje `wysylka zjada marze`.
Kubly lapia wiec *pieniadze*, ale nie *liczbe przypadkow* — do dopracowania na wiekszej probie.

## Konwencje

- Checklist uzywa `- [ ]` / `- [x]` - standardowy markdown
- Wyniki wpisuj pod krokiem w bloku `> result:`
- SQL-e w `sql/` maja placeholdery `[ID]`, `[EAN]`, `[DAYS]` - podmien przed uruchomieniem
- Pliki w `runs/` nazywaj: `{checklist}-{data}.md`
