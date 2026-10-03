
-- QUESTION D For hosts with multiple listings, are their properties concentrated in the same LGA or spread across different LGAs?

-- Before answering I want to know how big this population actually is, because if only 2% of the hosts have several listings, the answer is a detail, and if it's 30% it's a real part of the market. So this first query just sets the scene.

-- I count the listings of a host over the whole 12 months. A host could have had one listing in 2020 and replaced it by another one in 2021, and my count would call that
-- "2 listings" even though they never had two at the same time. So I also compute the maximum number of listings they had in a single month, which is the stricter version and I compare the two.


with per_host_month as (

    select
        host_id,
        month_date,
        count(distinct listing_id)  as listings_that_month,
        count(distinct lga_code)    as lgas_that_month
    from gold.fact_listings
    where lga_code is not null
    group by host_id, month_date

),

per_host as (

    select
        host_id,
        max(listings_that_month)    as max_listings_in_one_month,
        max(lgas_that_month)        as max_lgas_in_one_month,
        sum(listings_that_month)    as listing_months
    from per_host_month
    group by host_id

),

-- the same thing but over the whole year, so one line per host
over_the_year as (

    select
        host_id,
        count(distinct listing_id)  as nb_listings,
        count(distinct lga_code)    as nb_lga
    from gold.fact_listings
    where lga_code is not null
    group by host_id

),

hosts as (

    select
        y.host_id,
        y.nb_listings,
        y.nb_lga,
        h.max_listings_in_one_month,
        h.max_lgas_in_one_month,
        h.listing_months
    from over_the_year y
    join per_host h on y.host_id = h.host_id

)

select
    case when nb_listings = 1 then 'single listing' else 'multiple listings' end  as host_type,
    count(*)                                                                      as nb_hosts,
    round(100.0 * count(*) / sum(count(*)) over (), 1)                            as pct_of_hosts,
    sum(nb_listings)                                                              as nb_listings,
    round(100.0 * sum(nb_listings) / sum(sum(nb_listings)) over (), 1)            as pct_of_listings,
    -- the stricter version: hosts who really had 2 listings at the same time in a month
    count(*) filter (where max_listings_in_one_month > 1)                         as hosts_with_2_at_once
from hosts
group by 1
order by 1;




-- HERE IS THE ANSWER TO D:  for the hosts with several listings, are they all in the same LGA or not?

-- I split them by portfolio size, because I expect someone with 2 listings to keep them next to each other, and someone with 20 to spread out. Showing only one global percentage would hide that completely.

-- Like in question a, I build the detail lines and the total line separately and I stack  them with union all, with a sort_order column so the total stays at the bottom.

with per_host_month as (

    select
        host_id,
        month_date,
        count(distinct lga_code) as lgas_that_month
    from gold.fact_listings
    where lga_code is not null
    group by host_id, month_date

),

over_the_year as (

    select
        host_id,
        count(distinct listing_id)  as nb_listings,
        count(distinct lga_code)    as nb_lga
    from gold.fact_listings
    where lga_code is not null
    group by host_id

),

multi_hosts as (

    select
        y.host_id,
        y.nb_listings,
        y.nb_lga,
        max(m.lgas_that_month) as max_lgas_in_one_month,
        -- the bucket, plus a number next to it only so the table comes out in the right
        -- order instead of being sorted alphabetically
        case
            when y.nb_listings = 2              then '2 listings'
            when y.nb_listings between 3 and 5  then '3 to 5 listings'
            when y.nb_listings between 6 and 10 then '6 to 10 listings'
            else                                     '11 listings or more'
        end as portfolio_size,
        case
            when y.nb_listings = 2              then 1
            when y.nb_listings between 3 and 5  then 2
            when y.nb_listings between 6 and 10 then 3
            else                                     4
        end as sort_order
    from over_the_year y
    join per_host_month m on y.host_id = m.host_id
    where y.nb_listings >= 2
    group by y.host_id, y.nb_listings, y.nb_lga

),

-- one line per portfolio size
by_bucket as (

    select
        sort_order,
        portfolio_size,
        count(*)                                                        as nb_hosts,
        sum(nb_listings)                                                as nb_listings,
        count(*) filter (where nb_lga = 1)                              as hosts_in_one_lga,
        round(100.0 * count(*) filter (where nb_lga = 1) / count(*), 1) as pct_in_one_lga,
        round(avg(nb_lga), 2)                                           as avg_nb_lga,
        max(nb_lga)                                                     as max_nb_lga,
        -- same question but looking at one month at a time, as a check that my yearly
        -- count isn't just picking up hosts who moved from one LGA to another
        count(*) filter (where max_lgas_in_one_month = 1)               as hosts_in_one_lga_same_month
    from multi_hosts
    group by sort_order, portfolio_size

),

-- the total line, computed on all the multi-listing hosts at once
overall as (

    select
        9,
        'ALL multi-listing hosts',
        count(*),
        sum(nb_listings),
        count(*) filter (where nb_lga = 1),
        round(100.0 * count(*) filter (where nb_lga = 1) / count(*), 1),
        round(avg(nb_lga), 2),
        max(nb_lga),
        count(*) filter (where max_lgas_in_one_month = 1)
    from multi_hosts

),

combined as (

    select * from by_bucket
    union all
    select * from overall

)

select
    portfolio_size,
    nb_hosts,
    nb_listings,
    hosts_in_one_lga,
    pct_in_one_lga,
    avg_nb_lga,
    max_nb_lga,
    hosts_in_one_lga_same_month
from combined
order by sort_order;
