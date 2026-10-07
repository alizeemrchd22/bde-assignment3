-- Silver: 2016 Census G01 (person characteristics per LGA).
-- Fixes:
--  the lga_code_2016 looks like 'LGA10050', so I remove the 'LGA' prefix and cast it to int. Now it matches the code in silver_lga (10050).
--   and every other column is a count of people, so I cast them all to int. There are more than 100 columns, so instead of writing each one by  hand I loop over the column list with Jinja.

{% set source_relation = source('bronze', 'raw_census_g01') %}
{% set all_columns = adapter.get_columns_in_relation(source_relation) %}
{% set skip_columns = ['lga_code_2016', 'source_file', 'loaded_at'] %}

select
    replace(lga_code_2016, 'LGA', '')::int    as lga_code,
    {%- for col in all_columns if col.name not in skip_columns %}
    {{ col.name }}::numeric::int              as {{ col.name }},
    {%- endfor %}
    loaded_at::timestamp                      as loaded_at
from {{ source_relation }}
