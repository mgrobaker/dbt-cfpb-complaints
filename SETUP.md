# Setup

Getting this project running locally.

## Prerequisites

- Python 3.10+ and [`uv`](https://github.com/astral-sh/uv) (or any virtualenv tool)
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
4. Move the key to a location **outside this repo**. A stable location under your home directory is recommended, e.g.:
   - Linux/macOS: `~/.config/gcloud/<project>-key.json` or a dedicated `~/.secrets/<project>/` folder
   - Windows: `%USERPROFILE%\.gcp\<project>-key.json`

   `chmod 600` the file (Linux/macOS) so only you can read it.

## 3. Configure environment variables

```bash
cp .env.example .env
# Edit .env and fill in the absolute path to your key file, project ID, and region.
```

Load `.env` into your shell (pick one):

```bash
# Option A: direnv
direnv allow

# Option B: one-off
set -a; source .env; set +a
```

Verify:

```bash
gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
bq ls --project_id="$GCP_PROJECT_ID"
```

## 4. Install dbt

```bash
uv venv
source .venv/bin/activate
uv pip install dbt-core dbt-bigquery
```

## 5. Configure dbt profile

_Profile details will be documented here once the dbt project is scaffolded. For now, see the dbt-bigquery [service-account-file auth docs](https://docs.getdbt.com/docs/core/connect-data-platform/bigquery-setup#service-account-file)._

## 6. Verify connection

```bash
dbt debug
```

## Secrets policy

- **Never commit** service account keys, `.env` files, or `profiles.yml` with credentials. `.gitignore` excludes these by default.
- The key file should live **outside the repo**. This repo will never reference its absolute path in committed code — only via the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.
- If a key is ever committed by accident, **rotate it immediately** in the GCP console (delete the key, create a new one) — revoking is the only remediation; git history rewrites don't help once a key has been pushed.
