-- BDE AT3 - Part 4 - ad-hoc analysis
-- I ran all of this in DBeaver (Postgres), after the 12 months were loaded in Part 3 so the data goes from May 2020 to April 2021.
-- Each question is one query. I ran them one by one and took a screenshot of each result for the report.




-- a. What are the demographic differences (age groups, household size) between
--    the top 3 and the bottom 3 LGAs by estimated revenue per active listing?

-- The first thing I had to decide is what "revenue per active listing" actually means over 12 months, because there are two ways to get it and they don't give the same number.
-- My datamart already gives an average per month, but if I just take the average of those 12 monthly averages, every month counts the same, even a month where the LGA only had a handful of active listings. So I go back to the fact table and do it in one shot:
-- all the revenue of the LGA divided by the number of active listing-months. That way a month with more listings weighs more, which is what I want.

-- Then I take the 3 best and the 3 worst LGAs and I put the census data next to them so I can compare the age groups and the household size side by side.


-- Step 1: the two numbers I need for each LGA, over the whole year. In my fact table estimated_revenue is already 0 for inactive listings, so summing everything only adds up the active ones, I don't need a filter there.
-- Counting the rows where has_availability is true gives me the number of active listing-months, so a listing that stayed active all year counts 12 times.
-- Dividing one by the other gives the average revenue of one active listing in one month, measured over the whole year. It's a monthly amount, not a yearly total, and I have to say it that way in the report.
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
-- G01 gives me 13 narrow age bands, which is way too many for a table in a report, so I add them up into 5 bigger bands that I can actually talk about: kids and teenagers, young adults, middle aged, close to retirement and elderly.
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
detail as (

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
-- Both are monthly amounts, so the two columns are on the same scale and they come out very close. They are not exactly equal, because mine gives more weight to the months with more
-- active listings while the datamart one gives every month the same weight. What I really check here are the two rank columns: if they match at the top and at the bottom, my answer
-- to question a doesn't depend on how I chose to average.

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
    round(m.rev_my_way, 2)                              as rev_my_way_weighted,
    round(d.rev_avg_of_months, 2)                       as rev_avg_of_months,
    rank() over (order by m.rev_my_way desc)            as rank_my_way,
    rank() over (order by d.rev_avg_of_months desc)     as rank_avg_of_months
from my_way m
join avg_of_months d
    -- the two tables don't write the names the same way, so I join on upper case
    on upper(m.lga_name) = upper(d.listing_neighbourhood)
order by rank_my_way;


-- QUESTION B  Is there a correlation between the median age of a neighbourhood and the estimated revenue per active listing of that neighbourhood?

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


-- FINAL QUETSION E : For hosts with only one listing, does their estimated revenue over the last 12 month cover the annualised median mortgage repayment of the LGA? And which LGA has the  highest percentage of hosts that can cover it?

-- The census gives median_mortgage_repay_monthly, so I multiply it by 12 to get a yearly amount, and I compare it with everything that host earned over the 12 months.

-- Which LGA do I use? The one of the listing, not the one of the host. The host's own suburb would make more sense economically, because the mortgage is on their own home,
-- but 39% of the hosts have an empty host_neighbourhood and 91 of them live overseas, so I  would lose almost half of my hosts. I keep the listing's LGA, which works for everybody, and I say in the report that this is an assumption.

-- One thing I have to be careful about: not every listing is in all 12 files. Someone whose listing only shows up in 3 months obviously earns less over the year, and counting them
-- as "cannot cover the mortgage" would not be fair. So I give the percentage twice, once on all the single-listing hosts and once only on those who were there all 12 months.


with per_host as (

    select
        host_id,
        count(distinct listing_id)  as nb_listings,
        count(distinct month_date)  as months_present,
        -- a single-listing host only has one LGA, so min() is just a way of picking it up
        min(lga_code)               as lga_code,
        sum(estimated_revenue)      as revenue_12m
    from gold.fact_listings
    where lga_code is not null
    group by host_id

),

single_hosts as (

    select *
    from per_host
    where nb_listings = 1

),

with_mortgage as (

    select
        l.lga_name,
        s.host_id,
        s.months_present,
        s.revenue_12m,
        g2.median_mortgage_repay_monthly * 12 as annual_mortgage
    from single_hosts s
    join gold.dim_lga l
        on  s.lga_code = l.lga_code
        and l.is_current
    join gold.census_g02 g2
        on s.lga_code = g2.lga_code

),

-- one line per LGA
by_lga as (

    select
        1                                                                           as sort_order,
        lga_name,
        count(*)                                                                    as nb_single_hosts,
        -- the mortgage is the same for everybody in the LGA, so max() just picks that value
        max(annual_mortgage)                                                        as annual_mortgage,
        round(percentile_cont(0.5) within group (order by revenue_12m)::numeric, 2) as median_revenue_12m,
        count(*) filter (where revenue_12m >= annual_mortgage)                      as hosts_covering,
        round(100.0 * count(*) filter (where revenue_12m >= annual_mortgage)
              / count(*), 1)                                                        as pct_covering,
        count(*) filter (where months_present = 12)                                 as hosts_all_year,
        round(100.0 * count(*) filter (where months_present = 12 and revenue_12m >= annual_mortgage)
              / nullif(count(*) filter (where months_present = 12), 0), 1)          as pct_covering_all_year
    from with_mortgage
    group by lga_name

),

-- the same thing on everybody, so the overall answer comes out on the last line.
-- The mortgage is different in each LGA, so there is nothing to put in that column here
-- and I leave it empty.
overall as (

    select
        2,
        'ALL LGAs',
        count(*),
        null::int,
        round(percentile_cont(0.5) within group (order by revenue_12m)::numeric, 2),
        count(*) filter (where revenue_12m >= annual_mortgage),
        round(100.0 * count(*) filter (where revenue_12m >= annual_mortgage)
              / count(*), 1),
        count(*) filter (where months_present = 12),
        round(100.0 * count(*) filter (where months_present = 12 and revenue_12m >= annual_mortgage)
              / nullif(count(*) filter (where months_present = 12), 0), 1)
    from with_mortgage

),

combined as (

    select * from by_lga
    union all
    select * from overall

)

select
    lga_name,
    nb_single_hosts,
    annual_mortgage,
    median_revenue_12m,
    hosts_covering,
    pct_covering,
    hosts_all_year,
    pct_covering_all_year
from combined
-- sort_order keeps the total line at the bottom, the LGAs are sorted by their percentage
order by sort_order, pct_covering desc;
