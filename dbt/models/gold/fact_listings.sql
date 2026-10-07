-- Gold the fact table one row per listing per scraped month
-- It only keeps IDs (to join the dimensions) and metrics, like the star schema asks.The LGA code is found with the SCD2 logic: the LGA version that was valid in that month, valid_to is exclusive (<), so a fact row can never match two versions in the month of a change.

with listings as (

    select * from {{ ref('silver_listings') }}

),

lga as (

    select * from {{ ref('dim_lga') }}

)

select
    -- ids
    l.listing_id,
    l.host_id,
    g.lga_code,
    l.scraped_date,
    l.month_date,

    -- metrics
    l.price,
    l.has_availability,
    l.availability_30,
    l.number_of_reviews,
    l.review_scores_rating,
    l.review_scores_accuracy,
    l.review_scores_cleanliness,
    l.review_scores_checkin,
    l.review_scores_communication,
    l.review_scores_value,

    -- number of stays = nights booked in the next 30 days, only for active listings
    case when l.has_availability then 30 - l.availability_30 else 0 end              as number_of_stays,

    -- estimated revenue = number of stays x price, only for active listings
    case when l.has_availability then (30 - l.availability_30) * l.price else 0 end  as estimated_revenue

from listings l
left join lga g
    on upper(l.listing_neighbourhood) = g.lga_name_key
   and l.month_date >= g.valid_from
   and l.month_date <  g.valid_to
