{% snapshot suburb_snapshot %}

{{
    config(
        target_schema='silver',
        unique_key='suburb_name_key',
        strategy='timestamp',
        updated_at='loaded_at'
    )
}}

-- This snapshot keeps the history of the suburb -> LGA mapping (SCD2), using loaded_at as the timestamp since this file doesn't come with the listings. The key is the upper-case suburb name, that's why
-- I kept only one row per suburb in silver. If a suburb moves to another LGA one day, the old link is kept.

select * from {{ ref('silver_suburb') }}

{% endsnapshot %}
