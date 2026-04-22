{{ config(materialized='table') }}

-- One row per crosswalk bank. company_sk is the FK carried by fct_complaints,
-- so analysts join fct_complaints → dim_bank on company_sk to add FDIC attributes.
-- 23 of 24 crosswalk banks have FDIC enrichment; Barclays (fdic_top_holder IS NULL)
-- appears with NULL FDIC columns — known gap documented in DECISIONS.md.

with companies as (
    select
        company_sk,
        canonical_name,
        fdic_top_holder,
        total_complaint_volume
    from {{ ref('dim_company') }}
    where category = 'bank'
),

fdic as (
    select * from {{ ref('int_fdic_banks_normalized') }}
)

select
    c.company_sk,
    c.canonical_name,
    c.fdic_top_holder,
    f.top_holder_normalized,
    f.charter_count,
    f.total_assets_usd,
    f.bank_size_bucket,
    f.bank_size_rank,
    f.is_supervised_cfpb,
    f.avg_roa,
    f.offices_count,
    f.is_branchless,
    f.deposits_to_assets_ratio,
    f.capital_ratio,
    f.avg_roe,
    f.credit_card_institution,
    f.primary_specialization,
    c.total_complaint_volume

from companies c
left join fdic f
    on c.fdic_top_holder = f.top_holder
