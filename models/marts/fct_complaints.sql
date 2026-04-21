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
    zip_code_is_valid,
    submitted_via,
    tags_is_servicemember,
    tags_is_older_american,
    consumer_consent_provided,

    company_response_to_consumer,
    company_public_response,
    timely_response,
    consumer_disputed,
    has_narrative,

    date_received < '2017-04-24'                                      as is_dispute_era,
    date_received >= '2015-06-01'                                     as is_narrative_era,
    greatest(date_diff(date_sent_to_company, date_received, day), 0) as days_to_company

from complaints
