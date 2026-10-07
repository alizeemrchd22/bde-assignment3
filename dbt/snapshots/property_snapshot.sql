{% snapshot property_snapshot %}

{{
    config(
        target_schema='silver',
        unique_key='listing_id',
        strategy='timestamp',
        updated_at='snapshot_month'
    )
}}

-- This snapshot keeps the history of each property (SCD2), with the month of the file as the timestamp.
-- Same reason as the host snapshot, scraped_date can spill into later months (07_2020.csv goes up to September) Cast to a timestamp to match dbt_valid_from / dbt_valid_to.

select
    *,
    month_date::timestamp as snapshot_month
from {{ ref('silver_properties') }}

{% endsnapshot %}
