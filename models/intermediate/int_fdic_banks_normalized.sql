-- Aggregates stg_fdic_banks to top_holder grain and applies display normalization.
-- Join key for dim_bank → dim_company is raw top_holder (dim_company.fdic_top_holder
-- stores the raw FDIC string); top_holder_normalized is display-only.
-- total_assets, total_deposits, equity_capital are all in thousands USD in the FDIC
-- source. total_assets_usd multiplies ×1000; ratios use thousands directly (unit-free).
-- Excluded: ownership_type (false for all 3,442 FDIC holders — zero variance);
-- office_count_domestic (near-identical to offices_count in our universe).
-- primary_specialization: largest-charter-by-assets wins for multi-charter holders
-- (175 holders span multiple values; largest charter best represents the business).

with banks as (
    select * from {{ ref('stg_fdic_banks') }}
    where top_holder is not null
),

aggregated as (
    select
        top_holder,

        regexp_replace(
            replace(
                replace(
                    replace(
                        regexp_replace(trim(upper(top_holder)), r'\s+', ' '),
                        '&', ' & '
                    ),
                    'BCORP', 'BANCORP'
                ),
                ' FINL ', ' FINANCIAL '
            ),
            r' THE$', ''
        )                                                               as top_holder_normalized,

        count(*)                                                        as charter_count,
        sum(total_assets) * 1000                                       as total_assets_usd,
        logical_or(cfpb_supervisory_flag)                              as is_supervised_cfpb,
        round(avg(return_on_assets), 4)                                as avg_roa,

        case
            when sum(total_assets) >= 1000000000 then 'mega (>$1T)'
            when sum(total_assets) >= 400000000  then 'large ($400B-$1T)'
            when sum(total_assets) >= 175000000  then 'mid ($175B-$400B)'
            else                                      'smaller (<$175B)'
        end                                                             as bank_size_bucket,

        -- branch footprint
        sum(offices_count)                                              as offices_count,

        -- financial ratios: numerator and denominator both in thousands → unit-free
        round(safe_divide(sum(total_deposits), sum(total_assets)), 4)  as deposits_to_assets_ratio,
        round(safe_divide(sum(equity_capital), sum(total_assets)), 4)  as capital_ratio,

        -- profitability
        round(avg(return_on_equity), 4)                                as avg_roe,

        -- business model
        logical_or(credit_card_institution)                            as credit_card_institution,

        -- primary specialization: largest charter by assets wins for multi-charter holders
        array_agg(
            primary_specialization ignore nulls
            order by total_assets desc
            limit 1
        )[offset(0)]                                                    as primary_specialization

    from banks
    group by top_holder
)

select
    top_holder,
    top_holder_normalized,
    charter_count,
    total_assets_usd,
    is_supervised_cfpb,
    avg_roa,
    bank_size_bucket,

    case bank_size_bucket
        when 'smaller (<$175B)'  then 1
        when 'mid ($175B-$400B)' then 2
        when 'large ($400B-$1T)' then 3
        when 'mega (>$1T)'       then 4
    end                                                                 as bank_size_rank,

    offices_count,
    offices_count < 50                                                  as is_branchless,

    deposits_to_assets_ratio,
    capital_ratio,
    avg_roe,
    credit_card_institution,
    primary_specialization

from aggregated
