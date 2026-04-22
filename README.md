# dbt-cfpb-complaints

A production-grade dbt project modeling the CFPB Consumer Complaint Database (3.5M rows) on BigQuery. Built to demonstrate the skills that distinguish Senior Analytics Engineering from junior dbt work: dimensional modeling against a messy real-world source, compliance-grade testing discipline, and a semantic layer that prevents metric drift. The CFPB dataset was chosen deliberately — it's regulator-published, large enough to matter, and has the kind of entity-resolution and partial-period problems that real warehouses inherit.

> The project runs on a private BigQuery project. Code is public for portfolio review; the warehouse is not accessible externally. To replicate: provision your own BigQuery project, load the CFPB public dataset, and configure credentials per the setup steps below.

## Architecture

Standard layered build: `raw` (one-time materialization with the narrative column dropped to control scan cost) → `staging` (typed, trimmed, normalized, with provenance flags) → `intermediate` (company crosswalk join) → `marts` (Kimball-style: `dim_date`, `dim_company`, `fct_complaints`) → `semantic` (MetricFlow `_metrics.yml`). A `company_renames` snapshot tracks SCD2 history on the crosswalk for known rebrands. FDIC reference data joins into `dim_company` at the parent-holder grain.

![Lineage graph](https://mgrobaker.github.io/dbt-cfpb-complaints/#!/overview)

[Hosted docs — lineage graph, column descriptions, test coverage](https://mgrobaker.github.io/dbt-cfpb-complaints/)

## What to look at first

If you have ten minutes, in this order:

- **`DECISIONS.md`** — 14 architectural decisions with full rationale. The document to read if you want to know how I think.
- **`models/marts/fct_complaints.sql` + `dim_company.sql`** — grain decisions, derived flags (`is_dispute_era`, `has_full_year_data`), and the FDIC enrichment join.
- **`models/marts/_metrics.yml`** — MetricFlow metric definitions, including era-filtered `dispute_rate` and `narrative_rate` that can't silently compute against years where the source fields stopped being collected.
- **`tests/`** — singular tests, especially `assert_int_complaints_no_fanout.sql` and `assert_crosswalk_coverage.sql`. These catch the failure modes generic tests miss.
- **`seeds/company_crosswalk.csv`** — 41 rows of explicit, auditable mappings covering 74% of complaint volume. Chose this over fuzzy matching deliberately; rationale in `DECISIONS.md`.
- **`snapshots/company_renames.sql`** — SCD2 with `parent_as_of` for two complementary mechanisms: known-historical rebrands captured in the seed, unknown-future rebrands handled automatically by the snapshot.

## Dataset

The CFPB Consumer Complaint Database is a public regulatory feed of consumer complaints against financial institutions, published since 2011. It's a strong portfolio dataset because it has the data-quality issues real warehouses inherit: inconsistent company naming across 6,694 free-text variants, a key field (`consumer_disputed`) that the agency stopped collecting in April 2017, partial first/last years, and mixed entity types — banks, credit bureaus, debt collectors, fintechs — that resist a single reference table.

## Key decisions

Full rationale for each in `DECISIONS.md`:

- Narrative column dropped at raw materialization — 90% of bytes; kept as `has_narrative` flag.
- `is_dispute_era` gates `dispute_rate` in the semantic layer — the field is 78% null overall due to a 2017 policy change; un-gated, the metric is meaningless.
- Crosswalk seed (41 rows, manual) over fuzzy matching — auditability beats automation on compliance-adjacent data.
- FDIC join on `top_holder`, not `institution_name` — parent-corp grain matches CFPB naming; `institution_name` is one level down and fragments multi-charter holders.
- `has_full_year_data` flag preserves 2011/2023 partial years rather than silently filtering — analyst decides what to include, not staging.

## Running the project

Requires Python 3.11+, [uv](https://github.com/astral-sh/uv), and a BigQuery project with credentials configured.

```bash
uv sync
uv run dbt deps
uv run dbt seed
uv run dbt snapshot
uv run dbt build
```

See `SETUP.md` for GCP credentials and `profiles.yml` setup.

## Dashboard

[CFPB Complaint Data — Data Studio](https://datastudio.google.com/reporting/7a6d183e-854a-46ba-8507-f375c50d71c8)
