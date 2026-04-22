-- timely_response_rate and dispute_rate must be between 0 and 1 (inclusive).
-- dispute_rate can be null for banks with no dispute-era complaints.
-- A value outside [0,1] indicates a broken COUNTIF/COUNT ratio.

select
    canonical_name,
    timely_response_rate,
    dispute_rate
from {{ ref('mart_bank_complaint_metrics') }}
where
    timely_response_rate < 0
    or timely_response_rate > 1
    or dispute_rate < 0
    or dispute_rate > 1
