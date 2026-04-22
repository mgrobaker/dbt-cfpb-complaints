-- Crosswalk covers the top 30 institutions by CFPB complaint volume (2012-2022),
-- which reaches 74.48% of all complaints. Threshold set to 74% to catch regression
-- without being brittle to minor data shifts.
{{ config(severity='error') }}

select
    round(100.0 * sum(case when is_crosswalked then 1 else 0 end) / count(*), 1) as coverage_pct
from {{ ref('int_complaints_with_company') }}
having coverage_pct < 74
