# Obraz wspolny dla ETL i runnera checkow.
# Baza z gcloud/bq w srodku (oba wolaja bq), plus sterownik pymssql dla ETL.
FROM google/cloud-sdk:slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip freetds-dev freetds-bin \
 && pip3 install --break-system-packages --no-cache-dir pymssql \
 && apt-get purge -y freetds-dev \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY etl/    /app/etl/
COPY runner/ /app/runner/
COPY sql/    /app/sql/

# ENTRYPOINT to samo `python3` — modul wybiera job przez args, np.:
#   ETL:    ["-m","etl.sync","--table=opi_OrderProfit"]
#   checki: ["-m","runner.run_check","--check=stratne-daily","--send=U03787T2DTR"]
ENTRYPOINT ["python3"]
CMD ["-m", "etl.sync", "--all"]
