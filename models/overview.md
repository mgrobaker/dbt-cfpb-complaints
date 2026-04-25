{% docs __overview__ %}

# CFPB Complaints — Analytics Engineering Portfolio

A dbt project modeling the CFPB Consumer Complaint Database (~3.5M rows, 2011–2023) on BigQuery, enriched with FDIC institution data. Code, setup instructions, and architectural decisions live on [GitHub](https://github.com/mgrobaker/dbt-cfpb-complaints) — this site is for exploring the build itself.

## Where to start

If you have ten minutes, in this order:

1. **`fct_complaints`** — the grain-of-truth fact table. Note `is_dispute_era` and `is_narrative_era` flags that gate metrics against known policy changes (the `consumer_disputed` field was discontinued in April 2017).
2. **`dim_company`** + **`dim_bank`** — the entity-resolution layer. A 50-row manual crosswalk seed covers ~80% of complaint volume; FDIC joins at the parent-corp grain via `top_holder`, not `institution_name`.
3. **`mart_bank_complaint_metrics`** — scale-normalized bank segment analysis across 23 banks (complaints per $B assets, routing speed, dispute rate, percentile ranks). Bank-grain executive summary.
4. **`mart_bank_complaints_monthly`** — time-series companion at bank × month × product_category grain (~17.5K rows). Stores measure components, not rates, so any rollup is Simpson's-paradox-safe.
5. **Metrics** (semantic layer) — MetricFlow definitions: era-filtered `dispute_rate` and `narrative_rate` (null, not misleadingly zero, for years the source field wasn't collected); `complaints_per_billion_assets` as a derived metric across the complaints and banks semantic models; MoM/YoY change metrics on `complaint_count` via `metric_time` offset windows.

Click any node in the lineage graph (button, top-right) to explore dependencies, columns, and tests.

{% enddocs %}
