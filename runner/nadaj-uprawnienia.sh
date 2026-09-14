#!/usr/bin/env bash
# Nadania IAM potrzebne do wdrozenia jobow tego repo.
#
# Po co osobny plik, skoro komendy sa tez w naglowkach manifestow: sa za dlugie, zeby
# je niezawodnie wkleic. Zawiniety wiersz przenosi do terminala znak nowej linii i zsh
# wykonuje kawalki jako osobne komendy — 2026-09-12 i 2026-09-14 wywrocilo sie to dwa razy.
# Tutaj wywolanie jest krotkie: bash runner/nadaj-uprawnienia.sh
#
# Skrypt jest idempotentny — powtorne uruchomienie nic nie psuje.
set -euo pipefail

PROJEKT=erp-production-438714
SA=businesschecks@erp-production-438714.iam.gserviceaccount.com

# ⚠️ Nadanie run.invoker jest PER JOB. businesschecks-daily ma je od dawna, ale kazdy NOWY
# job startuje bez niego: trigger wraca wtedy z kodem 7 (PERMISSION_DENIED), nie powstaje
# zadna egzekucja i raport po prostu nie przychodzi — bez sladu na Slacku.
for JOB in businesschecks-daily businesschecks-weekly; do
  echo "== $JOB =="
  gcloud run jobs add-iam-policy-binding "$JOB" \
    --region=europe-north1 \
    --project="$PROJEKT" \
    --member="serviceAccount:$SA" \
    --role=roles/run.invoker
done
