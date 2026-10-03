
-- QUESTION C What is the best type of listing (property type, room type, accommodates) for the top 5 listing_neighbourhoods (by average estimated revenue per active listing) to have the highest number of stays?

-- I do it in two steps. First I find the top 5 neighbourhoods, with exactly the same  calculation as in questions a and b so my three answers stay consistent. Then inside  those 5 only I group the listings by property type room type and capacity, and I look at the stays.

-- One thing I want to be careful about: "the highest number of stays" can mean two different things. The total number of stays mostly depends on how many listings of that type exist, so the winner is probably just going to be the most common type in the area.
-- That's the literal answer to the question so I give it first, but I also print the average number of stays per active listing per month, which tells me which type actually  gets booked the most. I look at both before I write my recommendation.


-- Step 1: revenue per active listing for every neighbourhood, over the 12 months.
-- Here I go through dim_property to get listing_neighbourhood, with the SCD2 join (the version of the listing that was valid in that month), and not just the latest one.
-- In this dataset listing_neighbourhood is the same thing as the LGA name, so I get the same ranking as in question a, which is a good sign that I didn't mix anything up.
with revenue_per_neighbourhood as (

    select
        p.listing_neighbourhood,
        sum(f.estimated_revenue) / count(*) filter (where f.has_availability) as revenue_per_active_listing
    from gold.fact_listings f
    join gold.dim_property p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    group by p.listing_neighbourhood

),

top5 as (

    select
        listing_neighbourhood,
        revenue_per_active_listing
    from revenue_per_neighbourhood
    order by revenue_per_active_listing desc
    limit 5

),

-- Step 2: inside those 5 neighbourhoods, one row per combination of property type + room type + capacity.
-- I don't filter number_of_stays, because in my fact table it's already 0 when the listing is not active, so summing everything only counts the active ones.
-- For the averages I do add the filter, otherwise all the inactive rows with 0 would drag the average down and the number wouldn't mean anything.
by_type as (

    select
        p.listing_neighbourhood,
        p.property_type,
        p.room_type,
        p.accommodates,
        count(*) filter (where f.has_availability)                              as active_listing_months,
        sum(f.number_of_stays)                                                  as total_stays,
        round(avg(f.number_of_stays) filter (where f.has_availability), 1)      as avg_stays_per_month,
        round(avg(f.price) filter (where f.has_availability), 2)                as avg_price,
        round(avg(f.estimated_revenue) filter (where f.has_availability), 2)    as avg_revenue_per_active_listing
    from gold.fact_listings f
    join gold.dim_property p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    join top5 t
        on p.listing_neighbourhood = t.listing_neighbourhood
    group by p.listing_neighbourhood, p.property_type, p.room_type, p.accommodates

),

-- I rank the combinations inside each neighbourhood, so each area gets its own top 3. partition by is what makes the ranking restart at 1 for every neighbourhood.
ranked as (

    select
        *,
        rank() over (partition by listing_neighbourhood order by total_stays desc) as rank_by_total_stays
    from by_type

)

select
    r.listing_neighbourhood,
    r.rank_by_total_stays,
    r.property_type,
    r.room_type,
    r.accommodates,
    r.total_stays,
    r.active_listing_months,
    r.avg_stays_per_month,
    r.avg_price,
    r.avg_revenue_per_active_listing
from ranked r
join top5 t
    on r.listing_neighbourhood = t.listing_neighbourhood
where r.rank_by_total_stays <= 3
-- I sort the neighbourhoods by their revenue, so the table reads in the same order
-- as the top 5 I announced just before
order by t.revenue_per_active_listing desc, r.rank_by_total_stays;







-- SECOND PART OF C : the question is : is any type actually better at filling up, or is the first table just telling me which type is the most common?

-- In the first table all the average stays were sitting between 23 and 26 nights out of 30 which made me think the type of listing doesn't really change the occupancy. So here I rank the same combinations by average stays per month instead of total stays, to check it properly instead of just eyeballing the numbers.

-- I add a volume filter: at least 120 active listing-months, which is about 10 listings present all year. Without it the winner would be some one-off listing that happened to be booked every night, and that tells me nothing about what to recommend.

with revenue_per_neighbourhood as (

    select
        p.listing_neighbourhood,
        sum(f.estimated_revenue) / count(*) filter (where f.has_availability) as revenue_per_active_listing
    from gold.fact_listings f
    join gold.dim_property p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    group by p.listing_neighbourhood

),

top5 as (

    select
        listing_neighbourhood,
        revenue_per_active_listing
    from revenue_per_neighbourhood
    order by revenue_per_active_listing desc
    limit 5

),

by_type as (

    select
        p.listing_neighbourhood,
        p.property_type,
        p.room_type,
        p.accommodates,
        count(*) filter (where f.has_availability)                              as active_listing_months,
        sum(f.number_of_stays)                                                  as total_stays,
        round(avg(f.number_of_stays) filter (where f.has_availability), 1)      as avg_stays_per_month,
        round(avg(f.price) filter (where f.has_availability), 2)                as avg_price,
        round(avg(f.estimated_revenue) filter (where f.has_availability), 2)    as avg_revenue_per_active_listing
    from gold.fact_listings f
    join gold.dim_property p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    join top5 t
        on p.listing_neighbourhood = t.listing_neighbourhood
    group by p.listing_neighbourhood, p.property_type, p.room_type, p.accommodates
    having count(*) filter (where f.has_availability) >= 120

),

-- this time I rank on the average, and I keep the rank on the total as well, so I can see in the same table whether the type that fills up best is also the most common one
ranked as (

    select
        *,
        rank() over (partition by listing_neighbourhood order by avg_stays_per_month desc) as rank_by_occupancy,
        -- careful: this rank is computed on the filtered list, so it is not exactly the same number as in the first query. It barely changes anything in practice, because a combination with less than 120 listing-months can't reach the top on total stays.
        rank() over (partition by listing_neighbourhood order by total_stays desc)         as rank_by_total_stays,
        -- the gap between the best and the worst type, among the ones that passed the 120 filter. If this stays small, it means picking a type barely changes how full the listing is.
        max(avg_stays_per_month) over (partition by listing_neighbourhood)
            - min(avg_stays_per_month) over (partition by listing_neighbourhood)           as spread_in_the_area
    from by_type

)

select
    r.listing_neighbourhood,
    r.rank_by_occupancy,
    r.rank_by_total_stays,
    r.property_type,
    r.room_type,
    r.accommodates,
    r.avg_stays_per_month,
    r.spread_in_the_area,
    r.active_listing_months,
    r.avg_price,
    r.avg_revenue_per_active_listing
from ranked r
join top5 t
    on r.listing_neighbourhood = t.listing_neighbourhood
where r.rank_by_occupancy <= 3
order by t.revenue_per_active_listing desc, r.rank_by_occupancy;
