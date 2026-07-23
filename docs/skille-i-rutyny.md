# Skille i rutyny — Claude Code (CLI) vs claude.ai (web)

Ten dokument tłumaczy, **gdzie co działa** i jak używać checków z przeglądarki, a nie tylko z konsoli.

## Najważniejsze rozróżnienie: dwa różne światy

| | Claude Code (CLI, ten terminal) | claude.ai (web / aplikacja) |
|---|---|---|
| Gdzie działa | Twój komputer | chmura Anthropic |
| Widzi lokalne pliki (`~/.claude`, repo) | ✅ tak | ❌ **nie** |
| Widzi bazę za VPN (`sqlcmd`, `gcloud`) | ✅ tak | ❌ **nie** |
| Widzi dane przez konektory MCP | ✅ (podpięte w CLI) | ✅ (podpięte na koncie) |
| Skille z `.claude/skills/` w repo | ✅ ładuje | ❌ **nie widzi** (to pliki lokalne) |
| Rutyny (`/schedule`, cron w chmurze) | tworzy je, ale biegną w chmurze | ✅ to jest ich dom |

**Konsekwencja, która rządzi wszystkim:** web nie ma dostępu do Twojego dysku ani do bazy
za VPN. Ma tylko to, co podepniesz jako **konektor MCP na koncie**. Dlatego żeby używać
checków przez web, dane muszą być w miejscu, które web widzi — czyli w **BigQuery**
(mamy konektor), a nie w SQL Serverze za VPN.

To jest cały powód, dla którego powstał ETL: przeniósł dane do BQ, żeby były dostępne
z chmury.

---

## A. Skille w Claude Code (CLI) — `.claude/skills/`

Skill to katalog z plikiem `SKILL.md`. Nagłówek YAML (`name`, `description`) mówi Claude'owi,
**kiedy** skill jest istotny; resztę czyta dopiero, gdy zadanie tego wymaga.

```
.claude/skills/
  businesscheck/SKILL.md   # jak odpalać i pisać checki + pułapki BigQuery
  wniosek/SKILL.md         # jak zapisać ustalenie do runs/
```

Minimalny szablon:

```markdown
---
name: nazwa-skilla
description: Kiedy się uruchamia — opisz wyzwalacz ("gdy padnie X", "gdy trzeba Y").
---

# Tytuł

Treść — instrukcje, które Claude ma wykonać zamiast domyślnego podejścia.
```

**Gdzie kłaść:**
- `<repo>/.claude/skills/` — skill jedzie z repo (dostaje go CLI *i* rutyna klonująca repo).
  To wybraliśmy dla `businesscheck` i `wniosek` — patrz niżej „skille dla rutyn".
- `~/.claude/skills/` — skill globalny, tylko dla Twojego CLI (web go nie zobaczy).

⚠️ **Web (claude.ai) NIE ładuje skilli z `.claude/skills/`** — to pliki lokalne. Jedyny
sposób, żeby wiedza domenowa trafiła do rutyny w chmurze, to umieścić ją w repo, które
rutyna klonuje (patrz sekcja B), albo w konektorze (dok w ClickUp/Notion).

---

## B. Rutyny w claude.ai (chmura) — `/schedule`

Rutyna to zaplanowany agent, który biegnie **w chmurze** na cron. Nie zależy od Twojego
laptopa. Tworzysz ją przez skill `/schedule` (w CLI albo na claude.ai) — ale biegnie w chmurze.

**Co rutyna ma do dyspozycji:**
- konektory MCP podpięte **na Twoim koncie** (nie w CLI): Slack, ClickUp, Drive, Gmail,
  Calendar — i **BigQuery, gdy go autoryzujesz**;
- repozytoria git, które jej wskażesz (klonuje je — tu wchodzą skille z repo);
- **nie ma**: VPN, `sqlcmd`, `gcloud`, lokalnych plików.

**Kadencja: minimum 1 godzina.** Rutyny nie chodzą częściej. Do porannych raportów bez
znaczenia; do rozmowy „na teraz" za wolno (wtedy Cloud Run, patrz sekcja D).

### Jak używać checków przez web — krok po kroku

1. **Autoryzuj konektor BigQuery na koncie:** `claude.ai/customize/connectors` → Google Cloud
   BigQuery → Connect → zaloguj kontem z dostępem do `polish-bookstores-group`
   (u nas: `jbrawo@gmail.com` — to na nim wiszą role; **nie** `wc@fkwt.pl`, bo tam brak dostępu).
   Bez tego kroku rutyna nie ma jak policzyć — patrz `../README.md` sekcja „Co do zrobienia".
2. **Sprawdź, że konektor wystawia narzędzia do zapytań** (nie tylko do logowania). W CLI:
   po autoryzacji `ToolSearch` na „bigquery query" pokaże realne narzędzia zamiast dwóch
   `authenticate`/`complete_authentication`.
3. **Utwórz rutynę** (`/schedule`): prompt typu „codziennie 8:00 policz z
   `polish-bookstores-group.BIData.opi_OrderProfit` stratne zamówienia z doby i wyślij mi
   na Slacka DM". Podłącz konektory Slack + BigQuery.
4. Rutyna liczy zapytaniem do BQ i wysyła — **bez laptopa, bez VPN**.

### ⚠️ Pułapka, którą już raz złapaliśmy

Rutyna założona z claude.ai **nie zna lokalnych zasad** (CLAUDE.md, tego repo). 2026-07-21
powstała rutyna „analiza stratnych", która **scrapowała własne digesty ze Slacka** zamiast
liczyć — bo nie miała dostępu do danych. Do tego założono ją **bez konektora Slack**, więc
cicho by nie robiła nic. Zakładając rutynę z weba: (a) sprawdź `mcp_connections`,
(b) każ jej raportować, że przebiegła, nawet gdy nie miała nic do roboty (rutyny umierają
po cichu), (c) dopisz ją do `~/.claude/AUTOMATYZACJE.md`.

---

## C. Skille dla rutyn — jak dać agentowi w chmurze wiedzę domenową

Rutyna klonuje repo, więc **skille w `<repo>/.claude/skills/` jadą z nią do chmury**.
To sposób, żeby agent w chmurze znał te same pułapki co CLI (region europe-west3, zakaz
`SELECT *`, filtry `OrderStatusId <> 40`, klucze tabel).

Wzór — nasze dwa skille:
- **`businesscheck`** — jak odpalać i pisać checki: mapa tabel `BIData`, filtry obowiązkowe,
  zasady kosztowe, pułapki BigQuery (`bq` krztusi się `--`, `LIMIT` nie bierze zmiennej,
  `MERGE` nie bierze podzapytania, `OurOffer` to tablica, prefiks `AZ-AZ-NL`).
- **`wniosek`** — jak zapisać ustalenie do `runs/`: wymuszone sekcje Decyzja i Zastrzeżenia.

⚠️ **Do potwierdzenia jednym testowym runem:** czy rutyna faktycznie ładuje skille z
`.claude/skills/` sklonowanego repo. Wygląda na to, że tak (rutyna ma `Skill` na liście
narzędzi), ale to założenie, nie fakt — zweryfikować przy pierwszej rutynie na tym repo.

---

## D. Kiedy rutyna nie wystarcza — Cloud Run

Rutyna ma limit 1 h i biegnie „prompt w chmurze" (niedeterministycznie). Gdy potrzeba
**deterministycznie, taniej, częściej** albo z dostępem do bazy za VPN — to jest robota dla
**Cloud Run Job** (jak nasz ETL i raport dzienny), nie dla rutyny:

| Chcę... | Mechanizm |
|---|---|
| raport rano z danych w BQ, na Slacka, bez laptopa | Cloud Run Job (jak `businesschecks-daily`) |
| to samo, ale sterowane promptem z przeglądarki | rutyna claude.ai + konektor BQ |
| sięgnąć do SQL Server za VPN z chmury | Cloud Run Job + sidecar `cloudflared` (jak ETL) |
| odpowiadać na pytania „@ola" w czasie rzeczywistym | Cloud Run + Slack `groups:history` (patrz README „Co do zrobienia") |
| tymczasowy monitor w trakcie pracy | `CronCreate` / `/loop` w sesji CLI |

Pełny rejestr działających automatyzacji: `~/.claude/AUTOMATYZACJE.md`.

---

## Ściąga: „chcę używać checków z przeglądarki"

1. Autoryzuj konektor **BigQuery** na `claude.ai/customize/connectors` (konto z dostępem do
   `polish-bookstores-group`).
2. Utwórz rutynę `/schedule` z konektorami Slack + BigQuery, prompt = „policz z
   `polish-bookstores-group.BIData.<tabela>` … i wyślij na Slacka".
3. Dane muszą być w BQ (są — ETL je tam trzyma). Web nie sięgnie do SQL Servera za VPN.
4. Do wiedzy domenowej w chmurze: trzymaj skille w `<repo>/.claude/skills/` i wskaż repo rutynie.
