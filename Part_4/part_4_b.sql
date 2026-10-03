
QUESTION B  Is there a correlation between the median age of a neighbourhood and the estimated revenue per active listing of that neighbourhood?

-- In question a I only looked at the 6 extreme LGAs, so I could easily be fooled by two small groups that happen to be different. Here I use all 29 LGAs that have listings so one row per LGA, and I measure how much the two columns move together.
--
-- I give two numbers, because they don't answer exactly the same thing:
-- First Pearson looks for a straight line. It's the usual one, but it gets dragged around by extreme values, and I know Mosman is way above everyone else.
-- then Spearman does the same thing on the ranks instead of the amounts, so Mosman is just number 1 and not number 1 by a mile. If the two numbers are close, the relation is real. If Pearson is much bigger, it means a couple of rich LGAs are carrying it.
--
-- Both go from -1 to +1. Above 0.5 (or below -0.5) is strong, 0.3 to 0.5 is moderate under 0.3 is weak. With only 29 rows I stay careful with the wording either way.


-- same calculation as in question a, I keep it the same so the two answers are consistent
with revenue_per_lga as (

    select
        lga_code,
        sum(estimated_revenue)                      as total_revenue,
        count(*) filter (where has_availability)    as active_listing_months
    from gold.fact_listings
    where lga_code is not null
    group by lga_code

),

-- one row per LGA: its median age from the census, and its revenue per active listing.The join on census_g02 is an inner join, which is fine here because I checked in Part 2 that every LGA with listings has a census row, so I'm not silently dropping any LGA.
per_lga as (

    select
        l.lga_name,
        g2.median_age_persons,
        r.total_revenue / r.active_listing_months    as revenue_per_active_listing
    from revenue_per_lga r
    join gold.dim_lga l
        on  r.lga_code = l.lga_code
        and l.is_current
    join gold.census_g02 g2
        on r.lga_code = g2.lga_code

),

-- For Spearman I need the position of each LGA instead of its value, so I rank both columns.
-- Small detail I should be honest about: median age is a whole number, so several LGAs can have the same age, and rank() gives all of them the lowest position of the tie. The proper way would be to give them the average position, so my Spearman is slightly approximate.
-- I keep it because it's only there as a sanity check next to Pearson.
ranked as (

    select
        *,
        rank() over (order by median_age_persons)            as rank_age,
        rank() over (order by revenue_per_active_listing)    as rank_revenue
    from per_lga

)

select
    count(*)                                                                    as nb_lga,
    round(corr(median_age_persons, revenue_per_active_listing)::numeric, 3)     as pearson_corr,
    round(corr(rank_age, rank_revenue)::numeric, 3)                             as spearman_corr,
    -- I print the two ranges as well, just to show how spread out the data is.
    -- Here the ages only go from 32 to 43, so a correlation built on 11 years of difference is not the same story as one built on 30 years, and I want that visible in the output.
    min(median_age_persons) || ' - ' || max(median_age_persons)                 as median_age_range,
    round(min(revenue_per_active_listing), 2) || ' - '
        || round(max(revenue_per_active_listing), 2)                            as revenue_range
from ranked;



-- b (detail): the 29 LGAs behind the correlation.
-- A single correlation number hides everything, so I also print the rows. I export this result to Excel and make a scatter plot (median age on the x axis, revenue per active
-- listing on the y axis), because the chart shows straight away if the relation is a real trend or just two clumps of LGAs sitting in opposite corners.
-- I add the household size and the median household income on the side. They're not part of the question, but if the age correlation turns out weak, these two tell me whether age was really the interesting variable or just the one I was asked about.

with revenue_per_lga as (

    select
        lga_code,
        sum(estimated_revenue)                      as total_revenue,
        count(*) filter (where has_availability)    as active_listing_months
    from gold.fact_listings
    where lga_code is not null
    group by lga_code

)

select
    l.lga_name,
    g2.median_age_persons                                   as median_age,
    round(r.total_revenue / r.active_listing_months, 2)     as revenue_per_active_listing,
    -- I show this one so I can see which LGAs only have a handful of listings. A LGA with
    -- very few active listing-months can land anywhere by chance, and I'd rather know it
    -- before I comment on its position in the chart.
    r.active_listing_months,
    g2.average_household_size,
    g2.median_tot_hhd_inc_weekly                            as median_household_income_weekly
from revenue_per_lga r
join gold.dim_lga l
    on  r.lga_code = l.lga_code
    and l.is_current
join gold.census_g02 g2
    on r.lga_code = g2.lga_code
order by revenue_per_active_listing desc;
