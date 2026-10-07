-- Silver: host entity, taken out of the listings table. One row per host: the latest month we have seen
-- This table feeds the host snapshot (SCD2) and month_date (the month of the file) is the timestamp that tells dbt when this host information was observed.

with hosts as (

    select
        host_id,
        host_name,
        host_since,
        host_is_superhost,
        host_neighbourhood,
        month_date,
        row_number() over (
            partition by host_id
            order by month_date desc, scraped_date desc, listing_id desc
        ) as row_num
    from {{ ref('silver_listings') }}
    where host_id is not null

)

select
    host_id,
    host_name,
    host_since,
    host_is_superhost,
    host_neighbourhood,
    month_date
from hosts
where row_num = 1
