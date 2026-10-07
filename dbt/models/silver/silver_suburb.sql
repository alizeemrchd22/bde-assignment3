-- Silver: suburb -> LGA mapping.
--    I ve fixed the raw file is all upper case 'ABBOTSBURY', so I keep an upper-cas key for joins and a Title Case name for display
--   I add the LGA code by joining on the LGA name, so later I can go from host_neighbourhood (a suburb) to its LGA without joining on text again
--   one row per suburb, because the snapshot needs a unique key loaded_at is kept because it is the timestamp used by the suburb snapshot.

with suburbs as (

    select
        upper(trim(suburb_name))     as suburb_name_key,
        initcap(trim(suburb_name))   as suburb_name,
        upper(trim(lga_name))        as lga_name_key,
        loaded_at::timestamp         as loaded_at,
        row_number() over (
            partition by upper(trim(suburb_name))
            order by upper(trim(lga_name))
        ) as row_num
    from {{ source('bronze', 'raw_lga_suburb') }}
    where suburb_name is not null

)

select
    s.suburb_name_key,
    s.suburb_name,
    l.lga_code,
    l.lga_name,
    s.loaded_at
from suburbs s
left join {{ ref('silver_lga') }} l
    on s.lga_name_key = l.lga_name_key
where s.row_num = 1
