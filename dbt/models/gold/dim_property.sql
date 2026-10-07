-- Gold: the property dimension is built from the property snapshot so there's one row per version of a listing SCD2
-- Same idea as dim_host: valid_from / valid_to are moved to the start of the month,and the first version of each listing is valid from 1900-01-01

with versions as (

    select
        dbt_scd_id              as property_version_id,
        listing_id,
        listing_neighbourhood,
        property_type,
        room_type,
        accommodates,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by listing_id order by dbt_valid_from) as version_num
    from {{ ref('property_snapshot') }}

)

select
    property_version_id,
    listing_id,
    listing_neighbourhood,
    property_type,
    room_type,
    accommodates,
    case
        when version_num = 1 then '1900-01-01'::date
        else date_trunc('month', dbt_valid_from)::date
    end                                                                     as valid_from,
    coalesce(date_trunc('month', dbt_valid_to)::date, '9999-12-31'::date)   as valid_to,
    dbt_valid_to is null                                                    as is_current
from versions
