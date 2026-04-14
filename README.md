# dbt-cfpb-complaints

A dbt project modeling the [CFPB Consumer Complaint Database](https://www.consumerfinance.gov/data-research/consumer-complaints/) — a public dataset of ~3.5M consumer complaints against financial institutions.

**Status**: In development.

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

_To be filled in as the project develops._

## Live Dashboard

_Coming soon — Looker Studio dashboard connected to the marts layer._
