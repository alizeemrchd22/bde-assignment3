-- Datamart: the insights per host_neighbourhood_lga and month
-- host_neighbourhood is a suburb, so I turn it into its LGA with two SCD2 joins fact -> dim_host (the host's suburb that month) -> dim_suburb (that suburb's LGA that month) Hosts with no neighbourhood or living overseas have no NSW LGA, so they go into 'Unknown' instead of being dropped.

with listings as (

    select
        coalesce(s.lga_name, 'Unknown')    as host_neighbourhood_lga,
        f.month_date,
        f.host_id,
        f.has_availability,
        f.estimated_revenue
    from {{ ref('fact_listings') }} f
    join {{ ref('dim_host') }} h
        on  f.host_id = h.host_id
        and f.month_date >= h.valid_from
        and f.month_date <  h.valid_to
    left join {{ ref('dim_suburb') }} s
        on  upper(h.host_neighbourhood) = s.suburb_name_key
        and f.month_date >= s.valid_from
        and f.month_date <  s.valid_to

)

select
    host_neighbourhood_lga,
    month_date                                                                       as month_year,
    count(distinct host_id)                                                          as distinct_hosts,
    round(avg(estimated_revenue) filter (where has_availability), 2)                 as avg_estimated_revenue_per_active_listing,
    -- estimated revenue per host = total revenue of active listings / distinct hosts
    round(sum(estimated_revenue) filter (where has_availability)
          / count(distinct host_id), 2)                                              as estimated_revenue_per_host
from listings
group by host_neighbourhood_lga, month_date
order by host_neighbourhood_lga, month_year
