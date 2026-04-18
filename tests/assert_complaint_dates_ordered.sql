select
    complaint_id,
    date_received,
    date_sent_to_company
from {{ ref('stg_cfpb_complaints') }}
where date_sent_to_company < date_received
