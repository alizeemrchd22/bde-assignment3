-- Gold: it host the dimension that is built from the host snapshot so there's one row per version of a host SCD2
-- I move valid_from / valid_to to the start of the month because the datamart works per month,and the first version of each host is valid from 1900-01-01 so no fact row is left without a match.

with versions as (

    select
        dbt_scd_id              as host_version_id,
        host_id,
        host_name,
        host_since,
        host_is_superhost,
        host_neighbourhood,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by host_id order by dbt_valid_from) as version_num
    from {{ ref('host_snapshot') }}

)

select
    host_version_id,
    host_id,
    host_name,
    host_since,
    host_is_superhost,
    host_neighbourhood,
    case
        when version_num = 1 then '1900-01-01'::date
        else date_trunc('month', dbt_valid_from)::date
    end                                                                     as valid_from,
    coalesce(date_trunc('month', dbt_valid_to)::date, '9999-12-31'::date)   as valid_to,
    dbt_valid_to is null                                                    as is_current
from versions
