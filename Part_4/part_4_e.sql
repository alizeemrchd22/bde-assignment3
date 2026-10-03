
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
