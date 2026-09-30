#!/usr/bin/env python3
"""
Archiwum crawl-statow z Cloudflare -> BigQuery (BIData.cf_crawl_daily @ europe-west3).

PO CO TO JEST
  Google Search Console ma raport "Statystyki indeksowania", ale trzyma go 90 dni,
  nie ma go w API ani w bulk exporcie do BigQuery. Przy kazdej analizie "czy Google
  przestal nas crawlowac" trafialismy na sciane.

  Cloudflare widzi to samo od naszej strony i wiecej: kod odpowiedzi, status cache'u
  i czas odpowiedzi origina per bot. Ale trzyma okno ~4 tygodni. Ten skrypt zrzuca
  je codziennie do BQ, zanim wyparuja.

CO ZAPISUJE
  Jeden wiersz = (doba, zona, bot, kod odpowiedzi brzegu, status cache).
  Ruch do origina liczymy ze statusu cache (miss/expired/dynamic/none/bypass),
  bo wymiar originResponseStatus ma w GraphQL okno tylko 1w1d - patrz LEKCJA nizej.

UZYCIE
    python3 -m etl.cf_crawl                    # wczorajsza doba (domyslnie)
    python3 -m etl.cf_crawl --date 2026-09-15
    python3 -m etl.cf_crawl --backfill 25      # 25 ostatnich pelnych dob
    python3 -m etl.cf_crawl --dry-run

LEKCJA (2026-09-18, przy okazji analizy Cache Reserve)
  Cloudflare GraphQL tnie okno w zaleznosci od wymiarow: ~4w3d dla podstawowych,
  1w1d gdy dotkniesz originResponseStatus. Nie zakladaj jednego limitu dla calego API.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

PROJECT = os.environ.get("BQ_PROJECT", "polish-bookstores-group")
DATASET = os.environ.get("BQ_DATASET", "BIData")
TABLE = "cf_crawl_daily"
LOCATION = "europe-west3"
GQL = "https://api.cloudflare.com/client/v4/graphql"
API = "https://api.cloudflare.com/client/v4"
SECRET = os.environ.get("CF_TOKEN_SECRET", "cloudflare-readonly-token")
SECRET_PROJECT = os.environ.get("CF_TOKEN_PROJECT", "erp-production-438714")

# Zony sklepowe. Reszta (librimondo, tirefu) nie ma ruchu organicznego wartego archiwum.
ZONY = [
    "ksiegarniainternetowa.co.uk",
    "ksiegarniainternetowa.de",
    "polskaksiegarniainternetowa.eu",
    "thepolishbookstore.com",
    "slowianin.nl",
    "slowianin.eu",
    "slowianin.co.uk",
    "slowianin.de",
]

# Wzorce sa ROZLACZNE - Googlebot-Image ma w UA "Googlebot-Image/1.0", a zwykly
# Googlebot "Googlebot/2.1", wiec filtr na "Googlebot/2.1" nie lapie obrazkow.
BOTY = [
    ("Googlebot", "%Googlebot/2.1%"),
    ("Googlebot-Image", "%Googlebot-Image%"),
    ("Googlebot-Video", "%Googlebot-Video%"),
    ("Google-Extended", "%Google-Extended%"),
    ("GoogleOther", "%GoogleOther%"),
    ("AdsBot-Google", "%AdsBot-Google%"),
    ("Storebot-Google", "%Storebot-Google%"),
    ("bingbot", "%bingbot%"),
    ("YandexBot", "%YandexBot%"),
    ("Applebot", "%Applebot%"),
    ("ClaudeBot", "%ClaudeBot%"),
    ("GPTBot", "%GPTBot%"),
    ("OAI-SearchBot", "%OAI-SearchBot%"),
    ("PerplexityBot", "%PerplexityBot%"),
    ("Amazonbot", "%Amazonbot%"),
    ("Bytespider", "%Bytespider%"),
    ("AhrefsBot", "%AhrefsBot%"),
    ("SemrushBot", "%SemrushBot%"),
    ("DataForSeoBot", "%DataForSeoBot%"),
    ("facebookexternalhit", "%facebookexternalhit%"),
    ("__WSZYSTKO__", None),  # mianownik: caly ruch zony (dataset probkowany)
]

# Wiersz kalibracyjny. httpRequestsAdaptiveGroups jest PROBKOWANY i jego `count`
# potrafi byc do 67% wyzszy niz nieprobkowany rollup httpRequests1dGroups, a skala
# bledu jest ROZNA DLA KAZDEJ ZONY (17.09.2026: co.uk 1,17x, tpb 1,61x, slowianin.nl
# 1,67x, slowianin.co.uk 1,00x). Dlatego obok liczb per bot zapisujemy dobowa sume
# z datasetu nieprobkowanego - inaczej porownanie zon miedzy soba jest nieuprawnione.
BOT_EXACT = "__EXACT_1DGROUPS__"

SCHEMA = [
    ("data_date", "DATE"),
    ("zone", "STRING"),
    ("bot", "STRING"),
    ("edge_status", "INT64"),
    ("cache_status", "STRING"),
    ("requests", "INT64"),
    ("bytes", "INT64"),
    ("avg_origin_ms", "FLOAT64"),
    ("collected_at", "TIMESTAMP"),
]

# Status cache'u, ktory oznacza, ze zadanie poszlo do origina.
DO_ORIGINA = {"miss", "expired", "dynamic", "none", "bypass", "revalidated"}


def log(msg: str) -> None:
    print(f"[{dt.datetime.now():%H:%M:%S}] {msg}", flush=True)


def token() -> str:
    t = os.environ.get("CF_API_TOKEN")
    if t:
        return t.strip()
    out = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest",
         f"--secret={SECRET}", f"--project={SECRET_PROJECT}"],
        capture_output=True, text=True, check=True)
    return out.stdout.strip()


def gql(query: str, tok: str) -> dict:
    req = urllib.request.Request(
        GQL, data=json.dumps({"query": query}).encode(),
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        d = json.load(r)
    if d.get("errors"):
        raise RuntimeError(d["errors"][0].get("message", "blad GraphQL"))
    return d["data"]


def zone_tagi(tok: str) -> dict[str, str]:
    req = urllib.request.Request(
        f"{API}/zones?per_page=50", headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.load(r)
    if not d.get("success"):
        raise RuntimeError(f"nie moge pobrac listy zon: {d.get('errors')}")
    return {z["name"]: z["id"] for z in d["result"]}


def pobierz_zakres(tok: str, tag: str, zona: str, od: dt.date, do: dt.date) -> list[dict]:
    """Zakres dob jednej zony, po jednym zapytaniu na bota (wymiar `date` zalatwia
    caly zakres naraz - inaczej backfill to tysiace wywolan). Wzorce UA sa rozlaczne,
    wiec nic sie nie dubluje i nie ma ryzyka ucietego top-N."""
    lo = f"{od}T00:00:00Z"
    hi = f"{do + dt.timedelta(days=1)}T00:00:00Z"
    teraz = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    wiersze: list[dict] = []
    for nazwa, wzorzec in BOTY:
        ua = f', userAgent_like:"{wzorzec}"' if wzorzec else ""
        q = f'''{{ viewer {{ zones(filter:{{zoneTag:"{tag}"}}) {{
              httpRequestsAdaptiveGroups(limit:10000,
                filter:{{datetime_geq:"{lo}", datetime_lt:"{hi}"{ua}}},
                orderBy:[count_DESC]) {{
                dimensions {{ date edgeResponseStatus cacheStatus }}
                count
                sum {{ edgeResponseBytes }}
                avg {{ originResponseDurationMs }}
              }} }} }} }}'''
        grupy = gql(q, tok)["viewer"]["zones"][0]["httpRequestsAdaptiveGroups"]
        for g in grupy:
            wiersze.append({
                "data_date": g["dimensions"]["date"],
                "zone": zona,
                "bot": nazwa,
                "edge_status": g["dimensions"]["edgeResponseStatus"],
                "cache_status": g["dimensions"]["cacheStatus"],
                "requests": g["count"],
                "bytes": g["sum"]["edgeResponseBytes"],
                "avg_origin_ms": g["avg"]["originResponseDurationMs"],
                "collected_at": teraz,
            })
    return wiersze


def pobierz_exact(tok: str, tag: str, zona: str, od: dt.date, do: dt.date) -> list[dict]:
    """Dobowe sumy z httpRequests1dGroups - dataset NIEPROBKOWANY, ten sam, ktory
    pokazuje panel CF. Sluzy do kalibracji liczb z datasetu adaptacyjnego."""
    teraz = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    q = f'''{{ viewer {{ zones(filter:{{zoneTag:"{tag}"}}) {{
          httpRequests1dGroups(limit:100, filter:{{date_geq:"{od}", date_leq:"{do}"}}) {{
            dimensions {{ date }} sum {{ requests }} }} }} }} }}'''
    out = []
    for g in gql(q, tok)["viewer"]["zones"][0]["httpRequests1dGroups"]:
        out.append({
            "data_date": g["dimensions"]["date"],
            "zone": zona,
            "bot": BOT_EXACT,
            "edge_status": None,
            "cache_status": None,
            "requests": g["sum"]["requests"],
            "bytes": None,
            "avg_origin_ms": None,
            "collected_at": teraz,
        })
    return out


def bq(args: list[str]) -> str:
    out = subprocess.run(["bq", *args], capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(f"bq {' '.join(args)}\n{out.stderr.strip()}")
    return out.stdout


def zapewnij_tabele() -> None:
    cel = f"{PROJECT}:{DATASET}.{TABLE}"
    czy = subprocess.run(["bq", "show", "--format=none", cel], capture_output=True, text=True)
    if czy.returncode == 0:
        return
    log(f"tworze {cel}")
    schema = ",".join(f"{n}:{t}" for n, t in SCHEMA)
    bq(["mk", "--table",
        "--time_partitioning_field=data_date", "--time_partitioning_type=DAY",
        "--clustering_fields=zone,bot",
        f"--location={LOCATION}",
        "--description=Crawl-staty z Cloudflare per doba/zona/bot. GSC trzyma 90 dni i nie ma API - to jest nasz zamiennik.",
        cel, schema])


def wgraj(wiersze: list[dict], dni: list[dt.date]) -> None:
    """Idempotentnie: kasuje te doby i wgrywa od nowa. Powtorzony bieg nie dubluje."""
    cel = f"{PROJECT}:{DATASET}.{TABLE}"
    lista = ", ".join(f"'{d}'" for d in sorted({w["data_date"] for w in wiersze}))
    bq(["query", "--use_legacy_sql=false", f"--location={LOCATION}", "--format=none",
        f"DELETE FROM `{PROJECT}.{DATASET}.{TABLE}` WHERE data_date IN ({lista})"])
    with tempfile.NamedTemporaryFile("w", suffix=".ndjson", delete=False) as f:
        for w in wiersze:
            f.write(json.dumps(w) + "\n")
        sciezka = f.name
    try:
        bq(["load", "--source_format=NEWLINE_DELIMITED_JSON", f"--location={LOCATION}",
            cel, sciezka])
    finally:
        Path(sciezka).unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="konkretna doba YYYY-MM-DD")
    ap.add_argument("--backfill", type=int, default=0,
                    help="ile ostatnich pelnych dob (okno CF to ~4 tygodnie)")
    ap.add_argument("--zones", help="lista zon po przecinku (domyslnie sklepowe)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    wczoraj = dt.date.today() - dt.timedelta(days=1)
    if a.date:
        dni = [dt.date.fromisoformat(a.date)]
    elif a.backfill:
        dni = [wczoraj - dt.timedelta(days=i) for i in range(a.backfill)][::-1]
    else:
        dni = [wczoraj]

    zony = [z.strip() for z in a.zones.split(",")] if a.zones else ZONY
    tok = token()
    tagi = zone_tagi(tok)
    brak = [z for z in zony if z not in tagi]
    if brak:
        log(f"UWAGA: nie znalazlem zon w koncie CF: {brak}")

    od, do = min(dni), max(dni)
    wszystko: list[dict] = []
    for zona in zony:
        if zona not in tagi:
            continue
        try:
            w = pobierz_zakres(tok, tagi[zona], zona, od, do)
        except RuntimeError as e:
            log(f"  {zona}: POMINIETE - {e}")
            continue
        try:
            w += pobierz_exact(tok, tagi[zona], zona, od, do)
        except RuntimeError as e:
            log(f"  {zona}: brak kalibracji 1dGroups - {e}")
        boty = sum(x["requests"] for x in w if not x["bot"].startswith("__"))
        org = sum(x["requests"] for x in w
                  if not x["bot"].startswith("__") and x["cache_status"] in DO_ORIGINA)
        log(f"  {zona} {od}..{do}: {len(w)} wierszy, boty {boty:,} zadan, do origina {org:,}")
        wszystko.extend(w)

    if not wszystko:
        log("nic do zapisania")
        return 1
    if a.dry_run:
        log(f"dry-run: {len(wszystko)} wierszy, {len(dni)} dob - nic nie zapisuje")
        return 0

    zapewnij_tabele()
    wgraj(wszystko, dni)
    log(f"zapisane: {len(wszystko)} wierszy do {PROJECT}.{DATASET}.{TABLE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
