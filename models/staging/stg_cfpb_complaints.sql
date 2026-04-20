-- Thin staging pass over raw.cfpb_complaints.
-- Renames: none needed (source is already snake_case).
-- Transforms: trim all string columns; upper-case 2-char state code.
-- company_name_normalized: UPPER + collapsed whitespace + trailing punct stripped.
-- product_normalized / subproduct_normalized: merges CFPB's legacy taxonomy into current labels.
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
                then 'Unknown'
            else trim(company_public_response)
        end                                  as company_public_response,

        coalesce(trim(consumer_consent_provided), 'Unknown')
                                             as consumer_consent_provided,

        timely_response,
        consumer_disputed,
        has_narrative

    from filtered
),

normalized as (
    select
        *,

        -- CFPB renamed several product categories over time; older complaints use legacy labels.
        -- Consumer Loan is additionally split by subproduct into two current categories.
        -- Unrecognized values pass through unchanged so future additions surface in dim_product.
        case
            when product = 'Bank account or service'
                then 'Checking or savings account'
            when product = 'Consumer Loan' and subproduct in ('Vehicle loan', 'Vehicle lease')
                then 'Vehicle loan or lease'
            when product = 'Consumer Loan'
                then 'Payday loan, title loan, or personal loan'
            when product = 'Credit card'
                then 'Credit card or prepaid card'
            when product = 'Credit reporting'
                then 'Credit reporting, credit repair services, or other personal consumer reports'
            when product = 'Money transfers'
                then 'Money transfer, virtual currency, or money service'
            when product = 'Payday loan'
                then 'Payday loan, title loan, or personal loan'
            when product = 'Prepaid card'
                then 'Credit card or prepaid card'
            when product = 'Virtual currency'
                then 'Money transfer, virtual currency, or money service'
            else product
        end                                  as product_normalized,

        case
            -- Bank account or service: subproduct label differences in legacy taxonomy
            when product = 'Bank account or service' and subproduct = '(CD) Certificate of deposit'
                then 'CD (Certificate of Deposit)'
            when product = 'Bank account or service' and subproduct = 'Other bank product/service'
                then 'Other banking product or service'
            when product = 'Bank account or service' and subproduct = 'Cashing a check without an account'
                then 'Other banking product or service'
            -- Consumer Loan → Vehicle loan or lease: subproduct rename
            when product = 'Consumer Loan' and subproduct = 'Vehicle loan'
                then 'Loan'
            when product = 'Consumer Loan' and subproduct = 'Vehicle lease'
                then 'Lease'
            -- Legacy single-category products: fill null subproduct with best-fit current label
            when product = 'Credit card'     and subproduct is null
                then 'General-purpose credit card or charge card'
            when product = 'Credit reporting' and subproduct is null
                then 'Credit reporting'
            when product = 'Payday loan'     and subproduct is null
                then 'Payday loan'
            -- Prepaid card: map to Credit card or prepaid card subproduct labels
            when product = 'Prepaid card' and subproduct = 'General purpose card'
                then 'General-purpose prepaid card'
            when product = 'Prepaid card' and subproduct = 'Mobile wallet'
                then 'General-purpose prepaid card'
            when product = 'Prepaid card' and subproduct = 'Gift or merchant card'
                then 'Gift card'
            when product = 'Prepaid card'
                and subproduct in ('Government benefit payment card', 'Electronic Benefit Transfer / EBT card')
                then 'Government benefit card'
            when product = 'Prepaid card'
                and subproduct in ('ID prepaid card', 'Other special purpose card', 'Transit card')
                then 'General-purpose prepaid card'
            -- Debt collection: CFPB added " debt" suffix to subproduct labels in newer taxonomy
            when product = 'Debt collection' and subproduct = 'Credit card'             then 'Credit card debt'
            when product = 'Debt collection' and subproduct = 'Medical'                 then 'Medical debt'
            when product = 'Debt collection' and subproduct = 'Payday loan'             then 'Payday loan debt'
            when product = 'Debt collection' and subproduct = 'Mortgage'                then 'Mortgage debt'
            when product = 'Debt collection' and subproduct = 'Auto'                    then 'Auto debt'
            when product = 'Debt collection' and subproduct = 'Federal student loan'    then 'Federal student loan debt'
            when product = 'Debt collection' and subproduct = 'Non-federal student loan' then 'Private student loan debt'
            when product = 'Debt collection' and subproduct = 'Other (i.e. phone, health club, etc.)' then 'Other debt'
            -- Default: pass through unchanged
            else subproduct
        end                                  as subproduct_normalized

    from renamed
)

select * from normalized
