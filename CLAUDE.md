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

## Running Queries

Claude can run queries directly via the `bq` CLI using service account impersonation (no JSON key needed). Auth is via `gcloud auth application-default login` (user's Google identity) impersonating the `dbt-local` service account.

**Save to file when:** the query shapes a build decision, documents a finding, or will be re-run (validation queries). File goes in the appropriate `exploration/` subfolder (`cfpb/`, `fdic/`, `validation/`, etc.) — not necessarily at the top level. One statement per file; `bq` runs one statement per invocation.

**Run inline when:** it's a transient debug query — triggered by a specific failure, not worth keeping once resolved (row counts, coverage checks, "does this value exist?" sanity checks).

**Inline query protocol:** Before submitting an inline `bq` command for approval, describe in one sentence what the query does and what you expect to learn from it. This lets the user understand what they're approving without reading the SQL.

**File-based workflow:**
1. Write SQL to the appropriate `exploration/` subfolder
2. Show the file path and contents for review
3. Run via `bq` — permission prompt is the approval gate

**Standard invocations:**
```bash
# From file (single statement)
bq --project_id=dbt-portfolio-493318 --quiet query --use_legacy_sql=false --format=pretty < exploration/path/to/query.sql

# Inline
bq --project_id=dbt-portfolio-493318 --quiet query --use_legacy_sql=false --format=pretty 'SELECT ...'
```

Impersonation is set via `gcloud config set auth/impersonate_service_account` — no per-command flag needed. Add `--max_rows=N` for large results.

