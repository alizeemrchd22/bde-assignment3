# BDE AT3 - Airbnb Sydney data warehouse

## What is in here
- sql/part_1.sql - all the Part 1 SQL (bronze schema, bronze tables, checks after the load)
- sql/part_4.sql - the five ad-hoc questions (a to e), plus a few extra checks
- airflow/bde_load_bronze.py - the combined DAG for Part 1 and Part 3
- dbt/ - the dbt project (models, snapshots, tests, macros, dbt_project.yml)
- extra/ - my data quality checks and the Part 4 queries split one file per question

## How to run it

### 1. Postgres
Run sql/part_1.sql on an empty database. It creates the bronze schema and the five
bronze tables, all columns as TEXT.

### 2. Airflow (Cloud Composer)
- Create an Airflow Postgres connection with the connection id `postgres_bde`,
  pointing at the database above. The DAG will not run without it.
- Put the 16 CSV files in the Composer bucket under data/:
    data/listings/05_2020.csv ... 04_2021.csv
    data/Census LGA/2016Census_G01_NSW_LGA.csv
    data/Census LGA/2016Census_G02_NSW_LGA.csv
    data/NSW_LGA/NSW_LGA_CODE.csv
    data/NSW_LGA/NSW_LGA_SUBURB.csv
- Put airflow/bde_load_bronze.py in the dags/ folder.
- The DAG has no schedule. One trigger loads the reference files (first run only)
  and the next month that is not in bronze yet. Trigger it 12 times, in order,
  and run `dbt build` after each one.

### 3. dbt
Point a dbt project at the same database and run `dbt build`.
The environment must be on dbt v1, not v2 (Fusion), which has no Postgres adapter.
The bronze tables must exist before the first build: silver_census_g01 reads the
column list from the database at compile time.

### 4. Analysis
sql/part_4.sql runs on the gold and datamart schemas, so the dbt build has to be
done first.

## Additional files (extra/)
- part_2_checks.sql - the silver, gold and datamart checks from section 6.2 of the report
- part_3_resets_and_checks.sql - the resets and the monthly check I ran after each load,
  plus the query that found the month bug from section 7.
  WARNING: contains TRUNCATE / DROP / DELETE, do not run the whole file at once.
- part_4_by_question/ - the same queries as part_4.sql, one file per question
