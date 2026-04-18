-- 7,036 violations (~0.2% of rows). All exactly 1-day offsets, all in 2012-2014,
-- spread proportionally across every major filer. Systematic intake system artifact,
-- not a real data error. Rows kept; severity warn.
{{ config(severity='warn') }}

select
    complaint_id,
    date_received,
    date_sent_to_company
from {{ ref('stg_cfpb_complaints') }}
where date_sent_to_company < date_received
