{% snapshot company_renames %}

{{
    config(
        target_schema='snapshots',
        unique_key='raw_company_name',
        strategy='check',
        check_cols=['canonical_name', 'fdic_top_holder'],
    )
}}

-- Tracks canonical company name and FDIC parent changes over time.
--
-- In production on a live complaint feed, dbt would detect when canonical_name
-- or fdic_top_holder changes for a given raw_company_name and write a new row
-- with dbt_valid_from = change timestamp, closing the prior row's dbt_valid_to.
-- The result would automatically capture rebrands (SunTrust → Truist, etc.)
-- as they appear in the source data.
--
-- With this frozen source (last updated 2023-03-25), the snapshot establishes
-- initial state only — no future changes will be observed. The three known
-- rebrands are instead encoded via the crosswalk's parent_as_of column:
--   SunTrust → Truist:              2019-12-01
--   BB&T → Truist:                  2019-12-01
--   Alliance Data → Bread Financial: 2021-02-01
-- Query stg_company_crosswalk WHERE parent_as_of IS NOT NULL to surface them.
--
-- Requires stg_company_crosswalk to be built first (uv run dbt run -s stg_company_crosswalk).

select
    raw_company_name,
    canonical_name,
    category,
    fdic_top_holder,
    parent_as_of
from {{ ref('stg_company_crosswalk') }}

{% endsnapshot %}
