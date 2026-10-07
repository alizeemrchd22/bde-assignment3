name: 'bde_at3'
version: '1.0.0'

profile: 'default'

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:
  - "target"
  - "dbt_packages"

# Medallion layers:
# - bronze   = raw tables loaded by Airflow (declared as sources, dbt does not build them)
# - silver   = cleaned and typed tables + snapshots of the dimensions
# - gold     = star schema (dimensions + fact + census reference tables)
# - datamart = views that answer the business questions
models:
  bde_at3:
    silver:
      +schema: silver
      +materialized: table
    gold:
      +schema: gold
      +materialized: table
      datamart:
        +schema: datamart
        +materialized: view
