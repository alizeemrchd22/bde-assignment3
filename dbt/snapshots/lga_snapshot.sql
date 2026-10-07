{% snapshot lga_snapshot %}

{{
    config(
        target_schema='silver',
        unique_key='lga_code',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

-- This snapshot keeps the history of each LGA (SCD2). LGAs don't come from the listings,so there's no scraped_date here. I use loaded_at instead, which is when Airflow loaded the file.
-- If the LGA file gets reloaded with a different name for a code, dbt keeps the old version too.

select * from {{ ref('silver_lga') }}

{% endsnapshot %}
