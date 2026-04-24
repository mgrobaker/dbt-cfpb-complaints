{% docs __overview__ %}

# CFPB Complaints — Analytics Engineering Portfolio

A dbt project modeling the CFPB Consumer Complaint Database (~3.5M rows, 2011–2023) on BigQuery, enriched with FDIC institution data. Code, setup instructions, and architectural decisions live on [GitHub](https://github.com/mgrobaker/dbt-cfpb-complaints) — this site is for exploring the build itself.

## Where to start

If you have ten minutes, in this order:

1. **`fct_complaints`** — the grain-of-truth fact table. Note `is_dispute_era` and `is_narrative_era` flags that gate metrics against known policy changes (the `consumer_disputed` field was discontinued in April 2017).
2. **`dim_company`** + **`dim_bank`** — the entity-resolution layer. A 50-row manual crosswalk seed covers ~80% of complaint volume; FDIC joins at the parent-corp grain via `top_holder`, not `institution_name`.
3. **`mart_bank_complaint_metrics`** — scale-normalized bank segment analysis across 23 banks (complaints per $B assets, routing speed, dispute rate, percentile ranks).
4. **Metrics** (semantic layer) — MetricFlow definitions including era-gated `dispute_rate` and `narrative_rate` that refuse to silently compute across years the source fields weren't collected.

Click any node in the lineage graph (button, top-right) to explore dependencies, columns, and tests.

{% enddocs %}
