-- Sum of complaint_count across mart_bank_complaints_monthly must equal the
-- complaint count in fct_complaints joined to FDIC-enriched dim_bank rows
-- (the same 23-bank universe — Barclays excluded, no asset denominator).
-- Catches grain bugs and fan-out at compile time on every dbt build.
{{ config(severity='error') }}

with monthly_total as (
    select sum(complaint_count) as n from {{ ref('mart_bank_complaints_monthly') }}
),
fct_total as (
    select count(*) as n
    from {{ ref('fct_complaints') }} c
    inner join {{ ref('dim_bank') }} b on c.company_sk = b.company_sk
    where b.total_assets_usd is not null
)

select monthly_total.n as monthly_n, fct_total.n as fct_n
from monthly_total
cross join fct_total
where monthly_total.n != fct_total.n
