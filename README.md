# dbt-cfpb-complaints

This is a dbt project on BigQuery that models the CFPB Consumer Complaint Database — about 3.5 million consumer complaints filed against U.S. financial institutions between 2011 and 2023 — and joins it to FDIC data on the banks those complaints are filed against.

## The CFPB dataset

The CFPB Consumer Complaint Database is a public regulatory feed of consumer complaints against financial institutions, published since 2011. I picked it because it has the problems real analytics engineering work has to deal with:

- Company names are free text — 6,694 distinct variants for what's really a few hundred institutions. One bank shows up under six different spellings.
- A key field, `consumer_disputed`, was discontinued in April 2017. Any metric that uses it silently breaks if you don't gate by date.
- The first and last years are partial. A naive year-over-year comparison would show 2011 collapsing and 2023 looking anomalous.
- The entities being complained about are a mix of banks, credit bureaus, debt collectors, and fintechs that don't fit a single reference table.

## Why I added FDIC data

Most real analytics work isn't modeling a single clean table. It's resolving entities across systems, applying business logic consistently, and keeping that logic in code where it can be reviewed and tested — not re-derived in every analyst's notebook. That's the kind of work dbt is built for.

I looked at what public data could meaningfully extend the CFPB dataset and chose the FDIC's institution data: asset size, branch counts, holding-company structure, financial ratios. There was no shared key. CFPB names companies as free text; FDIC has its own institution and holding-company identifiers. Joining the two required building a crosswalk by hand — 50 rows covering ~80% of complaint volume — and resolving complaints to the parent bank holding company before joining FDIC at the right grain.

That's the kind of business logic that should live in dbt, not in individual analysts' workflows. Once it's in the project, anyone querying the marts gets the same entity resolution, the same era gates on dispute rates, the same bank-size buckets — without having to re-derive any of it.

## Questions this data can answer

A few examples of what the modeled output is built to support:

- Which banks generate disproportionate complaint volume relative to their size? (The marts expose complaints per $B in assets, so a regional bank and a top-4 bank are actually comparable.)
- Do branchless banks resolve complaints faster or slower than traditional banks?
- Which product categories drove complaint surges, and was the volume concentrated in specific institutions?
- How did the CFPB's 2017 decision to stop collecting dispute data change what we can measure about resolution quality?

The dashboard linked at the bottom shows a few of these worked through; the marts are designed to support analysts asking their own.

## Architecture

Standard layered build: `raw` (one-time materialization with the narrative column dropped to control scan cost) → `staging` (typed, trimmed, normalized, with provenance flags) → `intermediate` (company crosswalk join + FDIC aggregation) → `marts` (Kimball-style: [`dim_date`](models/marts/dim_date.sql), [`dim_company`](models/marts/dim_company.sql), [`dim_bank`](models/marts/dim_bank.sql), [`fct_complaints`](models/marts/fct_complaints.sql), [`mart_bank_complaint_metrics`](models/marts/mart_bank_complaint_metrics.sql), [`mart_bank_complaints_monthly`](models/marts/mart_bank_complaints_monthly.sql)) → `semantic` (MetricFlow [`_metrics.yml`](models/marts/_metrics.yml)).

The marts split between an executive bank-grain mart (`mart_bank_complaint_metrics` — one row per bank, percentile ranks, the headline `complaints_per_billion_assets`) and a time-grained companion (`mart_bank_complaints_monthly` — bank × month × product_category, ~17.5K rows). The monthly mart stores measure components, not rates: rates are derived at consumption time so rollups across grains stay correct (averaging stored monthly rates produces wrong overall rates — Simpson's paradox). Era-gated denominators (`complaint_count_dispute_era`, `complaint_count_narrative_era`) are stored alongside their numerators.

A [`company_renames`](snapshots/company_renames.sql) snapshot tracks SCD2 history on the crosswalk for known rebrands.

FDIC reference data ([`raw.fdic_active_banks_lean`](models/staging/_sources.yml), 4,756 institutions) joins at the top-holder grain into `dim_bank`, so you can compare banks of different sizes fairly — complaints per billion in assets, not raw counts.

[Hosted docs — lineage graph, column descriptions, test coverage](https://mgrobaker.github.io/dbt-cfpb-complaints/)

## What to look at first

If you have ten minutes, in this order:

- [**`DECISIONS.md`**](DECISIONS.md) — architectural decisions with rationale: tradeoffs considered, what was rejected, and why.
- [**`fct_complaints.sql`**](models/marts/fct_complaints.sql) **+** [**`dim_company.sql`**](models/marts/dim_company.sql) — grain decisions, derived flags (`is_dispute_era`, `has_full_year_data`), and the company crosswalk join.
- [**`dim_bank.sql`**](models/marts/dim_bank.sql) **+** [**`mart_bank_complaint_metrics.sql`**](models/marts/mart_bank_complaint_metrics.sql) — the FDIC enrichment layer with asset tiers, ROA, branch footprint, and a scale-normalized metrics mart.
- [**`mart_bank_complaints_monthly.sql`**](models/marts/mart_bank_complaints_monthly.sql) — time-series companion at bank × month × product_category grain. Stores measure components (counts and era-gated denominators) so any rollup divides components rather than averaging precomputed rates.
- [**`_metrics.yml`**](models/marts/_metrics.yml) — MetricFlow definitions: era-filtered `dispute_rate` and `narrative_rate` (null — not misleadingly zero — for years the source field wasn't collected), `complaints_per_billion_assets` as a derived metric joining the complaints and banks semantic models, and MoM/YoY change metrics on `complaint_count` exercising MetricFlow's `metric_time` offset windows.
- [**`tests/`**](tests/) — singular tests, especially [`assert_int_complaints_no_fanout.sql`](tests/assert_int_complaints_no_fanout.sql) and [`assert_crosswalk_coverage.sql`](tests/assert_crosswalk_coverage.sql). They catch the bugs `not_null` and `unique` won't: fan-out in the crosswalk join, gaps in crosswalk coverage.
- [**`seeds/company_crosswalk.csv`**](seeds/company_crosswalk.csv) — 50 rows of explicit, auditable mappings covering ~80% of complaint volume. Three SCD2 rebrands (SunTrust→Truist, BB&T→Truist, BBVA→PNC). I chose a manual seed over fuzzy matching deliberately; for a dataset tied to regulatory complaints, I'd rather be able to explain every mapping than trust a similarity score.
- [**`snapshots/company_renames.sql`**](snapshots/company_renames.sql) — SCD2 with `parent_as_of` for two complementary mechanisms: known historical rebrands captured in the seed, unknown future rebrands handled automatically by the snapshot.

Full rationale for every design choice is in [`DECISIONS.md`](DECISIONS.md) (20 entries).

## Running the project

Requires Python 3.11+, [uv](https://github.com/astral-sh/uv), and a BigQuery project with credentials configured. See [`SETUP.md`](SETUP.md) for the full setup.

```bash
uv sync
uv run dbt deps
uv run dbt seed
uv run dbt snapshot
uv run dbt build
```

## Scope — what's out

The CFPB data is loaded once as a static snapshot. That's the right call for a portfolio project but not how this would run in production. In a real deployment the fact table would be incremental on complaint date with a lookback window for late-arriving updates, the FDIC reference would refresh quarterly against the Call Report release cycle, and the whole pipeline would run on a scheduler (Airflow, Dagster, or dbt Cloud) with freshness SLAs on the sources. The models are written to support that — `fct_complaints` has a natural partition key and the crosswalk join is idempotent — but the incremental config and orchestration aren't wired up here.

## Dashboard

[CFPB Complaint Data — Data Studio](https://datastudio.google.com/reporting/7a6d183e-854a-46ba-8507-f375c50d71c8)
