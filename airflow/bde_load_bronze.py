# BDE AT3 - Parts 1 and 3 (one DAG for both, like the brief asks)
# Every time I trigger this DAG it does 3 things:
#   1. loads the reference files (census + LGA) into bronze, but only if they're not there yet
#   2. finds the next Airbnb month that isn't loaded yet, in date order
#   3. loads only that month into bronze.raw_listings
# Then I run the dbt job by hand, and trigger the DAG again for the following month.
# The first run loads the references + 05_2020 (that's Part 1), the next 11 runs load the rest (Part 3).

import io
import os
from datetime import datetime

import pandas as pd
from airflow import DAG
from airflow.exceptions import AirflowSkipException
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook

# the data/ folder of the Composer bucket is mounted here on the Airflow workers
DATA_DIR = "/home/airflow/gcs/data"
LISTINGS_DIR = "listings"
LISTINGS_TABLE = "bronze.raw_listings"
POSTGRES_CONN = "postgres_bde"

# reference files (inside data/) -> bronze table. These never change, so I load them only once.
REFERENCE_FILES = {
    "Census LGA/2016Census_G01_NSW_LGA.csv": "bronze.raw_census_g01",
    "Census LGA/2016Census_G02_NSW_LGA.csv": "bronze.raw_census_g02",
    "NSW_LGA/NSW_LGA_CODE.csv": "bronze.raw_lga_code",
    "NSW_LGA/NSW_LGA_SUBURB.csv": "bronze.raw_lga_suburb",
}


def load_csv(file_path, table):
    # read everything as text, same as the bronze tables
    df = pd.read_csv(os.path.join(DATA_DIR, file_path), dtype=str)

    # CSV headers are in upper/mixed case, my table columns are lowercase
    df.columns = [c.strip().lower() for c in df.columns]

    # some CSVs have extra commas at the end of each line, so pandas creates
    # empty columns called "Unnamed: 2", "Unnamed: 3"... I drop them
    df = df.loc[:, ~df.columns.str.startswith("unnamed")]

    file_name = os.path.basename(file_path)
    df["source_file"] = file_name

    # write the dataframe into memory as CSV so I can use COPY
    # (COPY is much faster than inserting rows one by one)
    buffer = io.StringIO()
    df.to_csv(buffer, index=False, header=False)
    buffer.seek(0)
    cols = ", ".join(df.columns)

    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN)
    conn = hook.get_conn()
    with conn.cursor() as cur:
        # remove rows from this file first, so if I run the DAG twice I don't get duplicates
        cur.execute(f"DELETE FROM {table} WHERE source_file = %s", (file_name,))
        cur.copy_expert(f"COPY {table} ({cols}) FROM STDIN WITH CSV", buffer)
    # delete + copy are committed together, so if the copy fails nothing is lost
    conn.commit()
    conn.close()

    print(f"{len(df)} rows loaded from {file_name} into {table}")


def is_loaded(table, file_name):
    # true if this file is already in the bronze table (I check the source_file column)
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN)
    count = hook.get_first(
        f"SELECT count(*) FROM {table} WHERE source_file = %s", parameters=(file_name,)
    )[0]
    return count > 0


def load_reference(file_path, table):
    # census and LGA files are static, so I only load them the first time.
    # If I reloaded them every month, loaded_at would change and the LGA/suburb
    # snapshots would create a new "version" every month even though nothing changed.
    if is_loaded(table, os.path.basename(file_path)):
        print(f"{file_path} is already in {table}, skipping it")
        return
    load_csv(file_path, table)


def month_order(file_name):
    # file names look like MM_YYYY.csv, so sorting by name would put 01_2021 before 05_2020.
    # I turn the name into (year, month) so the files are sorted by real date.
    month, year = file_name.replace(".csv", "").split("_")
    return int(year), int(month)


def find_next_month():
    # all the monthly files in the bucket, sorted by date
    files = sorted(
        [f for f in os.listdir(os.path.join(DATA_DIR, LISTINGS_DIR)) if f.endswith(".csv")],
        key=month_order,
    )

    # months that are already in bronze
    hook = PostgresHook(postgres_conn_id=POSTGRES_CONN)
    loaded = {row[0] for row in hook.get_records(f"SELECT DISTINCT source_file FROM {LISTINGS_TABLE}")}

    for file_name in files:
        if file_name not in loaded:
            # safety check: never load a month that is older than one already loaded,
            # otherwise the snapshots in dbt would get the history in the wrong order
            if loaded and month_order(file_name) < max(month_order(f) for f in loaded):
                raise ValueError(f"{file_name} is older than a month already loaded, check the bronze table")
            print(f"Next month to load: {file_name}")
            return f"{LISTINGS_DIR}/{file_name}"

    # nothing left to load, so the next task is skipped
    raise AirflowSkipException("All the monthly files are already loaded")


def load_listings_month(ti):
    # the file name comes from the find_next_month task (through XCom)
    file_path = ti.xcom_pull(task_ids="find_next_month")
    load_csv(file_path, LISTINGS_TABLE)


with DAG(
    dag_id="bde_load_bronze",
    start_date=datetime(2026, 10, 1),
    schedule_interval=None,  # no schedule, I trigger it manually (asked in the brief)
    catchup=False,
    max_active_runs=1,  # only one run at a time, so two runs can never load the same month
    tags=["bde", "bronze"],
) as dag:

    # reference tables: one task per file, they can run in parallel
    reference_tasks = [
        PythonOperator(
            task_id=f"load_{table.split('.')[1]}",
            python_callable=load_reference,
            op_kwargs={"file_path": file_path, "table": table},
        )
        for file_path, table in REFERENCE_FILES.items()
    ]

    find_next = PythonOperator(task_id="find_next_month", python_callable=find_next_month)

    load_month = PythonOperator(task_id="load_listings_month", python_callable=load_listings_month)

    # reference data first, then the listings (dimensions before facts)
    reference_tasks >> find_next >> load_month
