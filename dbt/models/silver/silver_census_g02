-- Silver: 2016 Census G02 (medians and averages per LGA).
-- Fixes:
--   1. lga_code_2016 looks like 'LGA10050', so I remove the 'LGA' prefix and cast it to int, to match the code in silver_lga
--   2. medians are whole numbers (int), but the two averages have decimals  (e.g. 2.6 people per household), so I keep them as numeric

select
    replace(lga_code_2016, 'LGA', '')::int               as lga_code,
    median_age_persons::numeric::int                     as median_age_persons,
    median_mortgage_repay_monthly::numeric::int          as median_mortgage_repay_monthly,
    median_tot_prsnl_inc_weekly::numeric::int            as median_tot_prsnl_inc_weekly,
    median_rent_weekly::numeric::int                     as median_rent_weekly,
    median_tot_fam_inc_weekly::numeric::int              as median_tot_fam_inc_weekly,
    median_tot_hhd_inc_weekly::numeric::int              as median_tot_hhd_inc_weekly,
    average_num_psns_per_bedroom::numeric(4, 2)          as average_num_psns_per_bedroom,
    average_household_size::numeric(4, 2)                as average_household_size,
    loaded_at::timestamp                                 as loaded_at
from {{ source('bronze', 'raw_census_g02') }}
