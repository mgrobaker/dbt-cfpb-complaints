# Exploration Query Tracker

Status of each exploration query. Update as you run things.

**Status key**: `✓` done · `partial` some sub-queries run · `—` not yet run

---

## Current Priority

`int_complaints_with_company` is complete (Phase 2b item 10 ✅, 39 tests pass). Two exploration queries remain for docs and interview talking points — neither blocks any model work.

1. **`fdic/exploration.sql` 5c** — naive uppercase join baseline (DECISIONS.md talking point: "naive join hits X%; that's why the crosswalk exists")
2. **Narrative rate query** (`products.sql`) — `has_narrative` rate by product × year; worth running for MetricFlow/interview color

Queries without a downstream build decision are deprioritized. Exploration is scoped to questions that shape model decisions, not exhaustive coverage.

---

## cfpb/companies/

### quality.sql
**Status**: ✓

- **Outcome**: Long-tail distribution — most of 6,694 company strings have <20 complaints (noise/typos). Alphabetical dump confirms variant clusters (same entity, different casing/punctuation/suffix).
  - **Action**: → crosswalk seed strategy decided (hand-map top companies, not fuzzy join).

- **Outcome**: Response fields (`company_response_to_consumer`, `company_public_response`, `consumer_consent_provided`) — values and null rates confirmed. `company_response_to_consumer`: 4 nulls only. `company_public_response`: 56% null; verbose "has responded" label (1.3M rows) is a duplicate of the shorter "chooses not to provide" label. `consumer_consent_provided`: 25% null.
  - **Action**: → null mappings and label consolidation in `staging/stg_cfpb_complaints.sql`. Decisions documented in `staging/_models.yml` column descriptions.

- **Outcome**: Timely response rate by top companies (≥1,000 complaints, 2012–2022): all >95% timely, zero nulls. Field is clean and fully populated — no staging transformation needed; raw boolean usable as-is.

---

### volume.sql
**Status**: ✓

- **Outcome**: Top 50 companies by raw name: Equifax + TransUnion + Experian = 47% of all complaints; none have FDIC records. Mixed casing and punctuation confirmed. Rebrands visible in date ranges (SunTrust→Truist 2019, Ditech exits 2020, Alliance Data→Bread Financial ~2021).
  - **Action**: → confirmed credit bureaus out of scope for FDIC join. `company_name_normalized` expression in `staging/stg_cfpb_complaints.sql:31-34`

- **Outcome**: Top 30 companies by complaint volume (all types, 2012–2022) reach **74% cumulative coverage**. Credit bureaus are #1–3 (45.35% combined). Mix includes banks, mortgage servicers, debt collectors, student loan servicers, fintechs, and one credit union (Navy Federal). All 30 are in `seeds/company_crosswalk.csv`; coverage test set at 74%.
  - **Action**: → crosswalk seed covers all top-30 institutions. Query 3 in `volume.sql` updated to include all company types (bureau exclusion removed). See `assert_crosswalk_coverage.sql`.

---

## cfpb/profile/

### anomalies.sql
**Status**: ✓

- **Outcome**: Date ordering violations: 7,036 rows (~0.2%) where `date_sent_to_company < date_received`. All exactly 1 day early, all 2012-01-22 to 2014-04-26. Proportionally spread across all major filers — systematic intake-system artifact, not a data error.
  - **Action**: → `tests/assert_complaint_dates_ordered.sql` at `severity: warn`.

- **Outcome**: Zip code validity — raw zip_code is float-formatted (`30349.0`) — BigQuery CSV import artifact. After staging cleanup (`SAFE_CAST` + `LPAD` + trailing `-` strip): vast majority `valid_5digit`. 48 complaints (45 distinct zip strings) in 'other' — all genuinely corrupted (mixed punctuation, embedded dashes, etc.). No masked `XXXXX` values in this dataset. `zip_code_is_valid` flag added to `stg_cfpb_complaints.sql`; NULL zip → `false`.
  - **Action**: → `zip_code_is_valid` in `staging/stg_cfpb_complaints.sql` ✓ done.

---

### tags.sql
**Status**: ✓

- **Outcome**: 3 distinct non-null values confirmed: `'Servicemember'` (216,614), `'Older American'` (133,725), `'Older American, Servicemember'` (31,874). Combined tag is always Older American–first. Total tagged rows: ~382K (~11.1% of dataset). `LIKE '%Servicemember%'` and `LIKE '%Older American%'` both correctly parse all 3 values. Coverage floor: CFPB added tags in Release 11, February 2016 — pre-2016 complaints are structurally null, not missing data.
  - **Action**: → `tags_is_servicemember` and `tags_is_older_american` added to `staging/stg_cfpb_complaints.sql` ✓. `tags` raw column preserved alongside flags.

---

### geographic.sql
**Status**: ✓

- **Outcome**: 63 distinct state values, all legitimate. One long-form outlier: "UNITED STATES MINOR OUTLYING ISLANDS" (305 rows). 41,114 null rows (1.2%). All other values are valid 2-char USPS codes (50 states + DC, territories, APO codes, freely associated states).
  - **Action**: → state CASE expression `staging/stg_cfpb_complaints.sql:35-40` (NULL → `'not-provided'`, long-form → `'UM'`, safety catch for future edge cases). `accepted_values` test wired at explicit `severity: error` — values list confirmed against actual data. `staging/_models.yml`

---

### overview.sql
**Status**: ✓

- **Outcome**: 3.46M rows, 2011-12-01 to 2023-03-23. 6,694 distinct companies. Key null rates: `tags` 88.9%, `consumer_disputed` 77.8%, `subissue` 20.2%, `subproduct` 6.8%. 20-row sample confirmed data shape and casing mess.
  - **Action**: → Column descriptions in `staging/_models.yml`

| Column | Null % | Distinct | Notes |
|---|---|---|---|
| `complaint_id` | 0% | — | Natural PK |
| `product` | 0% | 18 | See accepted_values caveat in yml |
| `subproduct` | 6.8% | 76 | |
| `issue` | 0% | 165 | |
| `subissue` | 20.2% | 221 | |
| `company_name` | 0% | 6,694 | See company name section |
| `state` | 1.2% | 63 | Remapped in staging — see yml |
| `tags` | 88.9% | 3 | Servicemember / Older American / both |
| `company_public_response` | 55.6% | 11 | |
| `consumer_disputed` | 77.8% | 2 | Policy change ~2017 — see yml |
| `has_narrative` | ~64% false | 2 | Opt-in; see yml for floor detail |

---

### products.sql
**Status**: partial

- **Outcome**: Raw product taxonomy: 8 legacy product categories that CFPB renamed over time. Debt collection subproduct labels also renamed across eras (added "debt" suffix: "Credit card" → "Credit card debt", etc.). Query 4b (issues × subissues, ~1,500 rows) is in the file but commented out — not yet run.
  - **Action**: → `product_normalized` and `subproduct_normalized` in `staging/stg_cfpb_complaints.sql:63-129`. Column descriptions in `staging/_models.yml:57-77`

- **Outcome**: Query 4a (product × subproduct cross-tab, 95 rows): all legacy debt collection subproduct renames confirmed handled in `seeds/subproduct_mapping.csv`. `"I do not know"` subproduct is a legitimate CFPB consumer-selected value, passes through as-is. One junk row (`Credit reporting` × `Conventional home mortgage`, 1 complaint) — data entry error, not worth handling.
  - **Action**: — (seeds already complete; no staging changes needed)

- **Outcome**: Narrative rate by product × year (post-June 2015 only) — *not yet run*

*See Current Priority section above for run order.*

---

### temporal.sql
**Status**: ✓

- **Outcome**: 2011 stub, 2023 partial. `consumer_disputed` 100% fill 2012–2016, drops to 0% by 2018 (CFPB policy change mid-2017). `has_narrative` 0% before mid-2015. 2020 +60% YoY (COVID). 2022 is peak year (800K).
  - **Action**: → staging date filter `staging/stg_cfpb_complaints.sql:14-17` (drops 2011 + 2023). Caveats in `staging/_models.yml` column descriptions.

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

- **Outcome**: Resolution time distribution by era. Same-day forwarding (0 days) dominates and increases over time: pre_2015 33% zero (p50=1d), 2015_2019 75% zero (p50=0, p90=5d), 2020_plus 92% zero (p50=0, p90=0, p99=20d). Zeros are real — CFPB progressively automated same-day routing, not an artifact. Negatives (-1 day, 7,036 rows) are pre_2015 only — the known intake-system artifact. No negative rows in 2015+.
  - **Action**: → `days_to_company` in `fct_complaints` (renamed from `days_to_resolution` — measures receipt→forwarding, not receipt→resolved). Clamp negatives with `GREATEST(..., 0)`. Keep zeros. Column name change signals the metric is about CFPB routing speed, not company resolution time.

---

## cfpb/setup/

### materialize.sql
**Status**: ✓ (one-time)

- **Outcome**: Raw table materialized from `bigquery-public-data.cfpb_complaints.complaint_database`. Dropped `consumer_complaint_narrative`, kept `has_narrative` boolean. 2.31 GB → 768 MB.
  - **Action**: — (one-time setup, already run)

---

### schemas.sql
**Status**: ✓

- **Outcome**: Column lists for both raw tables exported: 18 CFPB columns (17 source columns + derived `has_narrative`), 95 FDIC columns. Metadata only — free query.
  - **Action**: → `docs/schema.md:1-183` populated

---

## fdic/

### exploration.sql
**Status**: partial

- **Outcome**: 5a/5b: `top_holder` confirmed as right join grain (~94% of top-50-by-assets institutions have `top_holder` populated). Top holders by combined assets: JPMorgan $3.4T, BofA $2.5T, Wells Fargo $1.7T, Citi $1.7T, US Bancorp $582B, PNC $534B, Truist $532B, Capital One $515B. Normalization quirks confirmed: `&` without spaces (`JPMORGAN CHASE&CO`, `WELLS FARGO&COMPANY`), BCORP vs BANCORP (`U S BCORP`, `FIFTH THIRD BCORP`), trailing THE (`GOLDMAN SACHS GROUP INC THE`, `BANK OF NY MELLON CORP THE`), abbreviated words (`FINL` → FINANCIAL, `BK OF COM` → BANK OF COMMERCE). Two nulls in top 50: First Republic Bank (failed Mar 2023), Zions Bancorporation.
  - **Action**: → `top_holder` as crosswalk join key. Normalization quirks → `int_fdic_banks_normalized` (Phase 3).

- **Outcome**: 5c (naive uppercase join test — baseline match rate between CFPB names and FDIC `top_holder`) — *not yet run*. Query is active in file. Run for DECISIONS.md talking point.

- **Outcome**: 5e (suffix-strip fuzzy match) — 7/12 bank crosswalk entries matched cleanly (Ally, AmEx, BofA, Capital One, Citi, Discover, JPMorgan). 5 failures fixed in `seeds/company_crosswalk.csv`: (1) Wells Fargo — crosswalk had `WELLS FARGO & CO`, FDIC stores `WELLS FARGO&COMPANY` (no spaces, full COMPANY not CO); (2) USAA — crosswalk had `USAA`, FDIC uses `UNITED SERVICES AUTOMOBILE ASSN`; (3) Santander — `SANTANDER HOLDINGS USA INC` doesn't exist in FDIC, corrected to `BANCO SANTANDER SA` (ultimate parent of Santander Bank N.A.); (4–5) SunTrust + BB&T historical entries — `SUNTRUST BANKS INC` and `BB&T CORP` are pre-merger entities no longer in current FDIC (active-only snapshot); added `TRUIST BANK` → `TRUIST FINANCIAL CORP` row for post-2019 complaints. Synchrony Financial `fdic_top_holder` filled in (`SYNCHRONY FINANCIAL`, $87B assets confirmed).
  - **Action**: → `seeds/company_crosswalk.csv` updated. SunTrust/BB&T historical rows are correct for era but won't join to current FDIC snapshot — document in DECISIONS.md.

- **Outcome**: 5f (first-token LIKE scan) — skipped. All 12 bank crosswalk entries resolved via 5e (7 clean matches + 5 manual fixes in seed). No unmatched entries remain.

---

### phase3_prep.sql
**Status**: ✓ (all 4 queries run 2026-04-22)

1. **Bank coverage summary** — bank = 21.4% of complaints (739K), 98% FDIC fill rate (725K enrichable). Credit bureau 47.6%. The 22% NULL/uncrosswalked slice breaks down as: uncrosswalked banks 3.9%, debt collectors 3.1%, mortgage servicers 1.7%, auto lenders 0.8%, fintechs 0.8%, true long tail 11.5% (4,923 companies with <~500 complaints each).
   - **Action**: → frame Phase 3 as bank-segment analysis, not full-dataset enrichment. Coverage is meaningful (725K rows) but bounded.

2. **FDIC normalization preview** — all normalization rules produce clean values. Key: `&`-spacing, `BCORP`→`BANCORP`, trailing `THE`, `FINL`→`FINANCIAL` all work correctly. `total_assets` column is in thousands USD.
   - **Action**: → `int_fdic_banks_normalized` transformation rules confirmed. Build the model.

3. **Match rate (raw-to-raw join)** — 15/15 non-null `fdic_top_holder` values match raw FDIC `top_holder`. Join design: raw-to-raw (`dim_company.fdic_top_holder` = `fdic_active_banks_lean.top_holder`); normalization in `int_fdic_banks_normalized` is display-only, not the join key. One gap: Barclays has `fdic_top_holder = NULL` (not resolved in Phase 2).
   - **Action**: → confirm `dim_bank` join key is raw `top_holder`, not `top_holder_normalized`. Barclays gap: minor, fix optionally.

4. **Asset tier + CFPB supervision + ROA** — all 15 banks CFPB-supervised (100%; flag won't differentiate within our universe). Two size tiers only: 9 mega (>$250B), 6 large ($50B–$250B). ROA varies ~10x: USAA 13.1% (atypical), AmEx 5.0%, Capital One 2.8%, JPMorgan 0.8% — useful for correlation mart.
   - **Action**: → `dim_bank` columns: `total_assets_usd` (×1000), `bank_size_bucket` (mega/large only in practice), `is_supervised_cfpb`, `avg_roa`, `charter_count`. `total_assets` is in thousands — multiply in model.

---

## Reference: Company Taxonomy & FDIC Join Strategy

### Non-bank companies in top 50

47% of complaint volume is credit bureaus — no FDIC record exists. FDIC enrichment applies
only to the bank-category subset. Other non-bank categories in the top 50:

| Category | Examples |
|---|---|
| Credit bureaus | Equifax, TransUnion, Experian, LexisNexis |
| Debt collectors | Portfolio Recovery, Encore Capital, Resurgent, I.C. System, Convergent |
| Mortgage servicers | Ocwen, Ditech, Nationstar, Shellpoint, LoanCare, Specialized Loan Servicing |
| Student loan servicers | Navient, AES/PHEAA, Nelnet |
| Fintechs | PayPal, Coinbase |
| Auto/subprime lenders | Santander Consumer, Ally |

### FDIC join approach

A naive `JOIN ON company_name = fdic_institution_name` (even after uppercasing) matches
well under 30% of complaint volume: CFPB uses parent corporation names; FDIC lists
operating bank subsidiaries. Casing, punctuation, and suffixes inconsistent across both.

**Crosswalk seed** (`seeds/company_crosswalk.csv`, Phase 2): hand-map top CFPB
`company_name_normalized` values to canonical names, company categories, and FDIC
`top_holder` keys. Scope: top 30 institutions by complaint volume (all types) = **74%**
of complaint volume; long tail stays uncategorized. Mix: banks, credit bureaus, mortgage
servicers, debt collectors, student loan servicers, fintechs, one credit union. FDIC
enrichment gates on `category = 'bank'` only.

**`top_holder` as join grain**: FDIC's parent holding company name maps to CFPB's
parent-corp naming much better than `institution_name`. Populated for ~94% of
top-50-by-assets institutions. Confirmed via `fdic/exploration.sql` queries 5a/5b.

`top_holder` normalization quirks for `int_fdic_banks_normalized` (Phase 3):
- `&` without surrounding spaces: `JPMORGAN CHASE&CO`
- `BCORP` vs `BANCORP` abbreviation variants
- Trailing `THE`: `BANK OF NY MELLON CORP THE`
- Abbreviated words: `FINL` (financial), `BK OF COM` (bank of commerce)

### FDIC analytical opportunities (Phase 3+)

All metrics gate on `crosswalk.category = 'bank'`.

- Complaints per $B assets — normalizes volume for size comparison
- CFPB-supervised vs non-supervised banks — volume and resolution-rate delta; uses `cfpb_supervisory_flag`
- Specialization × issue type — card-focused banks × card complaint rate
- Bank-HQ state vs complaint state — customer-reach proxy
- ROA decile × complaint rate — stressed-bank hypothesis (do lower-profitability banks generate more complaints?)
- ML handoff feature table — per-bank `{total_assets, roa, offices_count, established_date, primary_specialization, cfpb_supervisory_flag}` → target `complaint_rate` or `timely_response_rate`

---

## validation/

### staging_validation.sql
**Status**: —

- **Outcome**: zip_code_is_valid distribution + not-provided sentinel checks — *not yet run*. Confirms staging zip cleanup and NULL→'not-provided' mappings applied correctly.
  - **Action**: → Run after any `dbt run` that touches `stg_cfpb_complaints`.

---

### verify_product_normalization.sql
**Status**: — (blocked — run after next `dbt run`)

- **Outcome**: Post-`dbt run` verification: confirms no legacy product names remain in `fct_complaints`, `Consumer Loan` fully split into two new categories, Debt collection subproducts normalized. Queries 1 and 5 are stale (referenced old `dim_product`; updated to query `fct_complaints` directly).
  - **Action**: Run in DBCode after `dbt run` on `stg_cfpb_complaints`, `fct_complaints`
