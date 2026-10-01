BDE Assignment 3 – Airbnb Sydney ELT pipeline

ELT pipeline on Google Cloud: Airflow (Cloud Composer) loads Airbnb listings and 2016 Census data from a Cloud Storage bucket into Postgres (Cloud SQL), then dbt Cloud builds a Medallion data warehouse (Bronze → Silver → Gold).

Repository structure
Path	Deliverable	Content
part_1.sql	1	SQL used in Postgres for Part 1 (bronze schema, raw tables, checks)
dags/	2	Single Airflow DAG covering Parts 1 and 3
part_4.sql	3	SQL used in Postgres for Part 4
dbt/	4	dbt Cloud project (models/, snapshots/, dbt_project.yml)
report/	5	Handover report
additional/	6	Additional relevant files
Data sources (not stored in this repo)
Airbnb listings for Sydney, 12 monthly files (MM_YYYY.csv)
2016 Census General Community Profile, tables G01 and G02 at LGA level (NSW)
NSW LGA code and LGA–suburb mapping files
