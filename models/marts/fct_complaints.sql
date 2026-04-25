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
    issue_category,

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
    company_response_to_consumer = 'Closed with monetary relief'
                                                                       as had_monetary_relief,
    case
        when company_response_to_consumer in (
            'Closed with monetary relief',
            'Closed with non-monetary relief',
            'Closed with relief'
        )                                                              then 'relief'
        when company_response_to_consumer in (
            'Closed with explanation',
            'Closed without relief',
            'Closed'
        )                                                              then 'explanation_only'
        else 'other'
    end                                                                as response_category,
    company_public_response,
    timely_response,
    consumer_disputed,
    has_narrative,
    has_full_year_data,

    date_received < '2017-04-24'                                      as is_dispute_era,
    date_received >= '2015-06-01'                                     as is_narrative_era,
    greatest(date_diff(date_sent_to_company, date_received, day), 0) as days_to_company,
    case
        when greatest(date_diff(date_sent_to_company, date_received, day), 0) = 0   then '0_same_day'
        when greatest(date_diff(date_sent_to_company, date_received, day), 0) <= 3  then '1_to_3'
        when greatest(date_diff(date_sent_to_company, date_received, day), 0) <= 14 then '4_to_14'
        else '15_plus'
    end                                                                as days_to_company_bucket

from complaints
