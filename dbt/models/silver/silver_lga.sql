-- Silver: LGA reference table (LGA code -> LGA name).

select
    lga_code::int              as lga_code,
    trim(lga_name)             as lga_name,
    upper(trim(lga_name))      as lga_name_key,
    loaded_at::timestamp       as loaded_at
from {{ source('bronze', 'raw_lga_code') }}
where lga_code is not null
