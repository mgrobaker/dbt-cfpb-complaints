with complaints as (
    select * from {{ ref('int_complaints_with_company') }}
)

select
    complaint_id,
    date_received,
    date_sent_to_company,

    product,
    subproduct,
    product_normalized,
    case product_normalized
        when 'Mortgage'                                                                          then 'mortgage'
        when 'Credit reporting, credit repair services, or other personal consumer reports'      then 'credit_reporting'
        when 'Debt collection'                                                                   then 'debt_collection'
        when 'Checking or savings account'                                                       then 'banking'
        when 'Credit card or prepaid card'                                                       then 'card'
        when 'Money transfer, virtual currency, or money service'                               then 'payments'
        else 'other'
    end                                                                                          as product_category,
    subproduct_normalized,
    issue,
    subissue,

    farm_fingerprint(canonical_name)                                   as company_sk,
    company_name,
    company_name_normalized,
    canonical_name,
    category,
    is_crosswalked,
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
    has_full_year_data,

    date_received < '2017-04-24'                                      as is_dispute_era,
    date_received >= '2015-06-01'                                     as is_narrative_era,
    greatest(date_diff(date_sent_to_company, date_received, day), 0) as days_to_company

from complaints
