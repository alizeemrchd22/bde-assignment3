-- Gold: Census G02 as reference data (medians and averages per LGA: age, income, rent, mortgage).
-- Same as G01: it doesn't change over time, so no snapshot. It links to dim_lga with lga_code.

select * from {{ ref('silver_census_g02') }}
