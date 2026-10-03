
-- BDE AT3 - Part 3 - resets and checks
-- I ran all of this in DBeaver (Postgres). The blocks follow the order I actually did things in Part 3. I didn't run them all in one go, because the DAG and the dbt job had to run in between, so don't run the whole file at once.

 
 
-- 1. Reset before running the DAG for the first time
-- The brief says to truncate all the tables before the first run, so that's what I do here. I empty bronze so the DAG loads the reference files and every month again from the start.
-- I also drop the snapshots, because "dbt run --full-refresh" doesn't rebuild them, and they still had May 2020 in them from Part 2. dbt creates them again on the next build, so the history starts clean from May 2020.
-- I don't need to reset silver, gold or the datamart, because dbt build rebuilds them every time.

TRUNCATE bronze.raw_listings, bronze.raw_census_g01, bronze.raw_census_g02,
         bronze.raw_lga_code, bronze.raw_lga_suburb;
 
DROP TABLE IF EXISTS silver.host_snapshot, silver.property_snapshot,
                     silver.lga_snapshot, silver.suburb_snapshot;
 
-- check: every count should be 0
SELECT 'raw_listings' AS table_name, count(*) FROM bronze.raw_listings
UNION ALL SELECT 'raw_census_g01', count(*) FROM bronze.raw_census_g01
UNION ALL SELECT 'raw_census_g02', count(*) FROM bronze.raw_census_g02
UNION ALL SELECT 'raw_lga_code', count(*) FROM bronze.raw_lga_code
UNION ALL SELECT 'raw_lga_suburb', count(*) FROM bronze.raw_lga_suburb;
 
 

-- 2. Monthly check: I ran this after every month, so after the DAG run and then the dbt job.
-- What I look for:
--   lines 2 and 3: the same months in both, one for each file I loaded, so no fake month
--   line 4: the fact table has the same number of rows as silver, so the joins didn't lose or double anything
--   lines 5 and 6: the last two numbers are equal, so each host and each listing has only one current version
--   line 7: this goes up when hosts change their superhost status, and it jumps in Jul, Oct, Jan and Apr
--   line 8: should be 29 neighbourhoods x (number of months - 1)
-- After April 2021 I got 12 months, 412122 / 412122 and 319, so everything matched.

SELECT '1. bronze: rows per month file' AS check_name,
       (SELECT string_agg(source_file || ' = ' || n, ', ' ORDER BY substr(source_file, 4, 4), substr(source_file, 1, 2))
        FROM (SELECT source_file, count(*) AS n FROM bronze.raw_listings GROUP BY 1) t) AS result
UNION ALL SELECT '2. silver: months (from file name)',
       (SELECT string_agg(to_char(m, 'YYYY-MM'), ', ' ORDER BY m) FROM (SELECT DISTINCT month_date AS m FROM silver.silver_listings) t)
UNION ALL SELECT '3. datamart: months',
       (SELECT string_agg(to_char(m, 'YYYY-MM'), ', ' ORDER BY m) FROM (SELECT DISTINCT month_year AS m FROM datamart.dm_listing_neighbourhood) t)
UNION ALL SELECT '4. fact rows / silver rows (must be equal)',
       (SELECT count(*) FROM gold.fact_listings) || ' / ' || (SELECT count(*) FROM silver.silver_listings)
UNION ALL SELECT '5. host versions: total / hosts / current (last two equal)',
       (SELECT count(*) || ' / ' || count(DISTINCT host_id) || ' / ' || count(*) FILTER (WHERE dbt_valid_to IS NULL) FROM silver.host_snapshot)
UNION ALL SELECT '6. property versions: total / listings / current (last two equal)',
       (SELECT count(*) || ' / ' || count(DISTINCT listing_id) || ' / ' || count(*) FILTER (WHERE dbt_valid_to IS NULL) FROM silver.property_snapshot)
UNION ALL SELECT '7. hosts whose superhost status changed',
       (SELECT count(*) FROM (SELECT host_id FROM silver.host_snapshot GROUP BY host_id HAVING count(DISTINCT host_is_superhost) > 1) t)::text
UNION ALL SELECT '8. datamart rows with % change filled',
       (SELECT count(active_listings_pct_change) FROM datamart.dm_listing_neighbourhood)::text;
 
 
-- 3. This is the query that helped me find the month bug. It shows which scraped dates are in each file.
-- 07_2020.csv actually goes from 2020-07-14 to 2020-09-05, so taking the month from scraped_date was a mistake. Now I take the month from the file name instead.

SELECT source_file,
       min(scraped_date) AS first_scrape,
       max(scraped_date) AS last_scrape,
       count(DISTINCT left(scraped_date, 7)) AS nb_months_inside,
       count(*) AS nb_rows
FROM bronze.raw_listings
GROUP BY source_file
ORDER BY substr(source_file, 4, 4), substr(source_file, 1, 2);
 
 -- 4. Reset to fix the month bug (after loading July 2020)
-- Since I was taking the month from scraped_date, the datamart showed a fake "September" month.
-- Some hosts also got a snapshot version dated September, and that would have blocked their August versions, because the timestamp strategy only accepts newer timestamps.
-- So I changed dbt to take the month from the file name, and then I loaded June and July again. August is in the list as well, because I had already started it before I noticed the bug.
-- I keep May and the reference files. Only the host and property snapshots use the month as their timestamp, so I only drop those two. The LGA and suburb snapshots are fine.

DELETE FROM bronze.raw_listings WHERE source_file IN ('06_2020.csv', '07_2020.csv', '08_2020.csv');
DROP TABLE IF EXISTS silver.host_snapshot, silver.property_snapshot;
 
-- check: only 05_2020.csv should be left
SELECT source_file, count(*) FROM bronze.raw_listings GROUP BY 1;
 
-- >>> run "dbt build" here before the next query (it recreates the two snapshots) <<<
 
-- after running dbt build again on May only, this should give 1 / 27273 / 37562
SELECT (SELECT count(DISTINCT month_year) FROM datamart.dm_listing_neighbourhood) AS datamart_months,
       (SELECT count(*) FROM silver.host_snapshot) AS host_versions,
       (SELECT count(*) FROM silver.property_snapshot) AS property_versions;
 
 

-- 5. SCD2 example (after the 12 months): here I pick one host whose superhost status changed.
-- You can see every version has its own valid_from and valid_to, with no gaps or overlaps between them, and the current version is the one with valid_to = NULL.

SELECT host_id, host_name, host_is_superhost, host_neighbourhood,
       dbt_valid_from::date AS valid_from, dbt_valid_to::date AS valid_to
FROM silver.host_snapshot
WHERE host_id = (
    SELECT host_id FROM silver.host_snapshot
    GROUP BY host_id
    HAVING count(DISTINCT host_is_superhost) > 1
    ORDER BY host_id LIMIT 1
)
ORDER BY dbt_valid_from;
 
 

-- 6. Datamart extract (after the 12 months): here I look at one neighbourhood over the whole year.
-- The % change only starts in June 2020 because May doesnt have a month before it to compare with.
-- The inactive % change stays NULL as long as the month before had 0 inactive listing because you can't divide by 0.

SELECT listing_neighbourhood, month_year, active_listings_rate, median_price,
       superhost_rate, active_listings_pct_change, inactive_listings_pct_change,
       total_stays, avg_estimated_revenue_per_active_listing
FROM datamart.dm_listing_neighbourhood
WHERE listing_neighbourhood = 'Sydney'
ORDER BY month_year;
