# Design Decisions

Key design choices and tradeoffs. Each entry states the decision, then the rationale. ⭐ marks the three most interesting for a quick read.

## If you only read three

- ⭐ [#2 Crosswalk seed over fuzzy matching](#crosswalk-seed-instead-of-fuzzy-matching-company-names) — entity resolution: why a 50-row hand-curated seed beats automated matching on compliance-adjacent data.
- ⭐ [#8 `is_dispute_era` flag](#consumer-disputed-era-flag-is_dispute_era) — a single column the CFPB stopped collecting mid-dataset turns into a 4.3% vs. 19.3% dispute rate depending on whether you gate it.
- ⭐ [#11 FDIC join at `top_holder`](#fdic-join-grain-top_holder-not-institution_name) — dimensional modeling taste: joining at the parent-corp grain collapses multi-charter holders correctly.

## Contents

**[Source & Staging](#source--staging)**

1. [Narrative column dropped at raw materialization](#narrative-column-dropped-at-raw-materialization)
2. ⭐ [Crosswalk seed over fuzzy matching](#crosswalk-seed-instead-of-fuzzy-matching-company-names)
3. [Product taxonomy normalization in staging](#product-taxonomy-normalization-in-staging)
4. [Partial years flagged, not filtered](#partial-years-flagged-not-filtered)

**[Modeling & Grain](#modeling--grain)**

5. [Staging → intermediate → marts layering](#staging--intermediate--marts-layering-convention)
6. [Fact grain: one row per complaint](#fact-grain-one-row-per-complaint)
7. [No date parts on the fact](#no-date-parts-on-the-fact)
8. ⭐ [`is_dispute_era` flag](#consumer-disputed-era-flag-is_dispute_era)
9. [No `dim_product` or `dim_issue`](#no-dim_product-or-dim_issue)
10. [`days_to_company`: routing speed, not resolution](#days_to_company-routing-speed-not-resolution-time)

**[Dimensional Design](#dimensional-design)**

11. ⭐ [FDIC join grain: `top_holder`](#fdic-join-grain-top_holder-not-institution_name)
12. [SCD2 snapshot on a frozen source](#scd2-snapshot-on-a-frozen-source)
13. [Bank segment join: `fct_complaints` → `dim_bank`](#bank-segment-join-fct_complaints--dim_bank)
14. [Percentile ranks scoped to the crosswalk](#percentile-ranks-scoped-to-the-crosswalk)
15. [Bank size buckets calibrated to the crosswalk](#bank-size-buckets-calibrated-to-the-crosswalk)

**[Semantic, Production & Limits](#semantic-production--limits)**

16. [MetricFlow: metrics as code](#metricflow-metrics-as-code)
17. [Incremental design for `fct_complaints`](#incremental-design-for-fct_complaints)
18. [Testing strategy](#testing-strategy)
19. [ZIP privacy codes — staging bug](#zip-privacy-codes--staging-bug)

---

## Source & Staging

### Narrative column dropped at raw materialization

**`raw.cfpb_complaints` does not contain `consumer_complaint_narrative`** — it was dropped at materialization from the BigQuery public mirror; a `has_narrative` boolean flag is kept in its place.

Rationale: the narrative column accounts for ~90% of the table's bytes — approximately 1.5 GB of 2.31 GB total. Since narrative text is not used in any model in this project, retaining it would significantly increase scan costs on every downstream query. The `has_narrative` flag preserves the analytical signal (opt-in rate by product, year, and company) at zero storage cost. On a capped BigQuery scan quota, this is a real constraint; the narrative drop is the first and largest optimization applied.

---

### Crosswalk seed instead of fuzzy-matching company names

**`seeds/company_crosswalk.csv` hand-maps the top CFPB complaint institutions by volume** to canonical names, categories, and FDIC `top_holder` keys. Automated fuzzy matching (edit distance, n-gram similarity) was explicitly rejected.

Rationale: 50 hand-curated rows cover ~80% of complaint volume; the remaining 20% is a long tail where automated matching would have high error rates and low analytical value. Fuzzy matching is hard to audit — a reviewer can't tell whether a match was correct or coincidental. An explicit seed is transparent: every mapping is a statement of fact a human verified. For compliance-adjacent data, auditability outweighs automation, and explainability to stakeholders ("this row maps to Equifax because we said so") beats "cosine similarity was 0.87." The crosswalk also carries `fdic_top_holder` for downstream bank enrichment — see [#11](#fdic-join-grain-top_holder-not-institution_name).

The top 30 by complaint volume include a mix of company types. Credit bureaus alone are 47% of all complaint volume — they have no FDIC record and are excluded from bank-segment analysis:

| Category | Examples |
|---|---|
| Credit bureaus | Equifax, TransUnion, Experian, LexisNexis |
| Debt collectors | Portfolio Recovery, Encore Capital, Resurgent |
| Mortgage servicers | Ocwen, Ditech, Nationstar, Shellpoint |
| Student loan servicers | Navient, AES/PHEAA, Nelnet |
| Fintechs | PayPal, Coinbase |
| Auto/subprime lenders | Santander Consumer, Ally |

FDIC enrichment gates on `category = 'bank'` only — roughly 23% of total complaint volume at 98% FDIC fill rate.

---

### Product taxonomy normalization in staging

**`stg_cfpb_complaints` normalizes CFPB's historical product taxonomy into current-taxonomy values** by joining to the `product_mapping` and `subproduct_mapping` seeds. One inline CASE handles the Consumer Loan + vehicle-subproduct split (where `product_normalized` depends on `subproduct`); all other renames come from the seeds.

Rationale: CFPB renamed and split product categories mid-dataset. Most notably: several debt collection subcategories gained "debt" suffixes across eras (e.g., "Credit card" → "Credit card debt" within debt collection). A naive `GROUP BY product` double-counts entities that changed names, making the same complaint type appear in different buckets by year. Normalization belongs in staging — not in marts — because it is a source-data judgment, not an analytical choice that should vary per mart. Using seeds rather than inline CASE keeps the mapping auditable in diff and reviewable as a table.

---

### Partial years flagged, not filtered

**`stg_cfpb_complaints` flags partial years rather than filtering them out** via `has_full_year_data = (EXTRACT(YEAR FROM date_received) BETWEEN 2012 AND 2022)`.

Rationale: 2011 contains 2,536 rows (December only) and 2023 is cut off at 2023-03-23. Both are structurally partial. Filtering them silently removes real complaints and takes the exclusion decision away from downstream analysts. A flag preserves all data while making the boundary explicit: analysts who want clean year-over-year trend lines filter on `has_full_year_data = true`; analysts who want Q1 2023 data can include it. The judgment stays with the analyst, not baked into staging.

---

## Modeling & Grain

### Staging → intermediate → marts layering convention

**Every model belongs to exactly one layer with a defined contract:**

- **Staging** (`stg_`): source-faithful cleanup only. Rename columns, cast types, trim whitespace, apply boolean flags. No business logic, no joins across sources. The staging model is a trusted, typed version of the source — consumers can rely on column types being consistent even if the raw schema changes.
- **Intermediate** (`int_`): joins and derivations that aren't presentation-layer decisions. The company crosswalk join lives here (not in staging, not in marts) because it combines two sources but produces no analytical grain. FDIC aggregation to the `top_holder` grain lives here for the same reason.
- **Marts** (`dim_`, `fct_`, `mart_`): analytical grain and business definitions. Kimball dimensional models, MetricFlow-registered semantic models, and pre-aggregated decision marts. Business rules — what counts as a "dispute era" complaint, what `product_category` bucket a product falls into — live here or in intermediate, never in staging.

Each layer has one job, which determines where new logic belongs. A raw-source rename doesn't cascade to marts; a new analytical bucket doesn't require touching the crosswalk join. The separation also makes the lineage graph meaningful — a reviewer can tell from the model prefix what contract it's operating under.

---

### Fact grain: one row per complaint

**`fct_complaints` is complaint-grain — one row per `complaint_id`.** The canonical Kimball pattern: the grain is the most atomic unit the source publishes.

A snapshot-grain alternative — one row per complaint lifecycle state (received, forwarded to company, closed) — was considered for event-level SLA analysis. Rejected on three grounds:

- CFPB doesn't publish lifecycle state changes as distinct events — `date_received` and `date_sent_to_company` are both attributes of a single complaint record.
- Fabricating event rows from one source row would misrepresent the source structure and require synthetic `event_type` values with no source validation.
- The SLA question the snapshot grain was meant to answer (`days_to_company`) is answerable as a derived column on the complaint-grain fact.

---

### No date parts on the fact

**`fct_complaints` carries `date_received` and `date_sent_to_company` as raw dates only** — no denormalized `year`, `month`, or `quarter` columns.

Rationale: `dim_date` already provides these via a join on `date_received`. Adding them to the fact duplicates `dim_date`'s reason to exist and signals that the analyst doesn't trust the dimensional model. Any BI tool or query can extract them from the date directly (`EXTRACT(YEAR FROM date_received)`), or join to `dim_date` for richer attributes (fiscal periods, week-of-year, etc.). Keeping the fact lean also means a single `dim_date` change propagates everywhere rather than requiring a fact rebuild. Denormalizing date parts onto the fact is one of the most common anti-patterns in dimensional modeling; keeping them off signals the model is trusted to do its job.

---

### Consumer disputed era flag (`is_dispute_era`)

**`fct_complaints` includes `is_dispute_era = (date_received < '2017-04-24')`** — the cutoff is CFPB's exact discontinuation date from Release 13, not a rounded year boundary.

Rationale: `consumer_disputed` is 78% null across the full dataset. Fill by era: 100% through 2016, 30% in 2017 (transition year), 0% from 2018 onward. A naive `dispute_rate` metric computed across all years produces a meaningless denominator — **4.3% across all rows vs. 19.3% against the era-gated base**, a 4.5× gap from the same column, same table. The flag gates the metric at the grain level so downstream queries and MetricFlow metric definitions can filter correctly without each analyst independently discovering the cutoff. Using the precise CFPB release date (`2017-04-24`) rather than `'2017-01-01'` preserves the 2017 partial-year data — ~30% fill in that year, not zero.

Same "flag, don't filter" pattern as [#4](#partial-years-flagged-not-filtered) (`has_full_year_data`): staging preserves all rows; gating happens at the metric layer where the analyst can override.

---

### No `dim_product` or `dim_issue`

**`fct_complaints` carries `product`, `product_normalized`, `issue`, `subissue`, and `product_category` directly** rather than via FK joins to `dim_product` and `dim_issue`.

A dimension earns its existence when it has independent attributes — properties of the entity that aren't derivable from the fact. `dim_date` qualifies (quarter, fiscal period, week-of-year). `dim_company` qualifies (category, `fdic_top_holder`, temporal stats). Product and issue don't: the only candidate attribute was a grouping bucket, and one derived column on the fact is simpler than a separate model, a join, and a FK test for it.

`product_category` is that derived column: a 7-bucket classification (`mortgage`, `credit_reporting`, `debt_collection`, `banking`, `card`, `payments`, `other`) optimized for dashboard visualization. `card` is split from `banking` rather than merged because their complaint patterns differ materially — credit card complaints skew toward disputes and fraud, while checking/savings complaints skew toward fees and access. Merging them would obscure a meaningful signal.

If a CFPB product hierarchy or issue-severity taxonomy were introduced as a source, `dim_product` or `dim_issue` would re-earn their place — the test is whether independent attributes exist, not whether the category matters analytically.

---

### `days_to_company`: routing speed, not resolution time

**The derived column is named `days_to_company`, not `days_to_resolution`** — deliberately.

Rationale: the metric measures `date_sent_to_company - date_received` — CFPB's internal forwarding speed, not how long it took the company to resolve the complaint. "Resolution" implies the complaint is closed; forwarding just means CFPB routed it. Naming it accurately prevents downstream analysts from misreading it as a company SLA metric. Negatives (7,052 pre-2015 rows, typically -1 day, intake-system clock artifact) are clamped to 0 via `GREATEST(..., 0)`. Zero-day rates by era: pre-2015 ~35%, 2015–2019 ~75%, 2020+ ~92% — CFPB progressively automated same-day routing over the decade.

---

## Dimensional Design

### FDIC join grain: top_holder, not institution_name

**The crosswalk joins CFPB complaint data to FDIC via `top_holder`, not `institution_name`.**

CFPB complaints name the parent corporation the consumer recognizes — "JPMORGAN CHASE & CO.", "WELLS FARGO & COMPANY". FDIC's `institution_name` is the legal charter of a specific subsidiary — "JPMorgan Chase Bank, National Association". These are one level apart: a holding company like JPMorgan has multiple subsidiary charters in FDIC, none matching the CFPB name directly.

`top_holder` is the ultimate parent — the same conceptual level as CFPB's naming. Validated via `fdic/exploration.sql` queries 5a/5b: ~94% of the top-50-by-assets FDIC institutions have `top_holder` populated, and values align with CFPB names after a small set of normalization rules (`&` spacing, `BCORP` → `BANCORP`, trailing `THE`).

`institution_name` is also unusable as an aggregation grain: Wintrust operates dozens of separately-chartered subsidiaries, each its own FDIC record. Aggregating at `institution_name` would fragment one entity into many rows; `top_holder` collapses them correctly.

For multi-charter holders, `primary_specialization` is aggregated as largest-charter-by-assets wins (175 holders span multiple values in the FDIC data) — the specialization label that best represents the holding company's dominant business, rather than a mode that can flip with a minor charter.

Known enrichment gaps — the current FDIC snapshot is active-institutions only, so three crosswalk banks don't resolve fully:

- **SunTrust** and **BB&T** (pre-merger records): `fdic_top_holder` values (`SUNTRUST BANKS INC`, `BB&T CORP`) were historically correct but those entities no longer appear. Post-2019 Truist complaints map to `TRUIST FINANCIAL CORP`, which does resolve.
- **Barclays**: the US card-issuing entity (Barclays Bank Delaware) doesn't roll up to a `top_holder` that matches CFPB's `BARCLAYS PLC` naming. Barclays appears in `dim_bank` with NULL FDIC columns and is filtered out of `mart_bank_complaint_metrics` via `where total_assets_usd is not null`.

In production with a historical FDIC feed and broader international coverage, these gaps would close.

---

### SCD2 snapshot on a frozen source

**`snapshots/company_renames.sql` tracks `canonical_name` and `fdic_top_holder` changes per `raw_company_name` using dbt's `check` strategy.** On a live complaint feed, this would automatically record rebrands as they appear — writing a new snapshot row with `dbt_valid_from = change_timestamp` and closing the prior row's `dbt_valid_to`.

The design uses two complementary mechanisms: `parent_as_of` in the crosswalk seed for known-historical rebrands (hand-curated, precise effective dates), and the dbt snapshot for unknown-future changes (automatic — no human intervention required on a live feed). `parent_as_of` captures what happened before the seed was created; the snapshot handles everything afterward.

Three known historical rebrands encoded in `parent_as_of`:
- SunTrust → Truist: 2019-12-01
- BB&T → Truist: 2019-12-01
- BBVA → PNC Bank: 2021-06-01

This source is frozen at 2023-03-25, so the snapshot produces one initial-state row per company (`dbt_valid_to = NULL`) — no future changes will be detected. On a live feed, the snapshot would detect rebrands automatically as `canonical_name` changed in the source data.

---

### Bank segment join: `fct_complaints` → `dim_bank`

**Bank-segment analysis joins `fct_complaints` to `dim_bank` on `company_sk`.** `dim_bank` is 24 rows (23 FDIC-enriched + Barclays with NULL FDIC columns), so the join is trivially cheap regardless of how many complaint rows are involved.

Different analytical questions use this join differently:

- **Complaint quality metrics by company** (routing speed, timely response rate, dispute rate): aggregate `fct_complaints` by `canonical_name` with `dim_bank` attributes as pass-through columns. This is `mart_bank_complaint_metrics`.
- **Scale-normalized complaint burden** (complaints per $B assets): same join, add `complaint_count / (total_assets_usd / 1e9)` as a derived column. Also in `mart_bank_complaint_metrics`.
- **Tier-level rollups** (how do mega banks compare to large banks?): `GROUP BY bank_size_bucket` on `mart_bank_complaint_metrics`. No separate tier mart needed — `bank_size_bucket` is a dimension column, not a grain.
- **Cross-category analysis** (banks vs. credit bureaus vs. debt collectors): use `fct_complaints` directly with `category` as the grouping dimension. `dim_bank` is bank-specific and not relevant here.
- **Complaint-level detail with bank attributes**: join `fct_complaints → dim_bank` in the consuming query directly. `dim_bank`'s small size means no performance reason to pre-materialize a wide enriched fact.

Percentile ranks within this mart are scoped to the crosswalk universe rather than the full FDIC population — see [#14](#percentile-ranks-scoped-to-the-crosswalk). Asset-tier thresholds are calibrated to this same universe — see [#15](#bank-size-buckets-calibrated-to-the-crosswalk).

---

### Percentile ranks scoped to the crosswalk

**`mart_bank_complaint_metrics` computes `roe_percentile_rank` and `offices_count_percentile_rank` over the 23 crosswalk banks, not the full FDIC universe** (3,442 distinct top-holders aggregated from 4,756 institution records).

The analytical question is "how do these banks compare to each other?" not "where does JPMorgan sit in the FDIC universe?" Ranking against all 3,442 holders would put every large crosswalk bank above the 99th percentile — useless for peer comparison. Ranking within the crosswalk universe distributes the field meaningfully: Ally (1 office) anchors the low end of offices count, JPMorgan (5,029) the high end; HSBC (ROE 2.77%) through American Express (51.07%) spans the full 0.0–1.0 range.

Computing in the mart rather than in `int_fdic_banks_normalized` keeps the ranking logic close to its consumer and avoids embedding an assumption about which institutions matter into a general-purpose intermediate model.

---

### Bank size buckets calibrated to the crosswalk

**`bank_size_bucket` uses cutpoints mega (>$1T), large ($400B–$1T), mid ($175B–$400B), smaller (<$175B)** — deliberately not the regulatory $250B SIFI line or G-SIB tiers.

Rationale: the analytical use is peer comparison within the 23-bank crosswalk, not compliance classification. SIFI's $250B line would put 8 banks in one tier and split the remainder awkwardly; the chosen cutpoints distribute the field meaningfully across all four buckets. The trade-off is explicit: these thresholds would shift if the universe expanded. Rebuilding the mart on a different complaint dataset would want to re-calibrate rather than inherit these numbers. Same reasoning as [#14](#percentile-ranks-scoped-to-the-crosswalk).

`is_branchless` (`offices_count < 50`) uses the same universe-calibrated logic: 50 separates pure-digital/card issuers (Ally at 1 office, Synchrony, AmEx, Capital One card arm) from even the smallest branch-network community bank in the set.

Financial ratios (`capital_ratio`, `deposits_to_assets_ratio`) are computed unit-free — numerator and denominator are both in FDIC's thousands-USD unit, so they cancel. `total_assets_usd` multiplies by 1,000 for human readability in display contexts but the ratio calculations use the raw thousands. Small detail, but if the underlying unit ever changes, the ratios stay correct without a code change.

---

## Semantic, Production & Limits

### MetricFlow: metrics as code

**`models/marts/_metrics.yml` defines a semantic model on `fct_complaints` and 8 metrics** (`complaint_count`, `timely_response_rate`, `dispute_rate`, `narrative_rate`, `avg_days_to_company`, and their component counts) — metric logic versioned in git, not buried in BI tool UI.

Rationale: without a semantic layer, each analyst or dashboard independently writes the same aggregation logic — and independently makes the same mistakes. `dispute_rate` is the concrete example (see [#8](#consumer-disputed-era-flag-is_dispute_era) for the 4.3% vs. 19.3% gap the filter prevents). MetricFlow encodes the `is_dispute_era` filter once in the metric definition; every consumer inherits it and can't accidentally get the un-gated number.

The closest analogy is LookML. "Semantic layer / metrics framework" appears explicitly in Senior AE job descriptions; this is the dbt-native answer to that requirement.

---

### Incremental design for `fct_complaints`

**`fct_complaints` is materialized as a `table` against this frozen source; on a live CFPB feed, the correct design is incremental:**

```sql
{{ config(materialized='incremental', unique_key='complaint_id', on_schema_change='append_new_columns') }}
...
{% if is_incremental() %}
  and date_received > (select max(date_received) from {{ this }}) - interval 7 day
{% endif %}
```

`unique_key = 'complaint_id'` compiles to a `MERGE`, so amended CFPB records overwrite rather than duplicate. `on_schema_change='append_new_columns'` handles CFPB's occasional field additions (tags in 2016, narrative in 2015) without breaking existing rows. The 7-day lookback catches late-arriving complaints: CFPB occasionally routes records with `date_received` several days behind the release date. Seven days is the smallest window that covers observed lag; `dbt run --full-refresh --select fct_complaints` handles backfills or schema changes the append strategy can't.

Production config keys (`unique_key`, `on_schema_change`) are set on the model; only the `{% if is_incremental() %}` filter block is omitted, since there is no delta to detect against a frozen source.

---

### Testing strategy

**Generic tests for column-level invariants, singular SQL tests for structural guarantees that generic tests can't express.**

**Generic tests** guard PK uniqueness and not_null at every layer (`complaint_id` is tested at source, staging, intermediate, and marts); `accepted_values` on categorical enums (`state`, `category`, `product`, `submitted_via`); and a FK relationship between `fct_complaints.company_sk` and `dim_company.company_sk`. Two `accepted_values` tests use a `config: where:` clause to scope them — e.g., `category` is only validated for crosswalked rows, since null is the correct value for the 26% of complaints that don't match the seed.

**Singular tests** guard invariants that require domain knowledge or cross-model reasoning:

- `assert_int_complaints_no_fanout` — compares row counts between `stg_cfpb_complaints` and `int_complaints_with_company`. The left join on `raw_company_name` can only fan out if the crosswalk seed contains duplicate keys; this test catches that immediately.
- `assert_crosswalk_coverage` — fails if the crosswalk match rate drops below 74%. Encodes the empirical coverage floor as a regression guard; any seed change that degrades coverage breaks loudly.
- `assert_complaint_dates_ordered` — verifies `date_sent_to_company >= date_received`, scoped to post-2014-04-26 to skip a known intake-system artifact (~7,000 pre-2015 rows with -1 day offsets).
- `assert_dispute_era_nulls` — warns when rows with `is_dispute_era = false` have non-null `consumer_disputed`. `severity: warn` rather than error because the 2017 transition year has ~30% fill — a signal, not a hard invariant.
- `assert_mart_bank_rates_in_range` — verifies `timely_response_rate` and `dispute_rate` are both in [0, 1]. A value outside that range means a broken COUNTIF/COUNT ratio; the test returns the offending row for diagnosis.

`where:` clauses scope tests to the rows where the constraint applies: `total_assets` in `stg_fdic_banks` is only asserted not_null for institutions with a `top_holder` (4 of 4,756 records have both fields null — documented edge cases). `bank_size_bucket` and `total_assets_usd` in `dim_bank` are only asserted for FDIC-enriched rows (Barclays has a documented null enrichment gap).

---

### ZIP privacy codes — staging bug

**Known bug: CFPB's intentional 3-digit privacy ZIPs are incorrectly expanded to 5 digits in staging.**

CFPB publishes 3-digit ZIP codes for a specific subset of complaints: those where the consumer consented to narrative publication but lives in a ZCTA with fewer than 20,000 people. The current staging cleanup — which converts float-formatted strings (`'30349.0'`) to zero-padded 5-digit strings via `SAFE_CAST` + `LPAD` — incorrectly expands these intentional 3-digit ZIPs into fabricated 5-digit values. `017` (raw: `17.0`) becomes `00017`.

Impact: affected rows pass `zip_code_is_valid = TRUE` (numeric, 5 digits) and will silently corrupt geographic analysis. The subset is small — only complaints with narrative consent in low-population ZCTAs. The fix — detect integer values 1–999 before applying `LPAD` and preserve as 3-digit — is deferred until a geographic analysis layer is built.
