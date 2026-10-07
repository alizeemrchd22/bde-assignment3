{% snapshot host_snapshot %}

{{
    config(
        target_schema='silver',
        unique_key='host_id',
        strategy='timestamp',
        updated_at='snapshot_month'
    )
}}

-- This snapshot keeps the history of each host (SCD2). The timestamp is the month of the file not scraped_date because 07_2020.csv has rows scraped in September, which would have blocked the August versions. I cast it to a timestamp so it matches dbt_valid_from / dbt_valid_to.

select
    *,
    month_date::timestamp as snapshot_month
from {{ ref('silver_hosts') }}

{% endsnapshot %}
