with complaints as (
    select * from {{ ref('stg_cfpb_complaints') }}
)

select
    complaint_id,
    date_received,
    date_sent_to_company,

    product,
    subproduct,
    product_normalized,
    subproduct_normalized,
    issue,
    subissue,

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
