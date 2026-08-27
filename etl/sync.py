#!/usr/bin/env python3
"""
Delta sync SQL Server -> BigQuery (dataset BIData @ europe-west3).

Zasady:
  * NDJSON zamiast TSV  -> kolumny tekstowe (Reason, Notes) moga zawierac newline/tab/cudzyslow
                           bez psucia formatu. To byl glowny blad poprzedniego ETL-a.
  * MERGE po PRAWDZIWYM PK (wykrywanym z katalogu zrodla), nie po zgadywanym kluczu biznesowym.
  * Watermark z targetu z nakladka (OVERLAP_MIN) -> MERGE jest idempotentny, wiec powtorzenie
    kilku wierszy jest bezpieczne, a zgubienie wiersza na granicy sekundy - nie.
  * KAZDE zapytanie BQ najpierw --dry_run; jesli skan > MAX_SCAN_GB, robota jest przerywana.
    To jest bezpiecznik kosztowy - nie da sie przypadkiem puscic zapytania za setki zlotych.
  * bq load jest darmowy; platny jest storage i skany. Dlatego dane ida przez load, nie przez INSERT.

Uzycie:
    python3 -m etl.sync --all
    python3 -m etl.sync --table opi_OrderProfit
    python3 -m etl.sync --all --dry-run          # tylko pokaz co by zrobil

Zmienne srodowiskowe:
    SQL_HOST (domyslnie 10.1.1.102), SQL_USER, SQL_PASS   - polaczenie do SQL Server
    MAX_SCAN_GB (domyslnie 20)                            - bezpiecznik kosztowy
"""
from __future__ import annotations

import argparse
import datetime as dt
import decimal
import gzip
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CONFIG = Path(__file__).with_name("tables.json")
BATCH = 20_000
OVERLAP_MIN = 10
# Jeden dlugi upload do BQ potrafi paść na ConnectionReset (sprawdzone: 188 MB, 10 min, zerwane).
# Dlatego delta idzie porcjami — kazda krotka i ponawialna osobno.
CHUNK_ROWS = 250_000
RETRIES = 3
# Ile czekac az sidecar cloudflared postawi tunel do bazy (Cloud Run startuje kontenery rownolegle).
CONNECT_WAIT_S = float(os.environ.get("CONNECT_WAIT_S", "120"))
MAX_SCAN_GB = float(os.environ.get("MAX_SCAN_GB", "20"))

# SQL Server -> BigQuery. Kwoty jako NUMERIC (dokladne), nie FLOAT64.
TYPE_MAP = {
    "int": "INT64", "bigint": "INT64", "smallint": "INT64", "tinyint": "INT64",
    "bit": "BOOL",
    "decimal": "NUMERIC", "numeric": "NUMERIC", "money": "NUMERIC", "smallmoney": "NUMERIC",
    "float": "FLOAT64", "real": "FLOAT64",
    "datetime": "TIMESTAMP", "datetime2": "TIMESTAMP", "smalldatetime": "TIMESTAMP",
    "datetimeoffset": "TIMESTAMP",
    "date": "DATE", "time": "TIME",
    "uniqueidentifier": "STRING",
}
SKIP_TYPES = {"varbinary", "binary", "image", "geography", "geometry", "xml", "hierarchyid", "sql_variant"}


def log(msg: str) -> None:
    print(f"[{dt.datetime.now(dt.UTC):%H:%M:%S}] {msg}", flush=True)


# ─────────────────────────── SQL Server ───────────────────────────

def connect(db: str, charset: str = "CP1250"):
    """Laczy z SQL Server, czekajac az baza bedzie osiagalna.

    W Cloud Run baza jest za sidecarem `cloudflared`, ktory potrzebuje kilku sekund na
    postawienie listenera na 127.0.0.1:1433. Bez czekania glowny kontener startuje pierwszy
    i dostaje "Connection refused (111)" — job wywala sie w calosci, mimo ze sekunde pozniej
    tunel juz dziala. Dlatego ponawiamy do CONNECT_WAIT_S sekund.
    """
    import pymssql
    czekaj_do = time.monotonic() + CONNECT_WAIT_S
    proba = 0
    while True:
        proba += 1
        try:
            return pymssql.connect(
                server=os.environ.get("SQL_HOST", "10.1.1.102"),
                user=os.environ["SQL_USER"],
                password=os.environ["SQL_PASS"],
                database=db,
                timeout=0,
                login_timeout=30,
                # Kolumny varchar trzymaja polskie znaki w CP1250. Domyslne UTF-8 dawalo
                # "konsumowa³o" zamiast "konsumowało" — czyli mirror rozjezdzal sie ze
                # zrodlem na kazdym polu tekstowym (Note w tagach, Reason w PriceOffer).
                # Zweryfikowane empirycznie: UTF-8 i LATIN1 psuja, CP1250 odtwarza poprawnie.
                #
                # ALE to prawda tylko dla tabel, w ktorych tresc siedzi w kolumnach VARCHAR.
                # Tabela z prawdziwym Unicode w NVARCHAR (BookstoreProduct: tytul, autorzy —
                # ksiazki obcojezyczne) pod CP1250 NIE DA SIE POBRAC: FreeTDS probuje
                # przekonwertowac UCS-2 na CP1250 i oddaje bajty, ktorych Python nie zdekoduje
                # ('charmap' codec can't decode byte 0x81). Dlatego charset jest przelaczalny
                # per tabela kluczem "charset" w tables.json. Domyslnie CP1250 — nie zmieniaj
                # go tabelom, ktore juz dzialaja.
                charset=charset,
            )
        except Exception as e:
            if time.monotonic() >= czekaj_do:
                raise
            if proba == 1:
                log(f"    baza jeszcze nieosiagalna, czekam na tunel (do {CONNECT_WAIT_S}s)")
            time.sleep(3)


def describe(conn, schema: str, table: str, exclude: list[str]) -> tuple[list[dict], list[str]]:
    """Zwraca (kolumny, pk). Kolumny nieobslugiwane w BQ sa pomijane z ostrzezeniem."""
    cur = conn.cursor(as_dict=True)
    cur.execute(
        """
        SELECT c.name AS nazwa, t.name AS typ, c.column_id AS nr
        FROM sys.tables tb
        JOIN sys.schemas s  ON tb.schema_id = s.schema_id
        JOIN sys.columns c  ON tb.object_id = c.object_id
        JOIN sys.types t    ON c.user_type_id = t.user_type_id
        WHERE s.name = %s AND tb.name = %s
        ORDER BY c.column_id
        """,
        (schema, table),
    )
    kolumny = []
    for r in cur.fetchall():
        if r["nazwa"] in exclude:
            continue
        if r["typ"] in SKIP_TYPES:
            log(f"    pomijam kolumne {r['nazwa']} (typ {r['typ']} nieobslugiwany w BQ)")
            continue
        kolumny.append({"nazwa": r["nazwa"], "bq": TYPE_MAP.get(r["typ"], "STRING")})

    cur.execute(
        """
        SELECT c.name AS nazwa
        FROM sys.indexes i
        JOIN sys.tables tb  ON i.object_id = tb.object_id
        JOIN sys.schemas s  ON tb.schema_id = s.schema_id
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c  ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.is_primary_key = 1 AND s.name = %s AND tb.name = %s
        ORDER BY ic.key_ordinal
        """,
        (schema, table),
    )
    pk = [r["nazwa"] for r in cur.fetchall()]
    return kolumny, pk


def serialize(v):
    if v is None:
        return None
    if isinstance(v, decimal.Decimal):
        return str(v)                      # NUMERIC jako string = bez utraty precyzji
    if isinstance(v, dt.datetime):
        return v.isoformat(sep=" ") + "+00:00"   # kolumny *Utc sa naiwne, ale trzymaja UTC
    if isinstance(v, (dt.date, dt.time)):
        return v.isoformat()
    if isinstance(v, (bytes, bytearray)):
        return None
    if isinstance(v, (str, int, float, bool)):
        return v
    # uniqueidentifier wraca jako uuid.UUID, a JSON go nie zna. Zamiast dokladac typ po typie,
    # wszystko nieznane idzie jako tekst — kolumna i tak jest zmapowana na STRING w BQ.
    return str(v)


# ─────────────────────────── Maskowanie PII ───────────────────────────
# Maskujemy PO STRONIE ZRODLA (w SELECT), a nie po pobraniu. Dzieki temu dane osobowe
# nie trafiaja nawet do pliku NDJSON na dysku ani do pamieci procesu — z bazy wychodzi
# juz wartosc zamaskowana. Tryby deklaruje sie w tables.json w kluczu "mask".
MASK_MODES = {
    # nazwisko/imie/firma -> stala. NULL zostaje NULL, zeby nie udawac danych tam gdzie ich nie ma.
    "xxx": lambda c: f"CASE WHEN [{c}] IS NULL THEN NULL ELSE 'xxx' END AS [{c}]",
    # e-mail -> zostaje sama domena (do analiz typu udzial gmail/marketplace), lokalna czesc znika.
    "email_domain": lambda c: (
        f"CASE WHEN [{c}] IS NULL THEN NULL "
        f"WHEN CHARINDEX('@', [{c}]) > 0 THEN 'xxx@' + SUBSTRING([{c}], CHARINDEX('@', [{c}]) + 1, 255) "
        f"ELSE 'xxx' END AS [{c}]"
    ),
}


def select_expr(nazwa: str, mask: dict) -> str:
    """Zwraca wyrazenie do SELECT-a: zwykla kolumne albo jej zamaskowana wersje."""
    tryb = mask.get(nazwa)
    if tryb is None:
        return f"[{nazwa}]"
    if tryb not in MASK_MODES:
        raise RuntimeError(f"Nieznany tryb maskowania '{tryb}' dla kolumny {nazwa}. Dozwolone: {sorted(MASK_MODES)}")
    return MASK_MODES[tryb](nazwa)


def pull(conn, cfg: dict, kolumny: list[dict], watermark: str | None, out_dir: Path) -> tuple[int, list[Path]]:
    """Pobiera delte do porcji po CHUNK_ROWS wierszy. Zwraca (liczba wierszy, lista plikow)."""
    mask = cfg.get("mask") or {}
    nieznane = set(mask) - {k["nazwa"] for k in kolumny}
    if nieznane:
        # lepiej wywalic sie glosno niz cicho zsynchronizowac PII bo ktos zrobil literowke
        raise RuntimeError(f"tables.json: maska wskazuje kolumny spoza tabeli {cfg['table']}: {sorted(nieznane)}")
    if mask:
        log(f"    maskuje {len(mask)} kolumn PII w zrodlowym SELECT: {', '.join(sorted(mask))}")
    cols = ", ".join(select_expr(k["nazwa"], mask) for k in kolumny)
    where = ""
    params = ()
    if watermark:
        where = f"WHERE [{cfg['watermark']}] >= %s"
        params = (watermark,)
    sql = f"SELECT {cols} FROM [{cfg['db']}].[{cfg['schema']}].[{cfg['table']}] WITH (NOLOCK) {where}"

    cur = conn.cursor(as_dict=True)
    cur.execute(sql, params)
    n = 0
    parts: list[Path] = []
    fh = None
    try:
        while True:
            rows = cur.fetchmany(BATCH)
            if not rows:
                break
            for row in rows:
                if fh is None:
                    p = out_dir / f"part_{len(parts):04d}.json.gz"
                    parts.append(p)
                    fh = gzip.open(p, "wt", encoding="utf-8")
                fh.write(json.dumps({k: serialize(v) for k, v in row.items()}, ensure_ascii=False) + "\n")
                n += 1
                if n % CHUNK_ROWS == 0:
                    fh.close()
                    fh = None
            if n % 200_000 == 0:
                log(f"    pobrano {n:,} wierszy...")
    finally:
        if fh is not None:
            fh.close()
    return n, parts


# ─────────────────────────── BigQuery ───────────────────────────

def bq(args: list[str], capture=True) -> str:
    p = subprocess.run(["bq", *args], capture_output=capture, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"bq {' '.join(args[:3])} ... nie powiodlo sie:\n{p.stderr or p.stdout}")
    return (p.stdout or "").strip()


def bq_query(sql: str, project: str, location: str, label: str) -> str:
    """Zapytanie z bezpiecznikiem kosztowym: najpierw --dry_run, potem dopiero wykonanie."""
    dry = subprocess.run(
        ["bq", f"--project_id={project}", f"--location={location}", "query",
         "--use_legacy_sql=false", "--dry_run", "--format=json", sql],
        capture_output=True, text=True,
    )
    gb = 0.0
    if dry.returncode == 0:
        try:
            gb = int(json.loads(dry.stdout)["statistics"]["query"]["totalBytesProcessed"]) / 1024**3
        except Exception:
            pass
    if gb > MAX_SCAN_GB:
        raise RuntimeError(
            f"BEZPIECZNIK KOSZTOWY: {label} chce przeskanowac {gb:.1f} GB "
            f"(limit {MAX_SCAN_GB} GB). Przerwane. Popraw zapytanie albo podnies MAX_SCAN_GB swiadomie."
        )
    log(f"    {label}: skan {gb:.3f} GB (~{gb * 5 / 1024 * 4:.3f} zl)")
    return bq([f"--project_id={project}", f"--location={location}", "query",
               "--use_legacy_sql=false", "--format=csv", sql])


def ensure_dataset(project: str, dataset: str, location: str) -> None:
    p = subprocess.run(["bq", f"--project_id={project}", "show", "--format=json", f"{project}:{dataset}"],
                       capture_output=True, text=True)
    if p.returncode == 0:
        return
    log(f"  tworze dataset {project}:{dataset} @ {location}")
    bq([f"--project_id={project}", f"--location={location}", "mk", "--dataset",
        "--description=Mirror SQL Server (BIData/azymut) - zrodlo dla businesschecks", f"{project}:{dataset}"])


def table_exists(project: str, dataset: str, table: str) -> bool:
    p = subprocess.run(["bq", f"--project_id={project}", "show", "--format=json", f"{project}:{dataset}.{table}"],
                       capture_output=True, text=True)
    return p.returncode == 0


def create_table(cfg: dict, conf: dict, kolumny: list[dict]) -> None:
    project, dataset, location = conf["project"], conf["dataset"], conf["location"]
    cols_ddl = ",\n  ".join(f"`{k['nazwa']}` {k['bq']}" for k in kolumny)
    extra = ""
    if cfg.get("partition_by"):
        # Granularnosc partycji. Domyslnie DAY, ale BigQuery przyjmuje najwyzej 4000 partycji
        # na jedno zadanie load — tabela z dluga historia (CustomerOrder: od 2010, 5819 dni)
        # przekracza ten limit i load pada w polowie. Dla takich tabel MONTH (191 partycji).
        gran = (cfg.get("partition_granularity") or "DAY").upper()
        if gran not in {"DAY", "MONTH", "YEAR"}:
            raise RuntimeError(f"partition_granularity musi byc DAY/MONTH/YEAR, jest: {gran}")
        if gran == "DAY":
            extra += f"\nPARTITION BY DATE(`{cfg['partition_by']}`)"
        else:
            # BigQuery przyjmuje tylko TRUNC pasujacy do typu kolumny — DATE_TRUNC(DATE(ts), MONTH)
            # jest odrzucane ("PARTITION BY expression must be ...").
            typ = next((k["bq"] for k in kolumny if k["nazwa"] == cfg["partition_by"]), "TIMESTAMP")
            trunc = {"TIMESTAMP": "TIMESTAMP_TRUNC", "DATETIME": "DATETIME_TRUNC", "DATE": "DATE_TRUNC"}[typ]
            extra += f"\nPARTITION BY {trunc}(`{cfg['partition_by']}`, {gran})"
    if cfg.get("cluster_by"):
        extra += "\nCLUSTER BY " + ", ".join(f"`{c}`" for c in cfg["cluster_by"])
    ddl = f"CREATE TABLE IF NOT EXISTS `{project}.{dataset}.{cfg['target']}` (\n  {cols_ddl}\n){extra}"
    log(f"  tworze tabele {cfg['target']} (partycja: {cfg.get('partition_by') or 'brak'}"
        f"{'/' + (cfg.get('partition_granularity') or 'DAY') if cfg.get('partition_by') else ''}, "
        f"klaster: {', '.join(cfg.get('cluster_by') or []) or 'brak'})")
    bq([f"--project_id={project}", f"--location={location}", "query", "--use_legacy_sql=false", ddl])


def get_watermark(cfg: dict, conf: dict) -> str | None:
    project, dataset, location = conf["project"], conf["dataset"], conf["location"]
    sql = (f"SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', "
           f"TIMESTAMP_SUB(MAX(`{cfg['watermark']}`), INTERVAL {OVERLAP_MIN} MINUTE)) "
           f"FROM `{project}.{dataset}.{cfg['target']}`")
    out = bq_query(sql, project, location, f"{cfg['target']}: watermark")
    lines = [l for l in out.splitlines() if l.strip()]
    if len(lines) < 2:
        return None
    # bq w formacie CSV oddaje NULL jako pusty ciag albo jako "" (z cudzyslowami) —
    # oba znacza "tabela pusta", czyli pelny load poczatkowy.
    wart = lines[1].strip().strip('"').strip()
    return wart or None


def load_parts(cfg: dict, conf: dict, kolumny: list[dict], parts: list[Path], cel: str) -> None:
    """Laduje porcjami do wskazanej tabeli. Pierwsza z --replace, reszta dopisuje.
    Kazda porcja ma wlasne ponowienia — zerwane polaczenie nie przekresla calej tabeli."""
    project, dataset, location = conf["project"], conf["dataset"], conf["location"]
    staging = cel
    schema = ",".join(f"{k['nazwa']}:{k['bq']}" for k in kolumny)
    log(f"    laduje do {staging}: {len(parts)} porcji (bq load = 0 zl)")

    for i, p in enumerate(parts):
        flagi = ["--replace"] if i == 0 else []
        for proba in range(1, RETRIES + 1):
            try:
                bq([f"--project_id={project}", f"--location={location}", "load", *flagi,
                    "--source_format=NEWLINE_DELIMITED_JSON",
                    f"{project}:{dataset}.{staging}", str(p), schema])
                break
            except RuntimeError as e:
                if proba == RETRIES:
                    raise
                log(f"      porcja {i + 1}/{len(parts)}: proba {proba} nieudana ({str(e).splitlines()[-1][:80]}), ponawiam")
                time.sleep(5 * proba)
        if (i + 1) % 5 == 0 or i + 1 == len(parts):
            log(f"      zaladowano {i + 1}/{len(parts)} porcji")


def merge(cfg: dict, conf: dict, kolumny: list[dict], pk: list[str]) -> None:
    project, dataset, location = conf["project"], conf["dataset"], conf["location"]
    tgt = f"`{project}.{dataset}.{cfg['target']}`"
    stg = f"`{project}.{dataset}.{cfg['target']}{conf['staging_suffix']}`"
    names = [k["nazwa"] for k in kolumny]

    on = " AND ".join(f"T.`{c}` = S.`{c}`" for c in pk)

    # Przyciecie partycji: MERGE ma dotknac tylko partycji obecnych w delcie, nie calej tabeli.
    # BigQuery NIE pozwala na podzapytanie w predykacie zlaczenia MERGE ("Unsupported subquery
    # with table in join predicate"), wiec zakres liczymy osobno i wstawiamy jako literaly.
    if cfg.get("partition_by"):
        p = cfg["partition_by"]
        zakres = bq_query(f"SELECT MIN(DATE(`{p}`)) AS od, MAX(DATE(`{p}`)) AS do_ FROM {stg}",
                          project, location, f"{cfg['target']}: zakres partycji")
        wiersze = [l for l in zakres.splitlines() if l.strip()]
        wart = wiersze[1].split(",") if len(wiersze) > 1 else []
        od = wart[0].strip().strip('"') if len(wart) > 1 else ""
        do = wart[1].strip().strip('"') if len(wart) > 1 else ""
        if od and do:
            # Wiersze z NULL w kolumnie partycjonujacej NIE wpadaja w BETWEEN — bez galezi
            # "IS NULL" nigdy by sie nie dopasowaly i MERGE wstawialby je od nowa przy KAZDYM
            # przebiegu, mnozac duplikaty. Stad jawne dopuszczenie NULL-i.
            on += f" AND (DATE(T.`{p}`) BETWEEN DATE '{od}' AND DATE '{do}' OR T.`{p}` IS NULL)"
    dedup = ", ".join(f"`{c}`" for c in pk)
    upd = ", ".join(f"`{c}` = S.`{c}`" for c in names if c not in pk)
    ins_cols = ", ".join(f"`{c}`" for c in names)
    ins_vals = ", ".join(f"S.`{c}`" for c in names)

    sql = f"""MERGE {tgt} T
USING (
  SELECT * FROM {stg}
  QUALIFY ROW_NUMBER() OVER (PARTITION BY {dedup} ORDER BY `{cfg['watermark']}` DESC) = 1
) S
ON {on}
WHEN MATCHED THEN UPDATE SET {upd}
WHEN NOT MATCHED THEN INSERT ({ins_cols}) VALUES ({ins_vals})"""
    bq_query(sql, project, location, f"{cfg['target']}: MERGE")


# ─────────────────────────── orkiestracja ───────────────────────────

def sync_table(cfg: dict, conf: dict, dry: bool) -> dict:
    log(f"► {cfg['target']}  ({cfg['db']}.{cfg['schema']}.{cfg['table']})")
    conn = connect(cfg["db"], cfg.get("charset") or "CP1250")
    try:
        kolumny, pk = describe(conn, cfg["schema"], cfg["table"], cfg.get("exclude") or [])

        # Tabela bez PK nie da sie MERGE-owac. Dla malych tabel (BolOffersFirstOffer: 112 tys.
        # wierszy, 17 MB) najprostsze i najtansze jest pelne przeladowanie: bq load jest darmowy,
        # a brak MERGE oznacza zero skanu. Wlacza sie samo albo jawnie przez "pelny_reload".
        pelny = cfg.get("pelny_reload") or not pk
        if pelny and not pk:
            log("  brak PK -> pelne przeladowanie przy kazdym przebiegu (tabela mala, load = 0 zl)")
        log(f"  kolumn: {len(kolumny)}, PK: {', '.join(pk) if pk else '(brak)'}")

        ensure_dataset(conf["project"], conf["dataset"], conf["location"])
        swieza = not table_exists(conf["project"], conf["dataset"], cfg["target"])
        if swieza and not dry:
            create_table(cfg, conf, kolumny)

        wm = None if (swieza or pelny) else get_watermark(cfg, conf)
        log(f"  watermark: {wm or 'BRAK -> pelny load poczatkowy'}")
        if dry:
            return {"target": cfg["target"], "wierszy": None, "tryb": "dry-run"}

        katalog = Path(tempfile.mkdtemp(prefix=f"etl_{cfg['target']}_"))
        try:
            n, parts = pull(conn, cfg, kolumny, wm, katalog)
            mb = sum(p.stat().st_size for p in parts) / 1024**2
            log(f"  delta: {n:,} wierszy ({mb:.1f} MB spakowane, {len(parts)} porcji)")
            if n == 0:
                return {"target": cfg["target"], "wierszy": 0}
            if wm is None:
                # Load poczatkowy albo pelne przeladowanie: nie ma czego dopasowywac.
                # Ladujemy prosto do celu i pomijamy MERGE — bq load jest darmowy,
                # a MERGE na 14 mln wierszy kosztowalby skan kilkunastu GB bez zadnego zysku.
                log("  cel pusty -> ladowanie bezposrednie, MERGE pominiety (skan 0 zl)")
                load_parts(cfg, conf, kolumny, parts, cfg["target"])
            else:
                load_parts(cfg, conf, kolumny, parts, f"{cfg['target']}{conf['staging_suffix']}")
                merge(cfg, conf, kolumny, pk)
        finally:
            shutil.rmtree(katalog, ignore_errors=True)
        log(f"  ✓ {cfg['target']}: {n:,} wierszy zsynchronizowane")
        return {"target": cfg["target"], "wierszy": n}
    finally:
        conn.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", action="append", help="nazwa targetu; mozna podac wielokrotnie")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    conf = json.loads(CONFIG.read_text(encoding="utf-8"))
    wybrane = [t for t in conf["tables"] if a.all or (a.table and t["target"] in a.table)]
    if not wybrane:
        ap.error("podaj --all albo --table <nazwa>")

    if not (os.environ.get("SQL_USER") and os.environ.get("SQL_PASS")):
        log("BLAD: brak SQL_USER / SQL_PASS w srodowisku")
        return 2

    wyniki, bledy = [], []
    for cfg in wybrane:
        try:
            wyniki.append(sync_table(cfg, conf, a.dry_run))
        except Exception as e:                       # jeden stol nie moze zabic calego przebiegu
            log(f"  ✗ {cfg['target']}: {e}")
            bledy.append((cfg["target"], str(e)))

    log("─" * 60)
    for w in wyniki:
        log(f"  {w['target']:32s} {w.get('wierszy') if w.get('wierszy') is not None else w.get('tryb')}")
    for t, e in bledy:
        log(f"  BLAD {t}: {e.splitlines()[0]}")
    return 1 if bledy else 0


if __name__ == "__main__":
    sys.exit(main())
