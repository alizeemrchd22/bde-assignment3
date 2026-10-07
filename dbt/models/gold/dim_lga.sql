-- Gold: LGA dimension is built from the LGA snapshot SCD2.
-- The first version is valid from 1900-01-01 because loaded_at is in 2026 (when Airflow loaded the file) but the listings are from 2020-2021. lga_name_key is kept to join listing_neighbourhood names to their LGA code.

with versions as (

    select
        dbt_scd_id              as lga_version_id,
        lga_code,
        lga_name,
        lga_name_key,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by lga_code order by dbt_valid_from) as version_num
    from {{ ref('lga_snapshot') }}

)

select
    lga_version_id,
    lga_code,
    lga_name,
    lga_name_key,
    case
        when version_num = 1 then '1900-01-01'::date
        else date_trunc('month', dbt_valid_from)::date
    end                                                                     as valid_from,
    coalesce(date_trunc('month', dbt_valid_to)::date, '9999-12-31'::date)   as valid_to,
    dbt_valid_to is null                                                    as is_current
from versions
