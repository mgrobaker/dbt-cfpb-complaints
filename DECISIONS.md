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

This source is frozen at 2023-03-25, so the snapshot establishes initial state only; no future changes will be detected. The three known historical rebrands are encoded in the crosswalk's `parent_as_of` column instead, which records the effective date of each entity change:

- SunTrust → Truist: 2019-12-01
- BB&T → Truist: 2019-12-01
- Alliance Data → Bread Financial: 2021-02-01

Query `stg_company_crosswalk WHERE parent_as_of IS NOT NULL` to surface these. The snapshot demonstrates the Kimball SCD2 pattern and correct dbt configuration; the `parent_as_of` column demonstrates how effective dates would be tracked in the source.

One known FDIC enrichment gap: pre-merger SunTrust and BB&T records carry historically-correct `fdic_top_holder` values (`SUNTRUST BANKS INC`, `BB&T CORP`), but the current FDIC snapshot is active-institutions only — those entities no longer appear. Post-2019 Truist complaints map to `TRUIST FINANCIAL CORP`, which does resolve. In production with a historical FDIC feed, pre-merger records would enrich fully.

---

## days_to_company: routing speed, not resolution time

The derived column is named `days_to_company`, not `days_to_resolution`.

Rationale: the metric measures `date_sent_to_company - date_received` — CFPB's internal forwarding speed, not how long it took the company to resolve the complaint. "Resolution" implies the complaint is closed; forwarding just means CFPB routed it. Naming it accurately prevents downstream analysts from misreading it as a company SLA metric. Negatives (7,036 pre-2015 rows, -1 day, intake-system clock artifact) are clamped to 0 via `GREATEST(..., 0)`.

---
