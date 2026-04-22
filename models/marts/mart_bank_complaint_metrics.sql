{{ config(materialized='table') }}

-- One row per crosswalk bank with FDIC enrichment. Joins fct_complaints → dim_bank
-- directly on company_sk; no intermediate enriched fact needed (dim_bank is 24 rows).
-- Excludes Barclays — no total_assets_usd means no denominator for normalization.
-- bank_size_bucket is a dimension column for slicing, not the grain.
-- Percentile ranks are computed within this 23-bank universe, not across all FDIC holders.

with complaints as (
    select * from {{ ref('fct_complaints') }}
),

banks as (
    select * from {{ ref('dim_bank') }}
    where total_assets_usd is not null
),

aggregated as (
    select
        b.canonical_name,
        b.top_holder_normalized,
        b.bank_size_bucket,
        b.bank_size_rank,
        round(b.total_assets_usd / 1e9, 1)                             as total_assets_billions,
        b.charter_count,
        b.is_supervised_cfpb,
        b.avg_roa,
        b.offices_count,
        b.is_branchless,
        b.deposits_to_assets_ratio,
        b.capital_ratio,
        b.avg_roe,
        b.credit_card_institution,
        b.primary_specialization,

        count(*)                                                        as complaint_count,
        round(count(*) / (b.total_assets_usd / 1e9), 2)               as complaints_per_billion_assets,
        round(avg(c.days_to_company), 2)                               as avg_days_to_company,
        round(countif(c.timely_response) / count(*), 4)                as timely_response_rate,
        round(
            countif(c.consumer_disputed and c.is_dispute_era)
            / nullif(countif(c.is_dispute_era), 0),
            4
        )                                                               as dispute_rate

    from complaints c
    inner join banks b on c.company_sk = b.company_sk
    group by
        b.canonical_name,
        b.top_holder_normalized,
        b.bank_size_bucket,
        b.bank_size_rank,
        b.total_assets_usd,
        b.charter_count,
        b.is_supervised_cfpb,
        b.avg_roa,
        b.offices_count,
        b.is_branchless,
        b.deposits_to_assets_ratio,
        b.capital_ratio,
        b.avg_roe,
        b.credit_card_institution,
        b.primary_specialization
)

select
    *,
    round(percent_rank() over (order by avg_roe), 4)                   as roe_percentile_rank,
    round(percent_rank() over (order by offices_count), 4)             as offices_count_percentile_rank
from aggregated
order by complaints_per_billion_assets desc
