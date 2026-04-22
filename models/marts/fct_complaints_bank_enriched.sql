{{ config(materialized='table') }}

-- Bank-segment complaints enriched with FDIC holding-company attributes.
-- Rows: fct_complaints filtered to category = 'bank' (~739K rows, 21.4% of total).
-- Columns: all fct_complaints columns plus FDIC attributes from dim_bank.
-- Grain: one row per complaint (same as fct_complaints).

with complaints as (
    select * from {{ ref('fct_complaints') }}
    where category = 'bank'
),

banks as (
    select * from {{ ref('dim_bank') }}
)

select
    c.*,
    b.top_holder_normalized,
    b.charter_count,
    b.total_assets_usd,
    b.bank_size_bucket,
    b.is_supervised_cfpb,
    b.avg_roa

from complaints c
left join banks b
    on c.company_sk = b.company_sk
