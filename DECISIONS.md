# Design Decisions

Key design choices made during this project, with rationale. Intended for portfolio reviewers and interview context.

---

## Table of Contents

**Source & Staging**
1. [Narrative column dropped at raw materialization](#narrative-column-dropped-at-raw-materialization)
2. [Crosswalk seed instead of fuzzy-matching company names](#crosswalk-seed-instead-of-fuzzy-matching-company-names)
3. [Product taxonomy normalization in staging](#product-taxonomy-normalization-in-staging)
4. [Partial years flagged, not filtered](#partial-years-flagged-not-filtered)

**Modeling & Grain**

5. [Staging → intermediate → marts layering convention](#staging--intermediate--marts-layering-convention)
6. [Fact grain: one row per complaint](#fact-grain-one-row-per-complaint)
7. [Date dimensions: no year/month/quarter on the fact table](#date-dimensions-no-yearmonthquarter-on-the-fact-table)
8. [Consumer disputed era flag (`is_dispute_era`)](#consumer-disputed-era-flag-is_dispute_era)
9. [Product and issue carried on the fact — no dim_product or dim_issue](#product-and-issue-carried-on-the-fact--no-dim_product-or-dim_issue)
10. [days_to_company: routing speed, not resolution time](#days_to_company-routing-speed-not-resolution-time)

**Dimensional Design**

11. [FDIC join grain: top_holder, not institution_name](#fdic-join-grain-top_holder-not-institution_name)
12. [SCD2 snapshot on a frozen source](#scd2-snapshot-on-a-frozen-source)
13. [Bank segment join pattern: fct_complaints → dim_bank](#bank-segment-join-pattern-fct_complaints--dim_bank)
14. [Percentile ranks scoped to 23-bank crosswalk universe](#percentile-ranks-scoped-to-23-bank-crosswalk-universe)

**Semantic Layer**

15. [MetricFlow: metrics defined as code, not in the BI tool](#metricflow-metrics-defined-as-code-not-in-the-bi-tool)

**Production Readiness**

16. [Incremental model design for fct_complaints](#incremental-model-design-for-fct_complaints)
17. [Testing strategy](#testing-strategy)

---

## Narrative column dropped at raw materialization

`raw.cfpb_complaints` does not contain `consumer_complaint_narrative`. It was dropped at materialization from the BigQuery public mirror; a `has_narrative` boolean flag is kept in its place.

Rationale: the narrative column accounts for ~90% of the table's bytes — approximately 1.5 GB of 2.31 GB total. Since narrative text is not used in any model in this project, retaining it would significantly increase scan costs on every downstream query. The `has_narrative` flag preserves the analytical signal (opt-in rate by product, year, and company) at zero storage cost. On a capped BigQuery scan quota, this is a real constraint; the narrative drop is the first and largest optimization applied.

---

## Crosswalk seed instead of fuzzy-matching company names

`seeds/company_crosswalk.csv` hand-maps the top CFPB complaint institutions by volume to canonical names, categories, and FDIC `top_holder` keys. Automated fuzzy matching (edit distance, n-gram similarity) was explicitly rejected.

Rationale: 51 rows covers 74% of complaint volume. The remaining 26% is a long tail of low-volume names where automated matching would have high error rates and low analytical value. Fuzzy matching produces results that are hard to audit — a reviewer can't tell whether a match was correct or coincidental. An explicit seed is transparent: every mapping is a statement of fact that a human verified. For compliance-adjacent data, auditability outweighs automation. Explainability to stakeholders ("this row maps to Equifax because we said so") is also materially easier than "cosine similarity was 0.87."

---

## Product taxonomy normalization in staging

`stg_cfpb_complaints` applies `product_normalized` and `subproduct_normalized` CASE expressions that collapse CFPB's historical taxonomy into current-taxonomy values.

Rationale: CFPB renamed and split product categories mid-dataset. Most notably: several debt collection subcategories gained "debt" suffixes across eras (e.g., "Credit card" → "Credit card debt" within debt collection). A naive `GROUP BY product` double-counts entities that changed names, making the same complaint type appear in different buckets by year. Normalization belongs in staging — not in marts — because it is a source-data judgment, not an analytical choice that should vary per mart. Every downstream consumer gets the corrected taxonomy without reimplementing the CASE.

---

## Partial years flagged, not filtered

`stg_cfpb_complaints` carries a `has_full_year_data` boolean flag (`EXTRACT(YEAR FROM date_received) BETWEEN 2012 AND 2022`) rather than filtering out the 2011 stub and the 2023 partial year.

Rationale: 2011 contains 2,536 rows (December only) and 2023 is cut off at 2023-03-23. Both are structurally partial. Filtering them silently removes real complaints and takes the exclusion decision away from downstream analysts. A flag preserves all data while making the boundary explicit: analysts who want clean year-over-year trend lines filter on `has_full_year_data = true`; analysts who want Q1 2023 data can include it. The judgment about which rows belong in a given analysis stays where it belongs — with the analyst — rather than being baked into staging.

---

## Staging → intermediate → marts layering convention

Every model belongs to exactly one layer with a defined contract:

- **Staging** (`stg_`): source-faithful cleanup only. Rename columns, cast types, trim whitespace, apply boolean flags. No business logic, no joins across sources. The staging model is a trusted, typed version of the source — consumers can rely on column types being consistent even if the raw schema changes.
- **Intermediate** (`int_`): joins and derivations that aren't presentation-layer decisions. The company crosswalk join lives here (not in staging, not in marts) because it combines two sources but produces no analytical grain. FDIC aggregation to the `top_holder` grain lives here for the same reason.
- **Marts** (`dim_`, `fct_`, `mart_`): analytical grain and business definitions. Kimball dimensional models, MetricFlow-registered semantic models, and pre-aggregated decision marts. Business rules — what counts as a "dispute era" complaint, what `product_category` bucket a product falls into — live here or in intermediate, never in staging.

Rationale: each layer has one job, which determines where new logic belongs. A raw-source rename (staging) doesn't cascade to marts. A new analytical bucket (mart) doesn't require touching the crosswalk join (intermediate). This separation also makes the lineage graph meaningful — a reviewer can tell from the model prefix what contract it's operating under.

---

## Fact grain: one row per complaint

`fct_complaints` is a complaint-grain fact — one row per `complaint_id`. This is the canonical Kimball pattern: the grain is the most atomic unit the source publishes, which determines what questions the fact can answer natively and which require pre-aggregation.

A snapshot-grain alternative — one row per complaint lifecycle state (received, forwarded to company, closed) — was considered for processing-speed SLA analysis at the event level. Rejected on three grounds: (1) CFPB doesn't publish lifecycle state changes as distinct events — `date_received` and `date_sent_to_company` are both attributes of a single complaint record; (2) fabricating event rows from one source row would misrepresent the source structure and require synthetic `event_type` values with no source validation; (3) the SLA question the snapshot grain was meant to answer (`days_to_company`) is answerable as a derived column on the complaint-grain fact. The complaint grain is accurate to the source and sufficient for every analytical question in scope.

---

## Date dimensions: no year/month/quarter on the fact table

`fct_complaints` carries `date_received` and `date_sent_to_company` as raw dates but does **not** denormalize `year`, `month`, or `quarter` onto the fact.

Rationale: `dim_date` already provides these via a join on `date_received`. Adding them to the fact duplicates `dim_date`'s reason to exist and signals that the analyst doesn't trust the dimensional model. Any BI tool or query can extract them from the date directly (`EXTRACT(YEAR FROM date_received)`), or join to `dim_date` for richer attributes (fiscal periods, week-of-year, etc.). Keeping the fact lean also means a single `dim_date` change propagates everywhere rather than requiring a fact rebuild. Denormalizing date parts onto the fact is one of the most common anti-patterns in dimensional modeling; keeping them off signals the model is trusted to do its job.

---

## Consumer disputed era flag (`is_dispute_era`)

`fct_complaints` includes `is_dispute_era = (date_received < '2017-04-24')`. The cutoff is CFPB's exact discontinuation date from Release 13, not a rounded year boundary.

Rationale: `consumer_disputed` is 78% null across the full dataset. Fill by era: 100% through 2016, 30% in 2017 (transition year), 0% from 2018 onward. A naive `dispute_rate` metric computed across all years produces a meaningless denominator. The flag gates the metric at the grain level so downstream queries and MetricFlow metric definitions can filter correctly without each analyst independently discovering the cutoff. Using the precise CFPB release date (`2017-04-24`) rather than `'2017-01-01'` preserves the 2017 partial-year data — ~30% fill in that year, not zero.

---

## Product and issue carried on the fact — no dim_product or dim_issue

`fct_complaints` carries `product`, `product_normalized`, `issue`, `subissue`, and `product_category` directly rather than via FK joins to `dim_product` and `dim_issue`.

A dimension earns its existence when it has independent attributes — properties of the entity that aren't derivable from the fact. `dim_date` qualifies (quarter, fiscal period, week-of-year). `dim_company` qualifies (category, fdic_top_holder, temporal stats). Product and issue don't: the only candidate attribute was a grouping bucket, and one derived column on the fact is simpler than a separate model, a join, and a FK test for it.

`product_category` is that derived column: a 7-bucket classification (`mortgage`, `credit_reporting`, `debt_collection`, `banking`, `card`, `payments`, `other`) optimized for dashboard visualization and aggregation. `product_normalized` has 9 values; several are analytically adjacent and would produce a cluttered chart axis. `card` is split from `banking` rather than merged because their complaint patterns differ materially — credit card complaints skew toward disputes and fraud, while checking/savings complaints skew toward fees and access. Merging them would obscure a meaningful signal.

If a CFPB product hierarchy or issue-severity taxonomy were introduced as a source, `dim_product` or `dim_issue` would re-earn their place — the test is whether independent attributes exist, not whether the category matters analytically.

---

## days_to_company: routing speed, not resolution time

The derived column is named `days_to_company`, not `days_to_resolution`.

Rationale: the metric measures `date_sent_to_company - date_received` — CFPB's internal forwarding speed, not how long it took the company to resolve the complaint. "Resolution" implies the complaint is closed; forwarding just means CFPB routed it. Naming it accurately prevents downstream analysts from misreading it as a company SLA metric. Negatives (7,036 pre-2015 rows, -1 day, intake-system clock artifact) are clamped to 0 via `GREATEST(..., 0)`.

---

## FDIC join grain: top_holder, not institution_name

The crosswalk joins CFPB complaint data to FDIC via `top_holder`, not `institution_name`.

CFPB complaints are filed against the brand or parent corporation the consumer recognizes — "JPMORGAN CHASE & CO.", "WELLS FARGO & COMPANY". FDIC's `institution_name` is the legal charter of the specific banking subsidiary — "JPMorgan Chase Bank, National Association", "Wells Fargo Bank, National Association". These are systematically one level apart: a holding company like JPMorgan has multiple subsidiary charters in the FDIC data, none of which match the CFPB name directly. Joining on `institution_name` would miss most rows or require fuzzy matching across thousands of records.

`top_holder` is the ultimate parent holding company name — the same conceptual level as CFPB's naming. Validated via `fdic/exploration.sql` queries 5a/5b: ~94% of the top-50-by-assets FDIC institutions have `top_holder` populated, and the values align structurally with CFPB parent names after a small set of normalization rules (`&` spacing, `BCORP` → `BANCORP`, trailing `THE`, abbreviated words).

`institution_name` is also not a reliable grain for aggregation: a single holding company (e.g., Wintrust) operates dozens of separately-chartered subsidiary banks, each with its own FDIC record. Aggregating complaint volume at the `institution_name` grain would fragment what is effectively one entity into many rows. `top_holder` collapses these correctly.

Known enrichment gap: pre-merger SunTrust and BB&T records carry historically-correct `fdic_top_holder` values (`SUNTRUST BANKS INC`, `BB&T CORP`), but the current FDIC snapshot is active-institutions only — those entities no longer appear. Post-2019 Truist complaints map to `TRUIST FINANCIAL CORP`, which does resolve. In production with a historical FDIC feed, pre-merger records would enrich fully.

---

## SCD2 snapshot on a frozen source

`snapshots/company_renames.sql` tracks `canonical_name` and `fdic_top_holder` changes per `raw_company_name` using dbt's `check` strategy. In production on a live complaint feed, this would automatically record rebrands as they appear — writing a new snapshot row with `dbt_valid_from = change_timestamp` and closing the prior row's `dbt_valid_to`.

The design uses two complementary mechanisms: `parent_as_of` in the crosswalk seed for known-historical rebrands (hand-curated, precise effective dates), and the dbt snapshot for unknown-future changes (automatic — no human intervention required on a live feed). `parent_as_of` captures what happened before the seed was created; the snapshot handles everything afterward.

Three known historical rebrands encoded in `parent_as_of`:
- SunTrust → Truist: 2019-12-01
- BB&T → Truist: 2019-12-01
- BBVA → PNC Bank: 2021-06-01

This source is frozen at 2023-03-25, so the snapshot produces one initial-state row per company (`dbt_valid_to = NULL`) — no future changes will be detected. On a live feed, the snapshot would detect rebrands automatically as `canonical_name` changed in the source data.

---

## Bank segment join pattern: fct_complaints → dim_bank

Bank-segment analysis joins `fct_complaints` to `dim_bank` on `company_sk`. `dim_bank` is 24 rows, so the join is trivially cheap regardless of how many complaint rows are involved.

Different analytical questions use this join differently:

- **Complaint quality metrics by company** (routing speed, timely response rate, dispute rate): aggregate `fct_complaints` by `canonical_name` with `dim_bank` attributes as pass-through columns. This is `mart_bank_complaint_metrics`.
- **Scale-normalized complaint burden** (complaints per $B assets): same join, add `complaint_count / (total_assets_usd / 1e9)` as a derived column. Also in `mart_bank_complaint_metrics`.
- **Tier-level rollups** (how do mega banks compare to large banks?): `GROUP BY bank_size_bucket` on `mart_bank_complaint_metrics`. No separate tier mart needed — `bank_size_bucket` is a dimension column, not a grain.
- **Cross-category analysis** (banks vs. credit bureaus vs. debt collectors): use `fct_complaints` directly with `category` as the grouping dimension. `dim_bank` is bank-specific and not relevant here.
- **Complaint-level detail with bank attributes**: join `fct_complaints → dim_bank` in the consuming query directly. `dim_bank`'s small size means no performance reason to pre-materialize a wide enriched fact.

---

## Percentile ranks scoped to 23-bank crosswalk universe, not full FDIC population

`mart_bank_complaint_metrics` computes `roe_percentile_rank` and `offices_count_percentile_rank` via `PERCENT_RANK()` over the 23 crosswalk banks, not across all 4,756 FDIC top-holder entities.

The analytical question is "how do these banks compare to each other?" not "where does JPMorgan sit in the FDIC universe?" Ranking against all 4,756 holders would put every large crosswalk bank above the 99th percentile — useless for peer comparison. Ranking within the crosswalk universe distributes the field meaningfully: Ally (1 office) anchors the low end of offices count, JPMorgan (5,029) the high end; HSBC (ROE 2.77%) through American Express (51.07%) spans the full 0.0–1.0 range.

Computing in the mart rather than in `int_fdic_banks_normalized` keeps the ranking logic close to its consumer and avoids embedding an assumption about which institutions matter into a general-purpose intermediate model.

---

## MetricFlow: metrics defined as code, not in the BI tool

`models/marts/_metrics.yml` defines a semantic model on `fct_complaints` and 8 metrics (`complaint_count`, `timely_response_rate`, `dispute_rate`, `narrative_rate`, `avg_days_to_company`, and their component counts).

Rationale: without a semantic layer, each analyst or dashboard independently writes the same aggregation logic — and independently makes the same mistakes. The concrete example: `dispute_rate` computed across all 3.5M rows is **4.3%**; computed only against `is_dispute_era = true` (the 768K pre-2017 rows where the field was actually collected) it is **19.3%** — a 4.5× difference from the same column, same table. An ungated metric produces a number that is neither the dispute rate for the era when it was measured, nor a meaningful overall figure. MetricFlow encodes the `is_dispute_era` filter once in the metric definition; every consumer inherits it and can't accidentally get 4.3%.

The closest analogy is LookML, which defines the same semantic layer for Looker. "Semantic layer / metrics framework" appears explicitly in Senior AE job descriptions; this is the dbt-native answer to that requirement.

---

## Incremental model design for fct_complaints

`fct_complaints` is materialized as a `table` against this frozen source. On a live CFPB feed, the correct design is incremental:

```sql
{{ config(materialized='incremental', unique_key='complaint_id', on_schema_change='append_new_columns') }}
...
{% if is_incremental() %}
  and date_received > (select max(date_received) from {{ this }}) - interval 7 day
{% endif %}
```

`unique_key = 'complaint_id'` compiles to a BigQuery `MERGE`, so amended CFPB records overwrite the prior row rather than duplicating it. `on_schema_change='append_new_columns'` handles CFPB's occasional field additions (tags in 2016, narrative in 2015) without breaking existing rows. The 7-day lookback window catches late-arriving complaints — CFPB publishes weekly data releases and occasionally routes records with `date_received` values several days behind the release date. One day would miss late-arrivals; 30 days would re-scan excessive history on every run. Seven days covers observed CFPB release lag with minimal scan overhead. `dbt run --full-refresh --select fct_complaints` rebuilds as a table for backfills or schema changes the append strategy can't handle.

The production config keys (`unique_key`, `on_schema_change`) are set on the model; only the `{% if is_incremental() %}` filter block is omitted, since there is no delta to detect against a frozen source.

---

## Testing strategy

The test suite uses generic tests for column-level invariants and singular SQL tests for structural guarantees not expressible as generic tests.

**Generic tests** guard: PK uniqueness and not_null at every layer (`complaint_id` is tested at source, staging, intermediate, and marts); `accepted_values` on categorical enums (`state`, `category`, `product`, `submitted_via`); and a FK relationship between `fct_complaints.company_sk` and `dim_company.company_sk`. Two `accepted_values` tests use a `config: where:` clause to scope them — e.g., `category` is only validated for crosswalked rows, since null is the correct value for the 26% of complaints that don't match the seed.

**Singular tests** guard invariants that require domain knowledge or cross-model reasoning:

- `assert_int_complaints_no_fanout` — compares row counts between `stg_cfpb_complaints` and `int_complaints_with_company`. The left join on `raw_company_name` can only fan out if the crosswalk seed contains duplicate keys; this test makes that assumption explicit and catches it immediately if violated.
- `assert_crosswalk_coverage` — uses `HAVING` on an aggregate to fail if the crosswalk match rate drops below 74%. Encodes the empirically-validated coverage floor as a regression guard; any seed change that degrades coverage breaks loudly.
- `assert_complaint_dates_ordered` — verifies `date_sent_to_company >= date_received`, scoped to post-2014-04-26 to skip a known intake-system artifact (7,036 pre-2015 rows with -1 day offsets). The date filter encodes documented domain knowledge so the test doesn't flag known-bad historical rows.
- `assert_dispute_era_nulls` — warns when rows with `is_dispute_era = false` have non-null `consumer_disputed`. Set to `severity: warn` rather than error because the 2017 transition year has ~30% fill — a signal, not a hard invariant.
- `assert_mart_bank_rates_in_range` — verifies `timely_response_rate` and `dispute_rate` are both in [0, 1]. A value outside that range means a broken COUNTIF/COUNT ratio; the test returns the offending row for immediate diagnosis.

`where:` clauses scope several tests to the rows where a constraint actually applies: `total_assets` in `stg_fdic_banks` is only asserted not_null for institutions with a `top_holder` (4 of 4,756 institution records have both fields null — documented edge cases excluded by the intermediate filter). `bank_size_bucket` and `total_assets_usd` in `dim_bank` are only asserted for FDIC-enriched rows (Barclays has a documented null enrichment gap). `accepted_values` on `category` in `int_complaints_with_company` only fires for crosswalked rows.

The pattern: generic tests for "this column must always be X," singular tests for "this structural property of the data pipeline must hold," and `where:` clauses to scope both to the population where the invariant is meaningful.

---
