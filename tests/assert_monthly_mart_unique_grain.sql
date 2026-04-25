-- Composite-key uniqueness for mart_bank_complaints_monthly. Generic `unique`
-- tests guard a single column; this guards the three-column grain explicitly.
-- Returns offending grain tuples on failure.
{{ config(severity='error') }}

select
    canonical_name,
    month_start,
    product_category,
    count(*) as row_count
from {{ ref('mart_bank_complaints_monthly') }}
group by 1, 2, 3
having count(*) > 1
