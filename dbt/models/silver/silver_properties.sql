-- Silver: property entity, taken out of the listings table. One row per listing: the latest month we have seen
-- This table feeds the property snapshot (SCD2), and month_date (the month of the file) is the timestamp that tells dbt when this property information was observed

with properties as (

    select
        listing_id,
        listing_neighbourhood,
        property_type,
        room_type,
        accommodates,
        month_date,
        row_number() over (
            partition by listing_id
            order by month_date desc, scraped_date desc
        ) as row_num
    from {{ ref('silver_listings') }}
    where listing_id is not null

)

select
    listing_id,
    listing_neighbourhood,
    property_type,
    room_type,
    accommodates,
    month_date
from properties
where row_num = 1
