-- Thin staging pass over raw.cfpb_complaints.
-- Renames: none needed (source is already snake_case).
-- Transforms: trim all string columns; upper-case 2-char state code.
-- company_name_normalized: UPPER + collapsed whitespace + trailing punct stripped.
-- Rows excluded: 2011 (stub year, 2,536 rows) and 2023 (partial year through 2023-03-23).

with source as (
    select * from {{ source('raw', 'cfpb_complaints') }}
),

filtered as (
    select *
    from source
    where date_received >= '2012-01-01'
      and date_received < '2023-01-01'
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
        trim(zip_code)                       as zip_code,

        trim(tags)                           as tags,
        trim(submitted_via)                  as submitted_via,
        trim(company_response_to_consumer)   as company_response_to_consumer,
        trim(company_public_response)        as company_public_response,
        trim(consumer_consent_provided)      as consumer_consent_provided,

        timely_response,
        consumer_disputed,
        has_narrative

    from filtered
)

select * from renamed
