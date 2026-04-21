-- Thin staging pass over the company_crosswalk seed.
-- raw_company_name is normalized identically to stg_cfpb_complaints.company_name_normalized
-- so the join in int_complaints_with_company works on equal keys.

with source as (
    select * from {{ ref('company_crosswalk') }}
),

staged as (
    select
        regexp_replace(
            regexp_replace(upper(trim(raw_company_name)), r'\s+', ' '),
            r'[.,;]+$', ''
        )                               as raw_company_name,

        trim(canonical_name)            as canonical_name,
        trim(category)                  as category,
        trim(fdic_top_holder)           as fdic_top_holder,
        cast(parent_as_of as date)      as parent_as_of
    from source
)

select * from staged
