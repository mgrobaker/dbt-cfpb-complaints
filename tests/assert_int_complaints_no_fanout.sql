-- Left join to a unique key (stg_company_crosswalk.raw_company_name) cannot fan out,
-- but this test makes that guarantee explicit and will catch any future change
-- to the crosswalk grain (e.g. accidental duplicates in the seed).
{{ config(severity='error') }}

with staging_count as (
    select count(*) as n from {{ ref('stg_cfpb_complaints') }}
),
int_count as (
    select count(*) as n from {{ ref('int_complaints_with_company') }}
)

select staging_count.n as staging_n, int_count.n as int_n
from staging_count
cross join int_count
where staging_count.n != int_count.n
