-- Silver cleaned version of the raw Airbnb listings, one row per listing per month
-- Bronze stores everything as TEXT, so here I cast each column to its real type the month comes from the file name, because 07_2020.csv has rows scraped up to September

with source as (

    select * from {{ source('bronze', 'raw_listings') }}

),

cleaned as (

    select
        -- ids
        listing_id::numeric::bigint                        as listing_id,
        host_id::numeric::bigint                           as host_id,

        -- dates: scraped_date is YYYY-MM-DD, host_since is D/M/YYYY
        scraped_date::date                                 as scraped_date,
        to_date(host_since, 'DD/MM/YYYY')                  as host_since,

        -- month of the file (MM_YYYY.csv), e.g. 07_2020.csv -> 2020-07-01
        make_date(substr(source_file, 4, 4)::int, substr(source_file, 1, 2)::int, 1) as month_date,

        -- host attributes
        trim(host_name)                                    as host_name,
        host_is_superhost = 't'                            as host_is_superhost,
        trim(host_neighbourhood)                           as host_neighbourhood,

        -- property attributes
        trim(listing_neighbourhood)                        as listing_neighbourhood,
        trim(property_type)                                as property_type,
        trim(room_type)                                    as room_type,
        accommodates::numeric::int                         as accommodates,

        -- metrics
        price::numeric(10, 2)                              as price,
        has_availability = 't'                             as has_availability,
        availability_30::numeric::int                      as availability_30,
        number_of_reviews::numeric::int                    as number_of_reviews,
        review_scores_rating::numeric(5, 2)                as review_scores_rating,
        review_scores_accuracy::numeric(5, 2)              as review_scores_accuracy,
        review_scores_cleanliness::numeric(5, 2)           as review_scores_cleanliness,
        review_scores_checkin::numeric(5, 2)               as review_scores_checkin,
        review_scores_communication::numeric(5, 2)         as review_scores_communication,
        review_scores_value::numeric(5, 2)                 as review_scores_value,

        -- load metadata
        source_file,
        loaded_at::timestamp                               as loaded_at

    from source

),

-- safety net: keep only one row per listing per month (the latest scrape)
deduplicated as (

    select
        *,
        row_number() over (
            partition by listing_id, month_date
            order by scraped_date desc, loaded_at desc
        ) as row_num
    from cleaned

)

select
    listing_id, host_id, scraped_date, month_date, host_since,
    host_name, host_is_superhost, host_neighbourhood,
    listing_neighbourhood, property_type, room_type, accommodates,
    price, has_availability, availability_30, number_of_reviews,
    review_scores_rating, review_scores_accuracy, review_scores_cleanliness,
    review_scores_checkin, review_scores_communication, review_scores_value,
    source_file, loaded_at
from deduplicated
where row_num = 1
