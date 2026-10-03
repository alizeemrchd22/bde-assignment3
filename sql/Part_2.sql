-- BDE AT3 - Part 2 - data quality checks on silver, gold and datamart
-- Run in DBeaver (Postgres) after "dbt build".
-- I ran these at the end of Part 2, when only May 2020 was loaded, and the screenshots in my report come from that run. If you run them now with the 12 months loaded, the counts are bigger, but the checks still mean the same thing.

 

-- 1. Silver checks
-- Here I'm checking that the cleaning didn't break anything. I want the same number of rows as in bronze, so nothing got lost, and no duplicate keys. I also compare the NULLs between
-- bronze and silver: if silver had more, it would mean a cast failed. Then I check the values look normal, and that every join key actually finds a match.


SELECT '1. rows listings bronze / silver' AS check_name, (SELECT count(*) FROM bronze.raw_listings) || ' / ' || (SELECT count(*) FROM silver.silver_listings) AS result
UNION ALL SELECT '1. rows lga bronze / silver', (SELECT count(*) FROM bronze.raw_lga_code) || ' / ' || (SELECT count(*) FROM silver.silver_lga)
UNION ALL SELECT '1. rows suburb bronze / silver', (SELECT count(*) FROM bronze.raw_lga_suburb) || ' / ' || (SELECT count(*) FROM silver.silver_suburb)
UNION ALL SELECT '1. rows census g01 / g02', (SELECT count(*) FROM silver.silver_census_g01) || ' / ' || (SELECT count(*) FROM silver.silver_census_g02)
UNION ALL SELECT '2. duplicates listing+date', (SELECT count(*) - count(DISTINCT (listing_id, scraped_date)) FROM silver.silver_listings)::text
UNION ALL SELECT '2. duplicates host_id', (SELECT count(*) - count(DISTINCT host_id) FROM silver.silver_hosts)::text
UNION ALL SELECT '2. duplicates listing_id in properties', (SELECT count(*) - count(DISTINCT listing_id) FROM silver.silver_properties)::text
UNION ALL SELECT '2. duplicates lga_code', (SELECT count(*) - count(DISTINCT lga_code) FROM silver.silver_lga)::text
UNION ALL SELECT '3. null price bronze / silver', (SELECT count(*) FROM bronze.raw_listings WHERE price IS NULL) || ' / ' || (SELECT count(*) FROM silver.silver_listings WHERE price IS NULL)
UNION ALL SELECT '3. null host_since bronze / silver', (SELECT count(*) FROM bronze.raw_listings WHERE host_since IS NULL) || ' / ' || (SELECT count(*) FROM silver.silver_listings WHERE host_since IS NULL)
UNION ALL SELECT '3. null rating bronze / silver', (SELECT count(*) FROM bronze.raw_listings WHERE review_scores_rating IS NULL) || ' / ' || (SELECT count(*) FROM silver.silver_listings WHERE review_scores_rating IS NULL)
UNION ALL SELECT '3. null host_id / listing_id / scraped_date', (SELECT count(*) FILTER (WHERE host_id IS NULL) || ' / ' || count(*) FILTER (WHERE listing_id IS NULL) || ' / ' || count(*) FILTER (WHERE scraped_date IS NULL) FROM silver.silver_listings)
UNION ALL SELECT '4. price min / max', (SELECT min(price) || ' / ' || max(price) FROM silver.silver_listings)
UNION ALL SELECT '4. availability_30 min / max', (SELECT min(availability_30) || ' / ' || max(availability_30) FROM silver.silver_listings)
UNION ALL SELECT '4. rating min / max', (SELECT min(review_scores_rating) || ' / ' || max(review_scores_rating) FROM silver.silver_listings)
UNION ALL SELECT '4. has_availability true / false / null', (SELECT count(*) FILTER (WHERE has_availability) || ' / ' || count(*) FILTER (WHERE NOT has_availability) || ' / ' || count(*) FILTER (WHERE has_availability IS NULL) FROM silver.silver_listings)
UNION ALL SELECT '4. superhost true / false / null', (SELECT count(*) FILTER (WHERE host_is_superhost) || ' / ' || count(*) FILTER (WHERE NOT host_is_superhost) || ' / ' || count(*) FILTER (WHERE host_is_superhost IS NULL) FROM silver.silver_hosts)
UNION ALL SELECT '5a. listing_neighbourhood with no LGA', (SELECT coalesce(string_agg(DISTINCT l.listing_neighbourhood, ', '), 'none') FROM silver.silver_listings l LEFT JOIN silver.silver_lga g ON upper(l.listing_neighbourhood) = g.lga_name_key WHERE g.lga_code IS NULL)
UNION ALL SELECT '5b. hosts with no matching suburb / total hosts', (SELECT count(*) FILTER (WHERE s.suburb_name_key IS NULL AND h.host_neighbourhood IS NOT NULL) || ' / ' || count(*) FROM silver.silver_hosts h LEFT JOIN silver.silver_suburb s ON upper(h.host_neighbourhood) = s.suburb_name_key)
UNION ALL SELECT '5c. top unmatched host_neighbourhood', (SELECT string_agg(x || ' (' || c || ')', ', ') FROM (SELECT h.host_neighbourhood AS x, count(*) AS c FROM silver.silver_hosts h LEFT JOIN silver.silver_suburb s ON upper(h.host_neighbourhood) = s.suburb_name_key WHERE s.suburb_name_key IS NULL AND h.host_neighbourhood IS NOT NULL GROUP BY 1 ORDER BY c DESC LIMIT 15) t)
UNION ALL SELECT '5d. hosts with null host_neighbourhood', (SELECT count(*) FROM silver.silver_hosts WHERE host_neighbourhood IS NULL)::text
UNION ALL SELECT '5e. suburbs with no LGA code', (SELECT count(*) FROM silver.silver_suburb WHERE lga_code IS NULL)::text
UNION ALL SELECT '5f. census codes not in LGA table', (SELECT coalesce(string_agg(c.lga_code::text, ', '), 'none') FROM silver.silver_census_g01 c LEFT JOIN silver.silver_lga g ON c.lga_code = g.lga_code WHERE g.lga_code IS NULL)
UNION ALL SELECT '5g. LGA codes not in census', (SELECT coalesce(string_agg(g.lga_code::text, ', '), 'none') FROM silver.silver_lga g LEFT JOIN silver.silver_census_g01 c ON c.lga_code = g.lga_code WHERE c.lga_code IS NULL);
 
 

-- 2. Here I'm looking at the weird prices, so listings at $0 or above $5,000.
-- In the end I decided to keep them. They're less than 0.2% of the rows, I can't really prove they're mistakes, and they don't change the median price much anyway.

SELECT
    count(*) FILTER (WHERE price = 0)            AS price_zero,
    count(*) FILTER (WHERE price > 5000)         AS price_over_5000,
    (SELECT string_agg(lga_code::text, ', ')
     FROM silver.silver_census_g01 c
     WHERE lga_code NOT IN (SELECT lga_code FROM silver.silver_lga)) AS census_codes_missing
FROM silver.silver_listings;
 
 

-- 3. Gold checks
-- The ones I care about most are 3 and 4. For each fact row, I want exactly one version of the host and one version of the property for that month. If it finds 0, the row would get lost in the joins, and if it finds 2 or more, the row would be counted twice.

SELECT '1. fact rows' AS check_name, (SELECT count(*) FROM gold.fact_listings)::text AS result
UNION ALL SELECT '2. fact rows with no lga_code', (SELECT count(*) FROM gold.fact_listings WHERE lga_code IS NULL)::text
UNION ALL SELECT '3. fact rows matching 0 / 1 / 2+ host versions', (SELECT count(*) FILTER (WHERE n = 0) || ' / ' || count(*) FILTER (WHERE n = 1) || ' / ' || count(*) FILTER (WHERE n > 1) FROM (SELECT f.listing_id, f.scraped_date, count(h.host_id) AS n FROM gold.fact_listings f LEFT JOIN gold.dim_host h ON f.host_id = h.host_id AND f.month_date >= h.valid_from AND f.month_date < h.valid_to GROUP BY 1, 2) t)
UNION ALL SELECT '4. fact rows matching 0 / 1 / 2+ property versions', (SELECT count(*) FILTER (WHERE n = 0) || ' / ' || count(*) FILTER (WHERE n = 1) || ' / ' || count(*) FILTER (WHERE n > 1) FROM (SELECT f.listing_id, f.scraped_date, count(p.listing_id) AS n FROM gold.fact_listings f LEFT JOIN gold.dim_property p ON f.listing_id = p.listing_id AND f.month_date >= p.valid_from AND f.month_date < p.valid_to GROUP BY 1, 2) t)
UNION ALL SELECT '5. fact lga_code with census data', (SELECT count(*) FROM gold.fact_listings f JOIN gold.census_g02 c ON f.lga_code = c.lga_code)::text
UNION ALL SELECT '6. number_of_stays min / max', (SELECT min(number_of_stays) || ' / ' || max(number_of_stays) FROM gold.fact_listings)
-- the label says May 2020, so I filter on May (otherwise it would add up the 12 months)
UNION ALL SELECT '7. total estimated revenue (May 2020)', (SELECT to_char(sum(estimated_revenue), 'FM999,999,999') FROM gold.fact_listings WHERE month_date = '2020-05-01')
UNION ALL SELECT '8. hosts whose suburb gives an LGA / total hosts', (SELECT count(s.lga_code) || ' / ' || count(*) FROM gold.dim_host h LEFT JOIN gold.dim_suburb s ON upper(h.host_neighbourhood) = s.suburb_name_key AND s.is_current)
UNION ALL SELECT '9. dims with more than one current version', (SELECT (SELECT count(*) FROM (SELECT host_id FROM gold.dim_host WHERE is_current GROUP BY 1 HAVING count(*) > 1) a) + (SELECT count(*) FROM (SELECT listing_id FROM gold.dim_property WHERE is_current GROUP BY 1 HAVING count(*) > 1) b))::text;
 
 

-- 4. Datamart checks
-- The views group the data in different ways, but in the end the totals should still match the fact table, so that's what I check here. For lines 4 and 5 I only look at
-- May 2020, because with several months the same host shows up once per month in the view, and 'Unknown' also gets one row per month.

SELECT '1. rows in each view (neighbourhood / property / host lga)' AS check_name, (SELECT count(*) FROM datamart.dm_listing_neighbourhood) || ' / ' || (SELECT count(*) FROM datamart.dm_property_type) || ' / ' || (SELECT count(*) FROM datamart.dm_host_neighbourhood) AS result
UNION ALL SELECT '2. total stays: fact / neighbourhood view / property view', (SELECT sum(number_of_stays) FROM gold.fact_listings) || ' / ' || (SELECT sum(total_stays) FROM datamart.dm_listing_neighbourhood) || ' / ' || (SELECT sum(total_stays) FROM datamart.dm_property_type)
UNION ALL SELECT '3. total revenue: fact / host lga view', (SELECT to_char(sum(estimated_revenue), 'FM999,999,999') FROM gold.fact_listings) || ' / ' || (SELECT to_char(sum(estimated_revenue_per_host * distinct_hosts), 'FM999,999,999') FROM datamart.dm_host_neighbourhood)
UNION ALL SELECT '4. distinct hosts: fact / sum over host lga view', (SELECT count(DISTINCT host_id) FROM gold.fact_listings WHERE month_date = '2020-05-01') || ' / ' || (SELECT sum(distinct_hosts) FROM datamart.dm_host_neighbourhood WHERE month_year = '2020-05-01')
UNION ALL SELECT '5. hosts in Unknown lga', (SELECT distinct_hosts FROM datamart.dm_host_neighbourhood WHERE host_neighbourhood_lga = 'Unknown' AND month_year = '2020-05-01')::text
UNION ALL SELECT '6. active_listings_rate min / max', (SELECT min(active_listings_rate) || ' / ' || max(active_listings_rate) FROM datamart.dm_listing_neighbourhood)
UNION ALL SELECT '7. superhost_rate min / max', (SELECT min(superhost_rate) || ' / ' || max(superhost_rate) FROM datamart.dm_listing_neighbourhood)
UNION ALL SELECT '8. top 3 neighbourhoods by revenue per active listing', (SELECT string_agg(listing_neighbourhood || ' ($' || avg_estimated_revenue_per_active_listing || ')', ', ') FROM (SELECT listing_neighbourhood, avg_estimated_revenue_per_active_listing FROM datamart.dm_listing_neighbourhood ORDER BY 2 DESC LIMIT 3) t);
