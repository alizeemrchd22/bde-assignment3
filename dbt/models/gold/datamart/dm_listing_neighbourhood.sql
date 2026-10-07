-- Datamart the insights per listing_neighbourhood and month
-- Built on the fact table joined to dim_property and dim_host with the SCD2 logic: for each fact rowI take the version that was valid in that month (month_date >= valid_from and < valid_to), not the latest one.

with listings as (

    select
        p.listing_neighbourhood,
        f.month_date,
        f.host_id,
        f.has_availability,
        f.price,
        f.review_scores_rating,
        f.number_of_stays,
        f.estimated_revenue,
        h.host_is_superhost
    from {{ ref('fact_listings') }} f
    join {{ ref('dim_property') }} p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    join {{ ref('dim_host') }} h
        on  f.host_id = h.host_id
        and f.month_date >= h.valid_from
        and f.month_date <  h.valid_to

),

monthly as (

    select
        listing_neighbourhood,
        month_date,
        count(*)                                                       as total_listings,
        count(*) filter (where has_availability)                       as active_listings,
        count(*) filter (where not has_availability)                   as inactive_listings,
        min(price) filter (where has_availability)                     as min_price,
        max(price) filter (where has_availability)                     as max_price,
        percentile_cont(0.5) within group (order by price)
            filter (where has_availability)                            as median_price,
        avg(price) filter (where has_availability)                     as avg_price,
        count(distinct host_id)                                        as distinct_hosts,
        count(distinct host_id) filter (where host_is_superhost)       as distinct_superhosts,
        avg(review_scores_rating) filter (where has_availability)      as avg_review_scores_rating,
        sum(number_of_stays) filter (where has_availability)           as total_stays,
        avg(estimated_revenue) filter (where has_availability)         as avg_estimated_revenue_per_active_listing
    from listings
    group by listing_neighbourhood, month_date

),

-- previous month values, used for the month to month % change
with_previous as (

    select
        *,
        lag(month_date)        over (partition by listing_neighbourhood order by month_date) as prev_month,
        lag(active_listings)   over (partition by listing_neighbourhood order by month_date) as prev_active,
        lag(inactive_listings) over (partition by listing_neighbourhood order by month_date) as prev_inactive
    from monthly

)

select
    listing_neighbourhood,
    month_date                                                         as month_year,
    round(100.0 * active_listings / total_listings, 2)                 as active_listings_rate,
    min_price,
    max_price,
    round(median_price::numeric, 2)                                    as median_price,
    round(avg_price, 2)                                                as avg_price,
    distinct_hosts,
    round(100.0 * distinct_superhosts / distinct_hosts, 2)             as superhost_rate,
    round(avg_review_scores_rating, 2)                                 as avg_review_scores_rating,
    -- % change only if the previous row is really the month before (null for the first month)
    case when prev_month = (month_date - interval '1 month')::date
         then round(100.0 * (active_listings - prev_active) / nullif(prev_active, 0), 2)
    end                                                                as active_listings_pct_change,
    case when prev_month = (month_date - interval '1 month')::date
         then round(100.0 * (inactive_listings - prev_inactive) / nullif(prev_inactive, 0), 2)
    end                                                                as inactive_listings_pct_change,
    total_stays,
    round(avg_estimated_revenue_per_active_listing, 2)                 as avg_estimated_revenue_per_active_listing
from with_previous
order by listing_neighbourhood, month_year
