-- Thin staging pass over raw.cfpb_complaints.
-- Renames: none needed (source is already snake_case).
-- Transforms: trim all string columns; upper-case 2-char state code.
-- Deferred to later layers: company_name normalization (crosswalk seed).

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
        upper(trim(state))                   as state,
        trim(zip_code)                       as zip_code,

        trim(tags)                           as tags,
        trim(submitted_via)                  as submitted_via,
        trim(company_response_to_consumer)   as company_response_to_consumer,
        trim(company_public_response)        as company_public_response,
        trim(consumer_consent_provided)      as consumer_consent_provided,

        timely_response,
        consumer_disputed,
        has_narrative

    from source
)

select * from renamed
