# sql/manual — zapytania ręczne (T-SQL, sqlcmd)

Te pliki **nie są checkami** i runner ich nie odpali — pisane są w T-SQL
(`SELECT TOP`, `(NOLOCK)`, `DATEADD`, placeholdery `[DAYS]`/`[ID]`),
a runner wykonuje wyłącznie **BigQuery**.

Odpalać ręcznie:
```
sqlcmd -S "10.1.1.102" -U "claude_readonly" -P "ReadOnly123!" -d azymut --trust-server-certificate -i plik.sql
```

| Plik | Co robi | Uwaga |
|---|---|---|
| `weekly-losses.sql` | stratne zamówienia z N dni | pokrywa się z checkiem `stratne-daily`, który robi to samo w BQ, z klasyfikacją przyczyn i linkami do panelu — **preferuj check** |
| `problematic-products.sql` | produkty z powtarzającymi się stratami (min 3 wystąpienia) | brak odpowiednika wśród checków; kandydat do przepisania na BQ, gdyby miał chodzić cyklicznie |

Przeniesione z `sql/reports/` 2026-08-26 — leżały tam, sugerując, że są checkami.
