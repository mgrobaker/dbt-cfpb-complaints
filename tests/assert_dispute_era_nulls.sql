-- consumer_disputed has 100% fill through 2016, drops to 0% by 2018. CFPB
-- discontinued the field on 2017-04-24 (Release 13). Every complaint outside
-- the dispute era (is_dispute_era = false) should have a NULL consumer_disputed.
-- Failures here mean either the era cutoff date is wrong or unexpected non-null
-- values crept into the post-discontinuation period.
{{ config(severity='warn') }}

select
    complaint_id,
    date_received,
    consumer_disputed
from {{ ref('fct_complaints') }}
where is_dispute_era = false
  and consumer_disputed is not null
