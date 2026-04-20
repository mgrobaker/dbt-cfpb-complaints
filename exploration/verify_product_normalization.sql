-- Verify product normalization in stg_cfpb_complaints / dim_product.
-- Run after dbt run on stg_cfpb_complaints, dim_product, fct_complaints.

-- 1. Canonical product list post-normalization (should be ~10 distinct products, no legacy names)
select product, count(*) as subproduct_count
from dbt_dev.dim_product
group by 1
order by 1;

-- 2. Confirm no legacy product names remain in the fact table
--    Expect 0 rows for all of these
select
    countif(product_normalized = 'Bank account or service')           as bank_account_legacy,
    countif(product_normalized = 'Consumer Loan')                     as consumer_loan_legacy,
    countif(product_normalized = 'Credit card'
        and product_normalized != 'Credit card or prepaid card')      as credit_card_legacy,
    countif(product_normalized = 'Credit reporting'
        and length(product_normalized) < 20)                          as credit_reporting_legacy,
    countif(product_normalized = 'Money transfers')                   as money_transfers_legacy,
    countif(product_normalized = 'Payday loan'
        and product_normalized != 'Payday loan, title loan, or personal loan') as payday_loan_legacy,
    countif(product_normalized = 'Prepaid card')                      as prepaid_card_legacy,
    countif(product_normalized = 'Virtual currency')                  as virtual_currency_legacy
from dbt_dev.fct_complaints;

-- 3. Spot-check: Debt collection subproducts — old labels should be gone, new labels present
--    Expect 0 rows for Credit card / Medical / Payday loan / Mortgage / Auto (without "debt" suffix)
select subproduct_normalized, count(*) as n
from dbt_dev.stg_cfpb_complaints
where product_normalized = 'Debt collection'
group by 1
order by n desc;

-- 4. Consumer Loan split — confirm all rows went to one of the two new products
--    Expect 0 rows with product_normalized = 'Consumer Loan'
select product_normalized, subproduct_normalized, count(*) as n
from dbt_dev.stg_cfpb_complaints
where product = 'Consumer Loan'
group by 1, 2
order by 1, 2;

-- 5. dim_product row count sanity — 66 rows expected post-normalization
select count(*) as total_product_rows from dbt_dev.dim_product;
