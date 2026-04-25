-- Thin staging pass over raw.cfpb_complaints.
-- Renames: none needed (source is already snake_case).
-- Transforms: trim all string columns; upper-case 2-char state code.
-- company_name_normalized: UPPER + collapsed whitespace + trailing punct stripped.
-- product_normalized / subproduct_normalized: seed joins to product_mapping and subproduct_mapping.
--   Consumer Loan + vehicle subproduct is the only case where product_normalized depends on
--   subproduct; handled inline. All other product renames come from the product_mapping seed.
-- has_full_year_data: false for 2011 (stub, Dec only) and 2023 (partial, frozen 2023-03-23).
--   Filter on this flag for clean year-over-year trend analysis.
-- issue_category: 8-bucket roll-up of the 165 raw issue strings via the issue_mapping seed.
--   Same pattern as product_mapping / subproduct_mapping.

with source as (
    select * from {{ source('raw', 'cfpb_complaints') }}
),

renamed as (
    select
        complaint_id,
        date_received,
        date_sent_to_company,

        trim(product)                        as product,
        trim(subproduct)                     as subproduct,
        trim(issue)                          as issue,
        trim(subissue)                       as subissue,

        trim(company_name)                   as company_name,
        regexp_replace(
            regexp_replace(upper(trim(company_name)), r'\s+', ' '),
            r'[.,;]+$', ''
        )                                    as company_name_normalized,
        case
            when state is null                                                    then 'not-provided'
            when upper(trim(state)) = 'UNITED STATES MINOR OUTLYING ISLANDS'     then 'UM'
            when length(trim(state)) > 2                                          then 'not-provided'
            else upper(trim(state))
        end                                  as state,
        -- Raw zip_code is float-formatted ('30349.0') — BigQuery CSV import artifact.
        -- Also strip trailing '-': artifact of users beginning to type zip+4 (e.g. '3008-').
        -- SAFE_CAST: non-numeric values pass through via COALESCE so zip_code_is_valid
        -- can flag them; NULL source stays NULL.
        coalesce(
            lpad(
                cast(safe_cast(
                    regexp_replace(
                        regexp_replace(trim(zip_code), r'\.0$', ''),
                        r'-$', ''
                    )
                as int64) as string),
                5, '0'
            ),
            trim(zip_code)
        )                                    as zip_code,

        trim(tags)                                              as tags,
        -- Tags added Feb 2016; pre-2016 complaints are structurally null — not missing data.
        coalesce(trim(tags) like '%Servicemember%', false)     as tags_is_servicemember,
        coalesce(trim(tags) like '%Older American%', false)    as tags_is_older_american,

        trim(submitted_via)                  as submitted_via,

        -- 4 nulls exist; assumption: no response filed = untimely response.
        coalesce(trim(company_response_to_consumer), 'Untimely response')
                                             as company_response_to_consumer,

        -- Verbose label ("...and chooses not to provide a public response") is the post-2015
        -- CFPB form; it restates company_response_to_consumer info that belongs in the other
        -- field. Collapse to the shorter label; null = no public statement filed.
        case
            when trim(company_public_response) = 'Company has responded to the consumer and the CFPB and chooses not to provide a public response'
                then 'Company chooses not to provide a public response'
            when company_public_response is null
                then 'not-provided'
            else trim(company_public_response)
        end                                  as company_public_response,

        coalesce(trim(consumer_consent_provided), 'not-provided')
                                             as consumer_consent_provided,

        timely_response,
        consumer_disputed,
        has_narrative,

        extract(year from date_received) between 2012 and 2022
                                             as has_full_year_data

    from source
),

normalized as (
    select
        r.*,
        coalesce(
            -- Consumer Loan + vehicle subproduct: product_normalized depends on subproduct
            case
                when r.product = 'Consumer Loan' and r.subproduct in ('Vehicle loan', 'Vehicle lease')
                    then 'Vehicle loan or lease'
            end,
            pm.product_normalized,
            r.product
        )                                    as product_normalized,
        coalesce(sm.subproduct_normalized, r.subproduct)
                                             as subproduct_normalized,
        coalesce(im.issue_category, 'other') as issue_category,
        coalesce(regexp_contains(r.zip_code, r'^\d{5}$'), false)
                                             as zip_code_is_valid
    from renamed r
    left join {{ ref('product_mapping') }} pm
        on r.product = pm.raw_product
    left join {{ ref('subproduct_mapping') }} sm
        on r.product = sm.raw_product
        and coalesce(r.subproduct, '') = coalesce(sm.raw_subproduct, '')
    left join {{ ref('issue_mapping') }} im
        on r.issue = im.issue
)

select * from normalized
