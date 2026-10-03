
-- BDE AT3 - Part 4 - ad-hoc analysis
-- I ran all of this in DBeaver (Postgres), after the 12 months were loaded in Part 3 so the data goes from May 2020 to April 2021.
-- Each question is one query. I ran them one by one and took a screenshot of each result for the report.




-- a. What are the demographic differences (age groups, household size) between
--    the top 3 and the bottom 3 LGAs by estimated revenue per active listing?

-- The first thing I had to decide is what "revenue per active listing over the 12 months" actually means because there are two ways to get it and they don't give the same number.
-- My datamart already gives an average per month, but if I just take the average of those 12 monthly averages, every month counts the same, even a month where the LGA only had a handful of active listings. So I go back to the fact table and do it in one shot:
-- all the revenue of the LGA divided by the number of active listing-months. That way a month with more listings weighs more, which is what I want for a yearly figure.

-- Then I take the 3 best and the 3 worst LGAs and I put the census data next to them so I can compare the age groups and the household size side by side.


-- Step 1: the two numbers I need for each LGA, over the whole year. In my fact table estimated_revenue is already 0 for inactive listings, so summing everything only adds up the active ones, I don't need a filter there.
-- Counting the rows where has_availability is true gives me the number of active listing-months, so a listing that stayed active all year counts 12 times. That's on purpose: it's a "per active listing per month" figure, summed over the year.
with revenue_per_lga as (

    select
        lga_code,
        sum(estimated_revenue)                      as total_revenue,
        count(*) filter (where has_availability)    as active_listing_months
    from gold.fact_listings
    where lga_code is not null
    group by lga_code

),

-- Step 2: I rank the LGAs twice, once starting from the best and once from the worst.
-- Doing both ranks in the same query means I don't have to run it twice and glue the two results together by hand. I join dim_lga to get the name instead of just the code, and
-- I keep is_current so I only get one row per LGA (dim_lga is SCD2, so a code can have several versions).
ranked as (

    select
        r.lga_code,
        l.lga_name,
        r.total_revenue,
        r.active_listing_months,
        r.total_revenue / r.active_listing_months                               as revenue_per_active_listing,
        rank() over (order by r.total_revenue / r.active_listing_months desc)   as rank_top,
        rank() over (order by r.total_revenue / r.active_listing_months asc)    as rank_bottom
    from revenue_per_lga r
    join gold.dim_lga l
        on  r.lga_code = l.lga_code
        and l.is_current

),

-- Step 3: I keep only the 6 LGAs I care about, and I tag each one with its group so I can see straight away in the result which side it's on.
selected as (

    select
        lga_code,
        lga_name,
        total_revenue,
        active_listing_months,
        revenue_per_active_listing,
        case when rank_top <= 3 then 'Top 3' else 'Bottom 3' end as revenue_group
    from ranked
    where rank_top <= 3 or rank_bottom <= 3

),

-- Step 4: here I bring the census in.
-- G01 gives me 13 narrow age bands, which is way too many for a table in a report, so Iadd them up into 5 bigger bands that I can actually talk about: kids and teenagers young adults, middle aged, close to retirement and elderly.
-- I only use the "_p" columns, which are the total persons. The "_m" and "_f" ones are men and women, and the "age_psns_att_educ_inst_" ones are people attending school, not population, so those would be wrong here.
-- G02 gives me the median age and the average household size, those two are ready to use.
base as (

    select
        s.revenue_group,
        s.lga_name,
        s.total_revenue,
        s.active_listing_months,
        s.revenue_per_active_listing,
        g1.age_0_4_yr_p + g1.age_5_14_yr_p + g1.age_15_19_yr_p   as p_0_19,
        g1.age_20_24_yr_p + g1.age_25_34_yr_p                    as p_20_34,
        g1.age_35_44_yr_p + g1.age_45_54_yr_p                    as p_35_54,
        g1.age_55_64_yr_p + g1.age_65_74_yr_p                    as p_55_74,
        g1.age_75_84_yr_p + g1.age_85ov_p                        as p_75_plus,
        g1.tot_p_p,
        g2.median_age_persons,
        g2.average_household_size
    from selected s
    join gold.census_g01 g1 on s.lga_code = g1.lga_code
    join gold.census_g02 g2 on s.lga_code = g2.lga_code

),

-- Step 5: one row per LGA, with the age bands turned into percentages so I can compare a small LGA with a big one.
-- I divide by the sum of my 5 bands and not by tot_p_p on purpose. The ABS changes the totals a tiny bit for privacy, so tot_p_p is not exactly equal to the sum of the bands.
-- Dividing by the sum means my 5 percentages always add up to 100, and nobody can ask me why the line doesn't add up.
det ail as (

    select
        1                                                                                   as sort_in_group,
        revenue_group,
        lga_name,
        round(revenue_per_active_listing, 2)                                                as revenue_per_active_listing,
        tot_p_p                                                                             as population,
        median_age_persons                                                                  as median_age,
        average_household_size                                                              as avg_household_size,
        round(100.0 * p_0_19    / (p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)    as pct_0_19,
        round(100.0 * p_20_34   / (p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)    as pct_20_34,
        round(100.0 * p_35_54   / (p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)    as pct_35_54,
        round(100.0 * p_55_74   / (p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)    as pct_55_74,
        round(100.0 * p_75_plus / (p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)    as pct_75_plus
    from base

),

-- Step 6: same thing, but for the 3 LGAs of a group together so I get one summary line per group and the comparison is easy to read in the report.
-- I weight everything by population otherwise Mosman with 28k people would count as much as Northern Beaches with 252k and the "average" wouldn't mean anything.
-- For the median age I have to be careful: you can't compute a real median out of medians. So this line is the population weighted average of the 3 median ages, not a true median.
-- I keep it because it's still useful to compare the two groups, but I say what it is.
grouped as (

    select
        2,
        revenue_group,
        'ALL 3 (weighted)',
        round(sum(total_revenue) / sum(active_listing_months), 2),
        sum(tot_p_p),
        round(sum(median_age_persons * tot_p_p)::numeric / sum(tot_p_p), 1),
        round(sum(average_household_size * tot_p_p) / sum(tot_p_p), 2),
        round(100.0 * sum(p_0_19)    / sum(p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1),
        round(100.0 * sum(p_20_34)   / sum(p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1),
        round(100.0 * sum(p_35_54)   / sum(p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1),
        round(100.0 * sum(p_55_74)   / sum(p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1),
        round(100.0 * sum(p_75_plus) / sum(p_0_19 + p_20_34 + p_35_54 + p_55_74 + p_75_plus), 1)
    from base
    group by revenue_group

),

-- I put the 6 LGA lines and the 2 summary lines in the same result, sort_in_group is only there so the summary line comes after its own 3 LGAs. I don't show it in the final select, I only use it to sort.
combined as (

    select * from detail
    union all
    select * from grouped

)

select
    revenue_group,
    lga_name,
    revenue_per_active_listing,
    population,
    median_age,
    avg_household_size,
    pct_0_19,
    pct_20_34,
    pct_35_54,
    pct_55_74,
    pct_75_plus
from combined
-- revenue_group desc puts "Top 3" before "Bottom 3", because T comes after B in the alphabet
order by revenue_group desc, sort_in_group, revenue_per_active_listing desc;


-- a (extra check): is my top 3 / bottom 3 the same if I compute the revenue the other way?
-- Here I compare my calculation (all the revenue of the year divided by all the active listing-months) with the simple average of the 12 monthly averages from my datamart.
-- The two columns are not on the same scale, because the datamart one is a monthly figure and mine is a yearly one, so I don't compare the amounts. I only compare the two ranks.
-- If the ranks match at the top and at the bottom, it means my answer to question a doesn't depend on how I chose to average, which is what I wanted to check.

with my_way as (

    select
        l.lga_name,
        sum(f.estimated_revenue) / count(*) filter (where f.has_availability) as rev_my_way
    from gold.fact_listings f
    join gold.dim_lga l
        on  f.lga_code = l.lga_code
        and l.is_current
    group by l.lga_name

),

avg_of_months as (

    select
        listing_neighbourhood,
        avg(avg_estimated_revenue_per_active_listing) as rev_avg_of_months
    from datamart.dm_listing_neighbourhood
    group by listing_neighbourhood

)

select
    m.lga_name,
    round(m.rev_my_way, 2)                              as rev_my_way_yearly,
    round(d.rev_avg_of_months, 2)                       as rev_avg_of_months,
    rank() over (order by m.rev_my_way desc)            as rank_my_way,
    rank() over (order by d.rev_avg_of_months desc)     as rank_avg_of_months
from my_way m
join avg_of_months d
    -- the two tables don't write the names the same way, so I join on upper case
    on upper(m.lga_name) = upper(d.listing_neighbourhood)
order by rank_my_way;
