with distinct_products as (
    select distinct
        product,
        subproduct
    from {{ ref('stg_cfpb_complaints') }}
)

select
    cast(
        farm_fingerprint(concat(product, '|', coalesce(subproduct, '')))
        as string
    )           as product_sk,
    product,
    subproduct
from distinct_products
