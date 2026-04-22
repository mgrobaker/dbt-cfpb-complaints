-- Aggregates stg_fdic_banks to top_holder grain and applies display normalization.
-- Join key for dim_bank → dim_company is raw top_holder (dim_company.fdic_top_holder
-- stores the raw FDIC string); top_holder_normalized is display-only.
-- total_assets is in thousands USD in the FDIC source — multiply ×1000 for USD.

with banks as (
    select * from {{ ref('stg_fdic_banks') }}
    where top_holder is not null
)

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
    )                                           as top_holder_normalized,

    count(*)                                    as charter_count,
    sum(total_assets) * 1000                    as total_assets_usd,
    max(cfpb_supervisory_flag)                  as is_supervised_cfpb,
    round(avg(return_on_assets), 4)             as avg_roa,

    case
        when sum(total_assets) >= 1000000000 then 'mega (>$1T)'
        when sum(total_assets) >= 400000000  then 'large ($400B-$1T)'
        when sum(total_assets) >= 175000000  then 'mid ($175B-$400B)'
        else                                      'smaller (<$175B)'
    end                                         as bank_size_bucket

from banks
group by top_holder
