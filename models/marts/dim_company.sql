{{ config(materialized='table') }}

with crosswalk as (
    select * from {{ ref('stg_company_crosswalk') }}
),

-- Deduplicate to one row per canonical company.
-- Truist has 3 crosswalk rows (SunTrust, BB&T, post-merger Truist); the current
-- fdic_top_holder is the one where parent_as_of IS NULL.
companies as (
    select
        canonical_name,
        category,
        max(case when parent_as_of is null then fdic_top_holder end) as fdic_top_holder
    from crosswalk
    group by canonical_name, category
),

complaint_stats as (
    select
        canonical_name,
        min(date_received)  as first_seen_date,
        max(date_received)  as last_seen_date,
        count(*)            as total_complaint_volume
    from {{ ref('fct_complaints') }}
    where is_crosswalked
    group by canonical_name
)

select
    farm_fingerprint(c.canonical_name)  as company_sk,
    c.canonical_name,
    c.category,
    c.category = 'credit_bureau'        as is_credit_bureau,
    c.fdic_top_holder,
    s.first_seen_date,
    s.last_seen_date,
    s.total_complaint_volume
from companies c
left join complaint_stats s
    on c.canonical_name = s.canonical_name
