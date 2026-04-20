with complaints as (
    select * from {{ ref('stg_cfpb_complaints') }}
)

select
    complaint_id,
    date_received,
    date_sent_to_company,

    date_received                                                           as date_day_received,
    cast(
        farm_fingerprint(concat(product_normalized, '|', coalesce(subproduct_normalized, '')))
        as string
    )                                                                       as product_sk,
    cast(
        farm_fingerprint(concat(issue, '|', coalesce(subissue, '')))
        as string
    )                                                                       as issue_sk,

    company_name,
    company_name_normalized,
    state,
    zip_code,
    submitted_via,
    tags,
    consumer_consent_provided,

    company_response_to_consumer,
    company_public_response,
    timely_response,
    consumer_disputed,
    has_narrative

from complaints
