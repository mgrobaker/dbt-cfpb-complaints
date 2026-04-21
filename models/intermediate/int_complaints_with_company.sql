-- Left join CFPB complaints to the company crosswalk on the normalized company name.
-- Adds canonical_name, category, and is_crosswalked to every complaint row.
-- Grain: one row per complaint (left join preserves all staging rows; no fan-out
-- because raw_company_name is unique in stg_company_crosswalk).

with complaints as (
    select * from {{ ref('stg_cfpb_complaints') }}
),

crosswalk as (
    select * from {{ ref('stg_company_crosswalk') }}
)

select
    c.*,
    xw.canonical_name,
    xw.category,
    xw.parent_as_of                         as company_parent_as_of,
    xw.raw_company_name is not null         as is_crosswalked

from complaints c
left join crosswalk xw
    on c.company_name_normalized = xw.raw_company_name
