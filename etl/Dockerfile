# Obraz ETL: SQL Server -> BigQuery.
# Baza z gcloud/bq w srodku (ETL wola bq load + bq query), plus sterownik pymssql.
FROM google/cloud-sdk:slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip freetds-dev freetds-bin \
 && pip3 install --break-system-packages --no-cache-dir pymssql \
 && apt-get purge -y freetds-dev \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY etl/ /app/etl/

# Domyslnie: synchronizuj wszystko. Nadpisywalne argsami w Cloud Run Job.
ENTRYPOINT ["python3", "-m", "etl.sync"]
CMD ["--all"]
