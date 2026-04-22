# Design Decisions

Key design choices made during this project, with rationale. Intended for portfolio reviewers and interview context.

---

## Date dimensions: no year/month/quarter on the fact table

`fct_complaints` carries `date_received` and `date_sent_to_company` as raw dates but does **not** denormalize `year`, `month`, or `quarter` onto the fact.

Rationale: `dim_date` already provides these via a join on `date_received`. Adding them to the fact duplicates `dim_date`'s reason to exist and signals that the analyst doesn't trust the dimensional model. Any BI tool or query can extract them from the date directly (`EXTRACT(YEAR FROM date_received)`), or join to `dim_date` for richer attributes (fiscal periods, week-of-year, etc.). Keeping the fact lean also means a single `dim_date` change propagates everywhere rather than requiring a fact rebuild.

---

## Consumer disputed era flag (`is_dispute_era`)

`fct_complaints` includes `is_dispute_era = (date_received < '2017-04-24')`. The cutoff is CFPB's exact discontinuation date from Release 13, not a rounded year boundary.

Rationale: `consumer_disputed` has 100% fill through 2016 and 0% from 2018 onward. A naive `dispute_rate` metric computed across all years produces a meaningless denominator. The flag gates the metric at the grain level so downstream queries and MetricFlow metric definitions can filter correctly without each analyst independently discovering the cutoff. Using the precise CFPB release date (`2017-04-24`) rather than `'2017-01-01'` preserves the 2017 partial-year data — ~30% fill in that year, not zero.

---

## SCD2 snapshot on a frozen source

`snapshots/company_renames.sql` tracks `canonical_name` and `fdic_top_holder` changes per `raw_company_name` using dbt's `check` strategy. In production on a live complaint feed, this would automatically record rebrands as they appear — writing a new snapshot row with `dbt_valid_from = change_timestamp` and closing the prior row's `dbt_valid_to`.

This source is frozen at 2023-03-25, so the snapshot establishes initial state only; no future changes will be detected. The two known historical rebrands are encoded in the crosswalk's `parent_as_of` column instead, which records the effective date of each entity change:

- SunTrust → Truist: 2019-12-01
- BB&T → Truist: 2019-12-01

(Alliance Data never appears in CFPB complaint data under that name — Bread Financial Holdings is its own crosswalk row with no `parent_as_of`.)

Query `stg_company_crosswalk WHERE parent_as_of IS NOT NULL` to surface these. The snapshot demonstrates the Kimball SCD2 pattern and correct dbt configuration; the `parent_as_of` column demonstrates how effective dates would be tracked in the source.

One known FDIC enrichment gap: pre-merger SunTrust and BB&T records carry historically-correct `fdic_top_holder` values (`SUNTRUST BANKS INC`, `BB&T CORP`), but the current FDIC snapshot is active-institutions only — those entities no longer appear. Post-2019 Truist complaints map to `TRUIST FINANCIAL CORP`, which does resolve. In production with a historical FDIC feed, pre-merger records would enrich fully.

---

## FDIC join grain: top_holder, not institution_name

The crosswalk joins CFPB complaint data to FDIC via `top_holder`, not `institution_name`.

CFPB complaints are filed against the brand or parent corporation the consumer recognizes — "JPMORGAN CHASE & CO.", "WELLS FARGO & COMPANY". FDIC's `institution_name` is the legal charter of the specific banking subsidiary — "JPMorgan Chase Bank, National Association", "Wells Fargo Bank, National Association". These are systematically one level apart: a holding company like JPMorgan has multiple subsidiary charters in the FDIC data, none of which match the CFPB name directly. Joining on `institution_name` would miss most rows or require fuzzy matching across thousands of records.

`top_holder` is the ultimate parent holding company name — the same conceptual level as CFPB's naming. Validated via `fdic/exploration.sql` queries 5a/5b: ~94% of the top-50-by-assets FDIC institutions have `top_holder` populated, and the values align structurally with CFPB parent names after a small set of normalization rules (`&` spacing, `BCORP` → `BANCORP`, trailing `THE`, abbreviated words). These normalization quirks are the planned work for `int_fdic_banks_normalized` (Phase 3).

`institution_name` is also not a reliable grain for aggregation: a single holding company (e.g., Wintrust) operates dozens of separately-chartered subsidiary banks, each with its own FDIC record. Aggregating complaint volume at the `institution_name` grain would fragment what is effectively one entity into many rows. `top_holder` collapses these correctly.

---

## dim_product and dim_issue dropped

`fct_complaints` carries `product`, `product_normalized`, `issue`, `subissue`, and related columns directly rather than via FK joins to `dim_product` and `dim_issue`.

Rationale: a dimension earns its existence when it has independent attributes — properties of the entity that aren't derivable from the fact. `dim_date` qualifies (quarter, fiscal period, week-of-year). `dim_company` qualifies (category, fdic_top_holder, temporal stats). Product and issue don't: the only candidate attribute was a `product_category` grouping bucket, and carrying one extra column on the fact is simpler than adding a model, a join, and a FK test for it. Keeping product and issue on the fact also makes the lineage graph easier to read — no spurious dim nodes that add hops without adding information.

---

## MetricFlow: metrics defined as code, not in the BI tool

`models/marts/_metrics.yml` defines a semantic model on `fct_complaints` and 8 metrics (`complaint_count`, `timely_response_rate`, `dispute_rate`, `narrative_rate`, `avg_days_to_company`, and their component counts).

Rationale: without a semantic layer, each analyst or dashboard independently writes the same aggregation logic — and independently makes the same mistakes (e.g., computing `dispute_rate` across all years when `consumer_disputed` is only meaningful pre-2017-04-24). MetricFlow encodes the filter logic once in the metric definition; every consumer inherits it. The era-filtered metrics (`dispute_rate` gated on `is_dispute_era`, `narrative_rate` gated on `is_narrative_era`) are the concrete example: the cutoff logic lives in the YAML, not in dashboards.

The closest analogy is LookML, which defines the same semantic layer for Looker. "Semantic layer / metrics framework" appears explicitly in Senior AE job descriptions; this is the dbt-native answer to that requirement.

---

## Incremental model design for fct_complaints

`fct_complaints` is materialized as a `table` (full rebuild on every run). On a live CFPB feed, this would be redesigned as an incremental model. The implementation is documented here but not built against the frozen source — there's no new data to detect, so running incremental against this dataset would just add machinery with nothing to exercise.

**Configuration:**

```sql
{{ config(
    materialized='incremental',
    unique_key='complaint_id',
    on_schema_change='append_new_columns'
) }}
```

**Incremental filter** (appended inside the CTE, after the `where` clause that already filters 2012–2022):

```sql
{% if is_incremental() %}
  and date_received > (select max(date_received) from {{ this }})
{% endif %}
```

**Why `unique_key = complaint_id`**: CFPB occasionally amends complaint records. `unique_key` tells dbt to `MERGE` on `complaint_id` rather than append-only `INSERT`, so amended records overwrite the prior row rather than duplicating it. On BigQuery this compiles to a `MERGE` statement.

**Why `on_schema_change='append_new_columns'`**: new CFPB releases occasionally add fields (e.g., tags in 2016, narrative in 2015). Append-new-columns passes new columns through without breaking existing rows. `sync_all_columns` would be safer but requires a full rebuild on schema change; `fail` would block the run entirely.

**Late-arriving data caveat**: the `max(date_received)` watermark assumes complaints arrive roughly in order. CFPB's public dataset occasionally has complaints with older `date_received` values arriving in later releases (agency routing delay). A production implementation would use a lookback window — e.g., `date_received > (select max(date_received) from {{ this }}) - interval 7 day` — to catch late arrivals at the cost of reprocessing the most recent week on every run.

**Full-refresh escape hatch**: `dbt run --full-refresh --select fct_complaints` rebuilds as a table, useful when backfilling or after schema changes that `append_new_columns` can't handle.

---

## days_to_company: routing speed, not resolution time

The derived column is named `days_to_company`, not `days_to_resolution`.

Rationale: the metric measures `date_sent_to_company - date_received` — CFPB's internal forwarding speed, not how long it took the company to resolve the complaint. "Resolution" implies the complaint is closed; forwarding just means CFPB routed it. Naming it accurately prevents downstream analysts from misreading it as a company SLA metric. Negatives (7,036 pre-2015 rows, -1 day, intake-system clock artifact) are clamped to 0 via `GREATEST(..., 0)`.

---
