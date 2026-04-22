# dbt-cfpb-complaints

A dbt project modeling the [CFPB Consumer Complaint Database](https://www.consumerfinance.gov/data-research/consumer-complaints/) — a public dataset of ~3.5M consumer complaints against financial institutions.

**Status**: In development.

> **Note**: This project runs on a private GCP project. The code is public for portfolio review; the underlying warehouse and data are not accessible to others. To replicate, you'd need your own BigQuery project and to load the CFPB dataset yourself.

## Stack

- **Warehouse**: BigQuery (native public dataset: `bigquery-public-data.cfpb_complaints`)
- **Transformation**: dbt
- **Destination**: Migration to Snowflake planned for v1.5

## Goals

- Dimensional model over a messy real-world regulatory dataset
- Staging → intermediate → marts layering
- Full test coverage and documentation
- Company-name normalization (same company appears under many string variants)
- Join with FDIC institutions data for bank metadata enrichment

## Setup

See [SETUP.md](./SETUP.md) for local installation and credentials.

## Structure

```
models/
  staging/        # stg_* — source-faithful cleaning, type casting, light derivations
  intermediate/   # int_* — multi-source joins and business logic (Phase 3+)
  marts/          # dim_* and fct_* — dimensional model for analytics
exploration/
  cfpb/           # Investigation queries: profile/, companies/, setup/
  fdic/           # Investigation queries by source
  README.md       # Query tracker: status and outcomes for each file
docs/
  schema.md       # Authoritative column reference for raw tables
seeds/            # company_crosswalk.csv (Phase 2) — hand-mapped CFPB→FDIC names
tests/            # Singular tests (assert_*)
```

**Model naming**: `stg_<source>_<entity>`, `int_<description>`, `dim_<entity>`, `fct_<entity>`.

## Live Dashboard

_Coming soon — Data Studio dashboard connected to the marts layer._
