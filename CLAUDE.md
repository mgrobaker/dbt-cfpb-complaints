# dbt-cfpb-complaints — AI Context

Public dbt project modeling the CFPB Consumer Complaint Database on BigQuery. See `README.md` for project overview.

## Credentials

Service account keys live in `~/.secrets/dbt-portfolio/` (two keys: one for dbt automation, one for interactive/CLI/DBCode use).

Exact paths, GCP project ID, and BigQuery quota settings are documented in the private planning doc:
`$PRIVATE_NOTES_DIR/README.md` (Session Handoff section).

Global convention for secrets layout: `~/.claude/claude-technical.md` § Secrets.

## Warehouse

- BigQuery project: see planning doc
- Raw datasets: `raw.cfpb_complaints` (768 MB; narrative dropped, `has_narrative` flag kept), `raw.fdic_active_banks`, `raw.fdic_active_banks_lean`

## Key Docs

- `docs/schema.md` — **authoritative column reference** for `raw.cfpb_complaints` (18 cols) and `raw.fdic_active_banks_lean` (95 cols). Check here before writing queries.
- `exploration/README.md` — tracker for all exploration queries: status, outcomes, and links to downstream actions. Check before writing new exploration SQL.
- `exploration/cfpb/` and `exploration/fdic/` — investigation queries by source. Re-runnable except `cfpb/setup/materialize.sql` (one-time).
- Private planning mirror: `$PRIVATE_NOTES_DIR` (see `.env`). Contains `README.md` (strategy + session handoff), `exploration-findings.md` (DQ findings, interview talking points), `warehouse-comparison.md`. Read when you need strategy context; don't write dbt code there.

## Tooling

- Run dbt as `uv run dbt <command>` (uv-managed venv; `pyproject.toml` + `uv.lock` in repo root)
- Example: `uv run dbt run`, `uv run dbt test`, `uv run dbt docs generate`

## Query Etiquette (BigQuery)

- Daily scan quota is capped (~30 GB) — user will raise temporarily when needed.
- Billed on **bytes scanned**, not compute time. Prefer a single scan with conditional aggregation over multiple UNION ALL passes.
- Metadata queries (`INFORMATION_SCHEMA`, `bq show`) are free.
- **Write SQL to files in `exploration/`; don't run queries via Python/API.** User runs queries interactively in DBCode and pastes results back.

