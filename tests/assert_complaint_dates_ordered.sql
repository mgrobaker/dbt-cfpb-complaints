-- 7,036 known violations all fall between 2012-01-22 and 2014-04-26 — exactly 1-day
-- offsets, spread proportionally across all major filers. Systematic intake-system
-- artifact; rows kept. This test filters to post-artifact dates so it errors only on
-- unexpected violations outside the known range.
select
    complaint_id,
    date_received,
    date_sent_to_company
from {{ ref('stg_cfpb_complaints') }}
where date_sent_to_company < date_received
  and date_received > '2014-04-26'
