with distinct_issues as (
    select distinct
        issue,
        subissue
    from {{ ref('stg_cfpb_complaints') }}
)

select
    cast(
        farm_fingerprint(concat(issue, '|', coalesce(subissue, '')))
        as string
    )           as issue_sk,
    issue,
    subissue
from distinct_issues
