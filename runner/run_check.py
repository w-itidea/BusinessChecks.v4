#!/usr/bin/env python3
"""
Runner checkow: SQL w BigQuery -> tabelka -> Slack (bot ola).

Deterministyczny z zalozenia. Model jezykowy NIE jest tu potrzebny: check liczy liczby
i wysyla je. AI wchodzi dopiero przy eskalacji (progi CRITICAL) — i to jest osobny krok,
zeby codzienny raport nie kosztowal tokenow.

Uzycie:
    python3 -m runner.run_check --check buybox-sale-profitability
    python3 -m runner.run_check --check buybox-sale-profitability --send U03787T2DTR
    python3 -m runner.run_check --check buybox-sale-profitability --dry-run   # tylko koszt skanu

Slack: token bota `ola` z GCP Secret Manager (cred-api-slack-ola, projekt erp-production-438714).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "polish-bookstores-group"
LOCATION = "europe-west3"
MAX_SCAN_GB = 20.0
SLACK_SECRET = "cred-api-slack-ola"
SLACK_PROJECT = "erp-production-438714"


def znajdz_sql(nazwa: str) -> Path:
    for kat in ("sql/reports", "sql/diagnostic"):
        p = ROOT / kat / f"{nazwa}.sql"
        if p.exists():
            return p
    raise SystemExit(f"nie znalazlem checku '{nazwa}' w sql/reports ani sql/diagnostic")


def sprawdz_gwiazdke(sql: str) -> None:
    """BigQuery jest kolumnowy: placisz za kolumny, ktore wybierzesz, nie za rozmiar tabeli.
    Na ofi_PriceOffer `SELECT *` to 14,53 GB, a piec konkretnych kolumn — 0,85 GB (17x taniej).
    Sam `Reason` to 79% objetosci. Dlatego gwiazdka na duzych mirrorach jest blokowana."""
    duze = ("ofi_PriceOffer", "opi_OrderProfit", "opi_OrderItemProfit",
            "opi_ShippingCost", "azymut_BookstoreProductPA")
    bez_komentarzy = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))
    # Liczy sie gwiazdka WPROST NA TABELI. `SELECT * FROM (podzapytanie)` jest w porzadku —
    # kolumny zostaly juz zawezone glebiej, wiec skan jest maly.
    for t in duze:
        if re.search(rf"SELECT\s+\*\s+(EXCEPT\s*\([^)]*\)\s+)?FROM\s+`[^`]*{t}`",
                     bez_komentarzy, re.IGNORECASE):
            raise SystemExit(
                f"ODRZUCONE: 'SELECT *' wprost na duzej tabeli ({t}). Wypisz kolumny jawnie —\n"
                f"na ofi_PriceOffer to roznica 14,53 GB vs 0,85 GB.\n"
                f"(Swiadomy wyjatek: opakuj w podzapytanie z lista kolumn.)"
            )


def czytaj_location(sql: str) -> str:
    """Per-check override regionu: naglowek `-- location: EU` w pliku checku.
    Domyslnie europe-west3 (mirror BIData). Billing export lezy w EU/US — stad override
    (job musi jechac w tym samym regionie co dataset, inaczej 'Not found: Dataset ... in location')."""
    for l in sql.splitlines():
        s = l.strip()
        if s.lower().startswith("-- location:"):
            return s.split(":", 1)[1].strip()
    return LOCATION


def koszt_skanu(sql: str, location: str = LOCATION) -> float:
    """--dry_run: ile GB przeskanuje. Kosztuje 0. Zawsze wolane PRZED wykonaniem."""
    # SQL idzie przez stdin, NIE jako argument: pliki checkow zaczynaja sie od komentarza "--",
    # ktory bq bierze za flage i wywala sie z RecursionError przy podpowiadaniu nazwy flagi.
    p = subprocess.run(
        ["bq", f"--project_id={PROJECT}", f"--location={location}", "query",
         "--use_legacy_sql=false", "--dry_run", "--format=json"],
        input=sql, capture_output=True, text=True,
    )
    if p.returncode != 0:
        raise SystemExit(f"blad skladni SQL (dry-run):\n{p.stderr or p.stdout}")
    return int(json.loads(p.stdout)["statistics"]["query"]["totalBytesProcessed"]) / 1024**3


def wykonaj(sql: str, location: str = LOCATION) -> list[dict]:
    p = subprocess.run(
        ["bq", f"--project_id={PROJECT}", f"--location={location}", "query",
         "--use_legacy_sql=false", "--format=prettyjson"],
        input=sql, capture_output=True, text=True,
    )
    if p.returncode != 0:
        raise SystemExit(f"zapytanie nie powiodlo sie:\n{p.stderr or p.stdout}")
    dane = json.loads(p.stdout or "[]")
    # bq --format=prettyjson potrafi opakowac wynik w dodatkowa liste ([[{...}]]) — rozpakowujemy.
    while isinstance(dane, list) and len(dane) == 1 and isinstance(dane[0], list):
        dane = dane[0]
    return dane


def jako_tabela(wiersze: list[dict]) -> str:
    if not wiersze:
        return "(brak wynikow)"
    kol = list(wiersze[0].keys())
    szer = {k: max(len(k), *(len(str(w.get(k) or "")) for w in wiersze)) for k in kol}
    linie = [" | ".join(k.ljust(szer[k]) for k in kol),
             "-+-".join("-" * szer[k] for k in kol)]
    for w in wiersze:
        linie.append(" | ".join(str(w.get(k) if w.get(k) is not None else "").ljust(szer[k]) for k in kol))
    return "\n".join(linie)


def slack_token() -> str:
    p = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         f"--secret={SLACK_SECRET}", f"--project={SLACK_PROJECT}"],
        capture_output=True, text=True,
    )
    if p.returncode != 0:
        raise SystemExit(f"nie moge pobrac tokenu Slacka: {p.stderr}")
    return p.stdout.strip()


def wyslij(kanal: str, tekst: str) -> None:
    req = urllib.request.Request(
        "https://slack.com/api/chat.postMessage",
        data=json.dumps({"channel": kanal, "text": tekst}).encode("utf-8"),
        headers={"Authorization": f"Bearer {slack_token()}", "Content-type": "application/json; charset=utf-8"},
    )
    odp = json.load(urllib.request.urlopen(req))
    if not odp.get("ok"):
        raise SystemExit(f"Slack odrzucil wiadomosc: {odp.get('error')}")
    print("wyslano na Slacka")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="append", required=True,
                    help="nazwa checku; mozna podac wielokrotnie (jedna wiadomosc na Slacku)")
    ap.add_argument("--send", help="channel_id lub user_id (DM)")
    ap.add_argument("--tytul", default="Raport dzienny", help="naglowek wiadomosci na Slacku")
    ap.add_argument("--dry-run", action="store_true", help="policz koszt skanu i zakoncz")
    a = ap.parse_args()

    czesci, gb_razem, bledy = [], 0.0, []
    for nazwa in a.check:
        try:
            sql = znajdz_sql(nazwa).read_text(encoding="utf-8")
            loc = czytaj_location(sql)
            sprawdz_gwiazdke(sql)
            gb = koszt_skanu(sql, loc)
            gb_razem += gb
            print(f"[{nazwa}] skan: {gb:.3f} GB (~{gb * 5 / 1024 * 4:.3f} zl) [region {loc}]")
            if gb > MAX_SCAN_GB:
                raise SystemExit(f"BEZPIECZNIK: {gb:.1f} GB > limit {MAX_SCAN_GB} GB — przerwane")
            if a.dry_run:
                continue
            tabela = jako_tabela(wykonaj(sql, loc))
            print(f"── {nazwa} ──\n{tabela}\n")
            czesci.append(f"*{nazwa}*\n```\n{tabela}\n```")
        except SystemExit:
            raise
        except Exception as e:                  # jeden check nie moze zabic calego raportu
            print(f"[{nazwa}] BLAD: {e}")
            bledy.append(f"*{nazwa}* — błąd: `{str(e).splitlines()[0][:120]}`")

    if a.dry_run:
        return 0

    if a.send and (czesci or bledy):
        naglowek = f"*{a.tytul}* — {dt.date.today():%Y-%m-%d}"
        stopka = f"_skan {gb_razem:.2f} GB (~{gb_razem * 5 / 1024 * 4:.3f} zł)_"
        wyslij(a.send, "\n\n".join([naglowek, *czesci, *bledy, stopka]))
    return 1 if bledy else 0


if __name__ == "__main__":
    sys.exit(main())
