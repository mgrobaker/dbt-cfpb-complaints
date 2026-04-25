-- Era-component coherence: in mart_bank_complaints_monthly, the era-gated
-- numerators (disputed_count, narrative_count) must be NULL exactly when their
-- denominators (complaint_count_dispute_era, complaint_count_narrative_era) are 0.
-- A NULL numerator with a positive denominator — or a non-NULL numerator with a
-- zero denominator — would break era-gated rate rollups (rate of summed
-- components = correct rate; the components must agree on which cells are in-era).
{{ config(severity='error') }}

select
    canonical_name,
    month_start,
    product_category,
    complaint_count_dispute_era,
    disputed_count,
    complaint_count_narrative_era,
    narrative_count
from {{ ref('mart_bank_complaints_monthly') }}
where
    (disputed_count is null and complaint_count_dispute_era > 0)
    or (disputed_count is not null and complaint_count_dispute_era = 0)
    or (narrative_count is null and complaint_count_narrative_era > 0)
    or (narrative_count is not null and complaint_count_narrative_era = 0)
