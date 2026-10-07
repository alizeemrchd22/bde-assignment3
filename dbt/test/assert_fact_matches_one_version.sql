-- this test checks my SCD2 joins so for each fact row I count how many host versions and property versions were valid in that month. It should always be exactly one.
-- if it's 0 the row would disappear from the datamart, and if it's 2 the row would be counted twice the test returns the bad rows, so if it returns nothing, everything is fine.

with host_matches as (

    select f.listing_id, f.month_date, count(h.host_id) as nb_versions
    from {{ ref('fact_listings') }} f
    left join {{ ref('dim_host') }} h
        on  f.host_id = h.host_id
        and f.month_date >= h.valid_from
        and f.month_date <  h.valid_to
    group by f.listing_id, f.month_date

),

property_matches as (

    select f.listing_id, f.month_date, count(p.listing_id) as nb_versions
    from {{ ref('fact_listings') }} f
    left join {{ ref('dim_property') }} p
        on  f.listing_id = p.listing_id
        and f.month_date >= p.valid_from
        and f.month_date <  p.valid_to
    group by f.listing_id, f.month_date

)

select 'host' as dimension, * from host_matches where nb_versions <> 1
union all
select 'property' as dimension, * from property_matches where nb_versions <> 1
