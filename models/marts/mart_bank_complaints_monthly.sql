{{ config(materialized='table') }}

-- Grain: canonical_name × month_start × product_category. Time-series companion to
-- mart_bank_complaint_metrics (which is bank-grain). Same 23-bank universe — Barclays
-- excluded since total_assets_usd is null and no asset denominator means no
-- complaints_per_billion_assets cuts. Bank attributes are denormalized for BI ergonomics.
--
-- Measures store COMPONENTS, not rates. Rates computed at consumption time (or in
-- MetricFlow) sum the components and divide — correct at any rollup. Storing rates
-- here would break Simpson's-paradox-safe rollups: averaging monthly rates ≠ rate of
-- summed components. Era-gated denominators (complaint_count_dispute_era,
-- complaint_count_narrative_era) are stored alongside the era-gated numerators so
-- dispute_rate / narrative_rate can be re-derived at any time grain.

with complaints as (
    select * from {{ ref('fct_complaints') }}
),

banks as (
    select * from {{ ref('dim_bank') }}
    where total_assets_usd is not null
)

select
    b.company_sk,
    b.canonical_name,
    date_trunc(c.date_received, month)                                      as month_start,
    c.product_category,

    b.bank_size_bucket,
    b.bank_size_rank,
    b.is_branchless,
    b.primary_specialization,
    round(b.total_assets_usd / 1e9, 1)                                      as total_assets_billions,
    b.is_supervised_cfpb,

    count(*)                                                                as complaint_count,
    countif(c.timely_response)                                              as timely_response_count,
    countif(c.days_to_company = 0)                                          as routed_same_day_count,
    sum(c.days_to_company)                                                  as sum_days_to_company,

    -- Era-gated denominators: number of complaints in this cell that fall in
    -- dispute / narrative era. April 2017 cells split across the dispute cutoff,
    -- so a month-grain era count is more precise than a month-level boolean.
    countif(c.is_dispute_era)                                               as complaint_count_dispute_era,
    countif(c.is_narrative_era)                                             as complaint_count_narrative_era,

    -- Era-gated numerators. NULL (not 0) when the cell has no in-era complaints —
    -- the rate is undefined, not zero. Coherence test: NULL iff denominator = 0.
    case
        when countif(c.is_dispute_era) > 0
            then countif(c.is_dispute_era and c.consumer_disputed)
    end                                                                     as disputed_count,
    case
        when countif(c.is_narrative_era) > 0
            then countif(c.is_narrative_era and c.has_narrative)
    end                                                                     as narrative_count

from complaints c
inner join banks b on c.company_sk = b.company_sk
group by
    b.company_sk,
    b.canonical_name,
    month_start,
    c.product_category,
    b.bank_size_bucket,
    b.bank_size_rank,
    b.is_branchless,
    b.primary_specialization,
    b.total_assets_usd,
    b.is_supervised_cfpb
