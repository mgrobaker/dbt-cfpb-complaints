{{ config(materialized='table') }}

-- Aggregates bank-segment complaints to bank_size_bucket grain.
-- Encodes era-gating for dispute_rate (is_dispute_era) so every metric is
-- correct by construction — consumers don't need to know the policy cutoffs.
-- Grain: one row per bank_size_bucket (5 possible tiers; only mega and large
-- are present in the current crosswalk universe).

with enriched as (
    select * from {{ ref('fct_complaints_bank_enriched') }}
)

select
    bank_size_bucket,

    count(distinct canonical_name)                                              as bank_count,
    string_agg(distinct canonical_name order by canonical_name)                as bank_names,
    count(*)                                                                    as complaint_count,
    round(avg(days_to_company), 2)                                              as avg_days_to_company,

    round(countif(timely_response) / count(*), 4)                              as timely_response_rate,

    -- dispute_rate gated on is_dispute_era — pre-2017-04-24 rows only.
    -- Ungated rate (4.3%) is meaningless; era-filtered rate (19.3%) is the signal.
    round(
        countif(consumer_disputed and is_dispute_era)
        / nullif(countif(is_dispute_era), 0),
        4
    )                                                                           as dispute_rate,

    round(avg(avg_roa), 4)                                                      as avg_roa,
    round(avg(total_assets_usd) / 1e9, 1)                                      as avg_total_assets_billions

from enriched
where bank_size_bucket is not null
group by bank_size_bucket
order by avg_total_assets_billions desc
