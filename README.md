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
checklists/       # szablony checklistow do kopiowania i odhaczania
knowledge/        # baza wiedzy - opisy systemow, architektura, przyklady
analyzer/         # config i definicje checkow dla automatycznego schedulera
sql/              # gotowe SQL-e diagnostyczne i raportowe
runs/             # wyniki uruchomien (recznych i automatycznych)
```

## Konwencje

- Checklist uzywa `- [ ]` / `- [x]` - standardowy markdown
- Wyniki wpisuj pod krokiem w bloku `> result:`
- SQL-e w `sql/` maja placeholdery `[ID]`, `[EAN]`, `[DAYS]` - podmien przed uruchomieniem
- Pliki w `runs/` nazywaj: `{checklist}-{data}.md`
