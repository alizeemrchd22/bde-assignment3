-- BDE AT3 - Part 1
-- SQL I ran in DBeaver (Postgres) to set up the bronze layer and to check the data after the Airflow DAG load


-- 1.2 Bronze schema + raw tables
-- all columns are TEXT on purpose: bronze keeps the data exactly like the CSV, so a bad value never makes the load fail. I cast and clean later in dbt (silver) source_file and loaded_at are added by me to know where and when each row came from.
CREATE SCHEMA IF NOT EXISTS bronze;


-- listings (one CSV per month, same 22 columns in each file)
DROP TABLE IF EXISTS bronze.raw_listings;
CREATE TABLE bronze.raw_listings (
    listing_id TEXT,
    scrape_id TEXT,
    scraped_date TEXT,
    host_id TEXT,
    host_name TEXT,
    host_since TEXT,
    host_is_superhost TEXT,
    host_neighbourhood TEXT,
    listing_neighbourhood TEXT,
    property_type TEXT,
    room_type TEXT,
    accommodates TEXT,
    price TEXT,
    has_availability TEXT,
    availability_30 TEXT,
    number_of_reviews TEXT,
    review_scores_rating TEXT,
    review_scores_accuracy TEXT,
    review_scores_cleanliness TEXT,
    review_scores_checkin TEXT,
    review_scores_communication TEXT,
    review_scores_value TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT NOW()
);


-- census G01 (109 cols, same names as the CSV header but in lowercase)
DROP TABLE IF EXISTS bronze.raw_census_g01;
CREATE TABLE bronze.raw_census_g01 (
    lga_code_2016 TEXT,
    tot_p_m TEXT,
    tot_p_f TEXT,
    tot_p_p TEXT,
    age_0_4_yr_m TEXT,
    age_0_4_yr_f TEXT,
    age_0_4_yr_p TEXT,
    age_5_14_yr_m TEXT,
    age_5_14_yr_f TEXT,
    age_5_14_yr_p TEXT,
    age_15_19_yr_m TEXT,
    age_15_19_yr_f TEXT,
    age_15_19_yr_p TEXT,
    age_20_24_yr_m TEXT,
    age_20_24_yr_f TEXT,
    age_20_24_yr_p TEXT,
    age_25_34_yr_m TEXT,
    age_25_34_yr_f TEXT,
    age_25_34_yr_p TEXT,
    age_35_44_yr_m TEXT,
    age_35_44_yr_f TEXT,
    age_35_44_yr_p TEXT,
    age_45_54_yr_m TEXT,
    age_45_54_yr_f TEXT,
    age_45_54_yr_p TEXT,
    age_55_64_yr_m TEXT,
    age_55_64_yr_f TEXT,
    age_55_64_yr_p TEXT,
    age_65_74_yr_m TEXT,
    age_65_74_yr_f TEXT,
    age_65_74_yr_p TEXT,
    age_75_84_yr_m TEXT,
    age_75_84_yr_f TEXT,
    age_75_84_yr_p TEXT,
    age_85ov_m TEXT,
    age_85ov_f TEXT,
    age_85ov_p TEXT,
    counted_census_night_home_m TEXT,
    counted_census_night_home_f TEXT,
    counted_census_night_home_p TEXT,
    count_census_nt_ewhere_aust_m TEXT,
    count_census_nt_ewhere_aust_f TEXT,
    count_census_nt_ewhere_aust_p TEXT,
    indigenous_psns_aboriginal_m TEXT,
    indigenous_psns_aboriginal_f TEXT,
    indigenous_psns_aboriginal_p TEXT,
    indig_psns_torres_strait_is_m TEXT,
    indig_psns_torres_strait_is_f TEXT,
    indig_psns_torres_strait_is_p TEXT,
    indig_bth_abor_torres_st_is_m TEXT,
    indig_bth_abor_torres_st_is_f TEXT,
    indig_bth_abor_torres_st_is_p TEXT,
    indigenous_p_tot_m TEXT,
    indigenous_p_tot_f TEXT,
    indigenous_p_tot_p TEXT,
    birthplace_australia_m TEXT,
    birthplace_australia_f TEXT,
    birthplace_australia_p TEXT,
    birthplace_elsewhere_m TEXT,
    birthplace_elsewhere_f TEXT,
    birthplace_elsewhere_p TEXT,
    lang_spoken_home_eng_only_m TEXT,
    lang_spoken_home_eng_only_f TEXT,
    lang_spoken_home_eng_only_p TEXT,
    lang_spoken_home_oth_lang_m TEXT,
    lang_spoken_home_oth_lang_f TEXT,
    lang_spoken_home_oth_lang_p TEXT,
    australian_citizen_m TEXT,
    australian_citizen_f TEXT,
    australian_citizen_p TEXT,
    age_psns_att_educ_inst_0_4_m TEXT,
    age_psns_att_educ_inst_0_4_f TEXT,
    age_psns_att_educ_inst_0_4_p TEXT,
    age_psns_att_educ_inst_5_14_m TEXT,
    age_psns_att_educ_inst_5_14_f TEXT,
    age_psns_att_educ_inst_5_14_p TEXT,
    age_psns_att_edu_inst_15_19_m TEXT,
    age_psns_att_edu_inst_15_19_f TEXT,
    age_psns_att_edu_inst_15_19_p TEXT,
    age_psns_att_edu_inst_20_24_m TEXT,
    age_psns_att_edu_inst_20_24_f TEXT,
    age_psns_att_edu_inst_20_24_p TEXT,
    age_psns_att_edu_inst_25_ov_m TEXT,
    age_psns_att_edu_inst_25_ov_f TEXT,
    age_psns_att_edu_inst_25_ov_p TEXT,
    high_yr_schl_comp_yr_12_eq_m TEXT,
    high_yr_schl_comp_yr_12_eq_f TEXT,
    high_yr_schl_comp_yr_12_eq_p TEXT,
    high_yr_schl_comp_yr_11_eq_m TEXT,
    high_yr_schl_comp_yr_11_eq_f TEXT,
    high_yr_schl_comp_yr_11_eq_p TEXT,
    high_yr_schl_comp_yr_10_eq_m TEXT,
    high_yr_schl_comp_yr_10_eq_f TEXT,
    high_yr_schl_comp_yr_10_eq_p TEXT,
    high_yr_schl_comp_yr_9_eq_m TEXT,
    high_yr_schl_comp_yr_9_eq_f TEXT,
    high_yr_schl_comp_yr_9_eq_p TEXT,
    high_yr_schl_comp_yr_8_belw_m TEXT,
    high_yr_schl_comp_yr_8_belw_f TEXT,
    high_yr_schl_comp_yr_8_belw_p TEXT,
    high_yr_schl_comp_d_n_g_sch_m TEXT,
    high_yr_schl_comp_d_n_g_sch_f TEXT,
    high_yr_schl_comp_d_n_g_sch_p TEXT,
    count_psns_occ_priv_dwgs_m TEXT,
    count_psns_occ_priv_dwgs_f TEXT,
    count_psns_occ_priv_dwgs_p TEXT,
    count_persons_other_dwgs_m TEXT,
    count_persons_other_dwgs_f TEXT,
    count_persons_other_dwgs_p TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT NOW()
);


-- census G02 (medians and averages per LGA)
DROP TABLE IF EXISTS bronze.raw_census_g02;
CREATE TABLE bronze.raw_census_g02 (
    lga_code_2016 TEXT,
    median_age_persons TEXT,
    median_mortgage_repay_monthly TEXT,
    median_tot_prsnl_inc_weekly TEXT,
    median_rent_weekly TEXT,
    median_tot_fam_inc_weekly TEXT,
    average_num_psns_per_bedroom TEXT,
    median_tot_hhd_inc_weekly TEXT,
    average_household_size TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT NOW()
);


-- LGA code -> LGA name
DROP TABLE IF EXISTS bronze.raw_lga_code;
CREATE TABLE bronze.raw_lga_code (
    lga_code TEXT,
    lga_name TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT NOW()
);


-- suburb -> LGA name
-- (the CSV has extra commas at the end of each line, the DAG drops those empty columns)
DROP TABLE IF EXISTS bronze.raw_lga_suburb;
CREATE TABLE bronze.raw_lga_suburb (
    lga_name TEXT,
    suburb_name TEXT,
    source_file TEXT,
    loaded_at TIMESTAMP DEFAULT NOW()
);


-- 1.3 Checks after running the Airflow DAG (bde_load_bronze)

-- are all 5 tables there?
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'bronze'
ORDER BY table_name;

-- row count for each table
-- (my result: listings 37,562 / g01 132 / g02 132 / lga_code 129 / lga_suburb 4,470)
SELECT 'raw_listings'   AS table_name, COUNT(*) AS nb_rows FROM bronze.raw_listings
UNION ALL SELECT 'raw_census_g01', COUNT(*) FROM bronze.raw_census_g01
UNION ALL SELECT 'raw_census_g02', COUNT(*) FROM bronze.raw_census_g02
UNION ALL SELECT 'raw_lga_code',   COUNT(*) FROM bronze.raw_lga_code
UNION ALL SELECT 'raw_lga_suburb', COUNT(*) FROM bronze.raw_lga_suburb;

-- rows per listings file, to check each month was loaded only once
-- the DAG deletes the rows of a file before loading it again, so even if a task
-- is retried, first_load and last_load should be the same (no duplicates)
SELECT source_file,
       COUNT(*)       AS nb_rows,
       MIN(loaded_at) AS first_load,
       MAX(loaded_at) AS last_load
FROM bronze.raw_listings
GROUP BY source_file
ORDER BY source_file;

-- quick look at the raw data
SELECT * FROM bronze.raw_listings LIMIT 10;
