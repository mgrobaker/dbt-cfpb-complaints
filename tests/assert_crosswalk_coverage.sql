-- Crosswalk covers ~77% of complaint volume by design (top 3 credit bureaus + top 30 others).
-- Fails if coverage drops below 75% — signals either a data shift or crosswalk regression.
{{ config(severity='error') }}

select
    round(100.0 * sum(case when is_crosswalked then 1 else 0 end) / count(*), 1) as coverage_pct
from {{ ref('int_complaints_with_company') }}
having coverage_pct < 75
