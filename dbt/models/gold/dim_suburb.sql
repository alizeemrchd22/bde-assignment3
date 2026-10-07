-- Gold the suburb dimension is built from the suburb snapshot SCD2
-- It's used to turn host_neighbourhood (a suburb) into its LGA in the datamart like dim_lga, the first version is valid from 1900-01-01 because loaded_at is in 2026

with versions as (

    select
        dbt_scd_id              as suburb_version_id,
        suburb_name_key,
        suburb_name,
        lga_code,
        lga_name,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by suburb_name_key order by dbt_valid_from) as version_num
    from {{ ref('suburb_snapshot') }}

)

select
    suburb_version_id,
    suburb_name_key,
    suburb_name,
    lga_code,
    lga_name,
    case
        when version_num = 1 then '1900-01-01'::date
        else date_trunc('month', dbt_valid_from)::date
    end                                                                     as valid_from,
    coalesce(date_trunc('month', dbt_valid_to)::date, '9999-12-31'::date)   as valid_to,
    dbt_valid_to is null                                                    as is_current
from versions
