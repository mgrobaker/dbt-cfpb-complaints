# Exploration Queries

Documents data quality investigations that shaped modeling decisions. Each entry records what was found and the downstream action it drove.

---

## cfpb/companies/

### quality.sql

- **Outcome**: Long-tail distribution — most of 6,694 company strings have <20 complaints (noise/typos). Alphabetical dump confirms variant clusters (same entity, different casing/punctuation/suffix).
  - **Action**: → crosswalk seed strategy decided (hand-map top companies, not fuzzy join).

- **Outcome**: Response fields (`company_response_to_consumer`, `company_public_response`, `consumer_consent_provided`) — values and null rates confirmed. `company_response_to_consumer`: 4 nulls only. `company_public_response`: 56% null; verbose "has responded" label (1.3M rows) is a duplicate of the shorter "chooses not to provide" label. `consumer_consent_provided`: 25% null.
  - **Action**: → null mappings and label consolidation in `staging/stg_cfpb_complaints.sql`. Decisions in `staging/_models.yml` column descriptions.

- **Outcome**: Timely response rate by top companies (≥1,000 complaints, 2012–2022): all >95% timely, zero nulls. Field is clean and fully populated — no staging transformation needed.

---

### volume.sql

- **Outcome**: Top 50 companies by raw name: Equifax + TransUnion + Experian = 47% of all complaints; none have FDIC records. Mixed casing and punctuation confirmed. Rebrands visible in date ranges (SunTrust→Truist 2019, Ditech exits 2020, Alliance Data→Bread Financial ~2021).
  - **Action**: → confirmed credit bureaus out of scope for FDIC join. `company_name_normalized` expression in `stg_cfpb_complaints`.

- **Outcome**: Top 30 companies by complaint volume (all types, 2012–2022) reach **74% cumulative coverage**. Credit bureaus are #1–3 (45.35% combined). Mix includes banks, mortgage servicers, debt collectors, student loan servicers, fintechs, and one credit union (Navy Federal). All 30 are in `seeds/company_crosswalk.csv`; coverage test set at 74%.
  - **Action**: → crosswalk seed covers all top-30 institutions. See `assert_crosswalk_coverage.sql`.

---

## cfpb/profile/

### anomalies.sql

- **Outcome**: Date ordering violations: 7,036 rows (~0.2%) where `date_sent_to_company < date_received`. All exactly 1 day early, all 2012-01-22 to 2014-04-26. Proportionally spread across all major filers — systematic intake-system artifact, not a data error.
  - **Action**: → `tests/assert_complaint_dates_ordered.sql` at `severity: warn`.

- **Outcome**: Zip code validity — raw `zip_code` is float-formatted (`30349.0`) — BigQuery CSV import artifact. After staging cleanup (`SAFE_CAST` + `LPAD` + trailing `-` strip): vast majority valid 5-digit. 48 complaints (45 distinct strings) genuinely corrupted (mixed punctuation, embedded dashes). No masked `XXXXX` values. Known limitation: intentional 3-digit privacy ZIPs are incorrectly expanded — see `DECISIONS.md`.
  - **Action**: → `zip_code_is_valid` flag in `stg_cfpb_complaints`.

---

### tags.sql

- **Outcome**: 3 distinct non-null values: `'Servicemember'` (216,614), `'Older American'` (133,725), `'Older American, Servicemember'` (31,874). Combined tag is always Older American–first. `LIKE '%Servicemember%'` and `LIKE '%Older American%'` both correctly parse all 3 values. Coverage floor: CFPB added tags in Release 11, February 2016 — pre-2016 complaints are structurally null, not missing data.
  - **Action**: → `tags_is_servicemember` and `tags_is_older_american` added to `stg_cfpb_complaints`. `tags` raw column preserved alongside flags.

---

### geographic.sql

- **Outcome**: 63 distinct state values, all legitimate. One long-form outlier: "UNITED STATES MINOR OUTLYING ISLANDS" (305 rows). 41,114 null rows (1.2%). All other values are valid 2-char USPS codes (50 states + DC, territories, APO codes, freely associated states).
  - **Action**: → state CASE expression in `stg_cfpb_complaints` (NULL → `'not-provided'`, long-form → `'UM'`). `accepted_values` test at `severity: error`.

---

### overview.sql

- **Outcome**: 3.46M rows, 2011-12-01 to 2023-03-23. 6,694 distinct companies. Key null rates: `tags` 88.9%, `consumer_disputed` 77.8%, `subissue` 20.2%, `subproduct` 6.8%.
  - **Action**: → column descriptions in `staging/_models.yml`.

| Column | Null % | Distinct | Notes |
|---|---|---|---|
| `complaint_id` | 0% | — | Natural PK |
| `product` | 0% | 18 | |
| `subproduct` | 6.8% | 76 | |
| `issue` | 0% | 165 | |
| `subissue` | 20.2% | 221 | |
| `company_name` | 0% | 6,694 | |
| `state` | 1.2% | 63 | Remapped in staging |
| `tags` | 88.9% | 3 | Servicemember / Older American / both |
| `company_public_response` | 55.6% | 11 | |
| `consumer_disputed` | 77.8% | 2 | Policy change ~2017 |
| `has_narrative` | ~64% false | 2 | Opt-in |

---

### products.sql

- **Outcome**: Raw product taxonomy: 8 legacy product categories that CFPB renamed over time. Debt collection subproduct labels renamed across eras (e.g., "Credit card" → "Credit card debt").
  - **Action**: → `product_normalized` and `subproduct_normalized` in `stg_cfpb_complaints`.

- **Outcome**: Product × subproduct cross-tab (95 rows): all legacy debt collection renames confirmed handled in `seeds/subproduct_mapping.csv`. `"I do not know"` subproduct is a legitimate consumer-selected value. One junk row (`Credit reporting` × `Conventional home mortgage`, 1 complaint) — not worth handling.
  - **Action**: — (seeds already complete; no staging changes needed)

---

### temporal.sql

- **Outcome**: 2011 stub, 2023 partial. `consumer_disputed` 100% fill 2012–2016, drops to 0% by 2018 (CFPB policy change mid-2017). `has_narrative` 0% before mid-2015. 2020 +60% YoY (COVID). 2022 is peak year (800K).
  - **Action**: → `has_full_year_data` flag in `stg_cfpb_complaints` (drops 2011 + 2023 from trend analysis). Caveats in `staging/_models.yml`.

| Year | Complaints | Distinct Cos | Disputed Fill | Narrative Rate | Public Resp Rate |
|---|---|---|---|---|---|
| 2011 | 2,536 | 76 | 100% | 0% | 0% |
| 2012 | 72,372 | 461 | 100% | 0% | ~0% |
| 2013 | 108,215 | 1,428 | 100% | 0% | ~0% |
| 2014 | 153,029 | 2,217 | 100% | 0% | ~0% |
| 2015 | 168,464 | 2,928 | 100% | 32.5% | 36.6% |
| 2016 | 191,442 | 3,027 | 100% | 40.6% | 52.0% |
| 2017 | 242,890 | 3,278 | 29.8% | 47.4% | 48.1% |
| 2018 | 257,234 | 3,264 | 0% | 46.0% | 50.4% |
| 2019 | 277,311 | 3,144 | 0% | 45.0% | 51.9% |
| 2020 | 444,315 | 3,235 | 0% | 39.2% | 56.9% |
| 2021 | 496,007 | 3,374 | 0% | 41.0% | 40.2% |
| 2022 | 800,416 | 3,298 | 0% | 42.1% | 57.3% |
| 2023 | 244,675 | 1,926 | 0% | 16.6% | 30.3% |

- **Outcome**: Resolution time by era. Zero-day rate dominates and grows: pre-2015 33% (p50=1d), 2015–2019 75% (p50=0), 2020+ 92% (p50=0, p90=0). Negatives (-1 day, 7,036 rows) are pre-2015 only — intake-system artifact, no negative rows in 2015+.
  - **Action**: → `days_to_company` in `fct_complaints` (measures CFPB routing speed, not company resolution time). Clamp negatives with `GREATEST(..., 0)`.

---

## cfpb/setup/

### materialize.sql

*(One-time setup — not re-runnable against this frozen dataset.)*

- **Outcome**: Raw table materialized from `bigquery-public-data.cfpb_complaints.complaint_database`. Dropped `consumer_complaint_narrative`, kept `has_narrative` boolean. 2.31 GB → 768 MB.

---

### schemas.sql

- **Outcome**: Column lists for both raw tables: 18 CFPB columns, 95 FDIC columns.
  - **Action**: → column reference folded into `models/staging/_sources.yml` (published to hosted dbt docs).

---

## fdic/

### exploration.sql

- **Outcome**: 5a/5b: `top_holder` confirmed as right join grain (~94% of top-50-by-assets institutions have `top_holder` populated). Top holders by assets: JPMorgan $3.4T, BofA $2.5T, Wells Fargo $1.7T, Citi $1.7T, US Bancorp $582B, PNC $534B, Truist $532B, Capital One $515B. Normalization quirks confirmed: `&` without spaces, `BCORP` vs `BANCORP`, trailing `THE`, abbreviated words. Two nulls in top 50: First Republic Bank (failed Mar 2023), Zions Bancorporation.
  - **Action**: → `top_holder` as crosswalk join key. Normalization → `int_fdic_banks_normalized`. See `DECISIONS.md` § FDIC join grain.

- **Outcome**: 5e (suffix-strip match) — 7/12 bank entries matched cleanly (Ally, AmEx, BofA, Capital One, Citi, Discover, JPMorgan). 5 fixes applied to `seeds/company_crosswalk.csv`: Wells Fargo (`WELLS FARGO&COMPANY`, not `WELLS FARGO & CO`); USAA (`UNITED SERVICES AUTOMOBILE ASSN`); Santander (`BANCO SANTANDER SA`); SunTrust + BB&T historical entries (pre-merger entities not in active FDIC snapshot; `TRUIST FINANCIAL CORP` row added for post-2019 complaints).
  - **Action**: → `seeds/company_crosswalk.csv` updated. Pre-merger rows correct for era but won't join to current FDIC snapshot — see `DECISIONS.md`.

---

### phase3_prep.sql

1. **Bank coverage summary** — bank = 21.4% of complaints (739K), 98% FDIC fill rate (725K enrichable). Credit bureau 47.6%. Uncrosswalked slice: uncrosswalked banks 3.9%, debt collectors 3.1%, mortgage servicers 1.7%, auto lenders 0.8%, fintechs 0.8%, long tail 11.5%.
   - **Action**: → Phase 3 framed as bank-segment analysis, not full-dataset enrichment.

2. **FDIC normalization preview** — all normalization rules produce clean values. `total_assets` is in thousands USD.
   - **Action**: → `int_fdic_banks_normalized` transformation rules confirmed.

3. **Match rate** — 15/15 non-null `fdic_top_holder` values match raw FDIC `top_holder`. Join key is raw `top_holder`, not normalized. One gap: Barclays `fdic_top_holder = NULL`.
   - **Action**: → `dim_bank` join key confirmed as raw `top_holder`.

4. **Asset tier + CFPB supervision + ROA** — all 15 banks CFPB-supervised (flag won't differentiate within this universe). Two size tiers: 9 mega (>$250B), 6 large ($50B–$250B). ROA varies ~10×: USAA 13.1%, AmEx 5.0%, Capital One 2.8%, JPMorgan 0.8%.
   - **Action**: → `dim_bank` columns: `total_assets_usd` (×1000), `bank_size_bucket`, `is_supervised_cfpb`, `avg_roa`, `charter_count`.
