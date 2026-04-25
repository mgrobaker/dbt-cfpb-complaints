# Setup

[← Back to README](README.md)

Getting this project running locally.

The project I built runs on a private BigQuery project, so the warehouse itself isn't externally accessible. To replicate end-to-end, provision your own BigQuery project, load the CFPB public dataset, and follow the steps below for credentials and configuration.

## Prerequisites

- Python 3.10+ and [`uv`](https://github.com/astral-sh/uv)
- A Google Cloud project with BigQuery enabled
- Billing enabled on the GCP project (BigQuery free tier is generous — 10 GB storage + 1 TB queries/month)
- `git`

## 1. Clone

```bash
git clone https://github.com/mgrobaker/dbt-cfpb-complaints.git
cd dbt-cfpb-complaints
```

## 2. Create a GCP service account and key

In the GCP console:

1. **IAM & Admin → Service Accounts → Create service account**
2. Grant roles on your BigQuery project:
   - `roles/bigquery.dataEditor` — read + create/update tables
   - `roles/bigquery.jobUser` — run queries (billing)
3. **Keys → Add key → Create new key → JSON**. Download the file.
4. Move the key to a location **outside this repo**. A dedicated folder under your home directory is recommended:
   - Linux/macOS: `~/.secrets/<project>/<key>.json`
   - Windows: `%USERPROFILE%\.gcp\<key>.json`

   `chmod 600` the file (Linux/macOS) so only you can read it.

## 3. Configure environment variables

Copy [`.env.example`](.env.example) and fill in your values:

```bash
cp .env.example .env
# Edit .env: absolute path to key file, GCP project ID, BigQuery location (e.g. US).
```

Load `.env` into your shell (pick one):

```bash
# Option A: direnv (recommended — auto-loads on cd into repo)
direnv allow

# Option B: one-off per shell
set -a; source .env; set +a
```

## 4. Install dbt

Dependencies are pinned via `pyproject.toml` + `uv.lock` for reproducible builds.

```bash
uv sync
```

This creates `.venv/` and installs the exact versions from `uv.lock`. Run dbt via `uv run`:

```bash
uv run dbt --version
```

(Or activate the venv with `source .venv/bin/activate` if you prefer.)

## 5. dbt profile

This repo commits a [`profiles.yml`](profiles.yml) in the project root that reads credentials from environment variables — no secrets in the file. dbt discovers it automatically when run from the repo root.

Required env vars (set via `.env`):
- `GOOGLE_APPLICATION_CREDENTIALS` — absolute path to your service account JSON
- `GCP_PROJECT_ID` — your BigQuery project ID
- `BQ_LOCATION` — BigQuery region (e.g. `US`)

## 6. Verify connection

```bash
uv run dbt debug
```

This validates: Python version, dbt install, profile resolution, BigQuery credentials, and connectivity. If all checks pass, you're ready to build.

## Secrets policy

- **Never commit** service account keys or `.env` files. `.gitignore` excludes these.
- The committed `profiles.yml` contains only `env_var(...)` references — no secrets.
- The key file lives **outside the repo**, referenced only via `GOOGLE_APPLICATION_CREDENTIALS`.
- If a key is ever committed by accident, **rotate it immediately** in the GCP console (delete the key, create a new one). Git history rewrites don't help once a key has been pushed.
