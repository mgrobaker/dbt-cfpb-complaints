with distinct_products as (
    select distinct
        product_normalized,
        subproduct_normalized
    from {{ ref('stg_cfpb_complaints') }}
)

select
    cast(
        farm_fingerprint(concat(product_normalized, '|', coalesce(subproduct_normalized, '')))
        as string
    )                       as product_sk,
    product_normalized      as product,
    subproduct_normalized   as subproduct
from distinct_products
