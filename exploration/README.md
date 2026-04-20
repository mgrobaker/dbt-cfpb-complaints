# Exploration Query Tracker

Status of each exploration query. Update as you run things.

**Status key**: `✓` done · `partial` some sub-queries run · `—` not yet run

---

## cfpb/companies/

### quality.sql
**Status**: partial

- **Outcome**: Long-tail distribution — most of 6,694 company strings have <20 complaints (noise/typos). Alphabetical dump confirms variant clusters (same entity, different casing/punctuation/suffix).
  - **Action**: → crosswalk seed strategy decided (hand-map top companies, not fuzzy join). `docs/data-quality-notes.md:132-143`

- **Outcome**: Response field values (`company_response_to_consumer`, `company_public_response`, `consumer_consent_provided`) — *not yet run*

- **Outcome**: Timely response rate by top companies — *not yet run*

---

### volume.sql
**Status**: partial

- **Outcome**: Top 50 companies by raw name: Equifax + TransUnion + Experian = 47% of all complaints; none have FDIC records. Mixed casing and punctuation confirmed. Rebrands visible in date ranges (SunTrust→Truist 2019, Ditech exits 2020, Alliance Data→Bread Financial ~2021).
  - **Action**: → confirmed credit bureaus out of scope for FDIC join. `docs/data-quality-notes.md:99-143`; `company_name_normalized` expression in `staging/stg_cfpb_complaints.sql:31-34`

- **Outcome**: Cumulative coverage by normalized name (% of total volume per top-N companies) — *not yet run*. Needed to size crosswalk seed at ~85% volume target.

---

## cfpb/profile/

### anomalies.sql
**Status**: partial

- **Outcome**: Date ordering violations: 7,036 rows (~0.2%) where `date_sent_to_company < date_received`. All exactly 1 day early, all 2012-01-22 to 2014-04-26. Proportionally spread across all major filers — systematic intake-system artifact, not a data error.
  - **Action**: → `tests/assert_complaint_dates_ordered.sql` at `severity: warn`. `docs/data-quality-notes.md:115-127`

- **Outcome**: Tags field co-occurrence (Servicemember, Older American, both) — *not yet run*. Informs `tags_is_servicemember` / `tags_is_older_american` staging flags.

- **Outcome**: Zip code validity — masked XXXXX patterns, 4-digit values, nulls — *not yet run*. Informs `zip_code_is_valid` staging flag.

---

### geographic.sql
**Status**: ✓

- **Outcome**: 63 distinct state values, all legitimate. One long-form outlier: "UNITED STATES MINOR OUTLYING ISLANDS" (305 rows). 41,114 null rows (1.2%). All other values are valid 2-char USPS codes (50 states + DC, territories, APO codes, freely associated states).
  - **Action**: → state CASE expression `staging/stg_cfpb_complaints.sql:35-40` (NULL → `'not-provided'`, long-form → `'UM'`, safety catch for future edge cases). `accepted_values` test list confirmed against actual data; wired at `severity: error` (dbt default — no explicit config block needed). `staging/_models.yml:100-168`; `docs/data-quality-notes.md:98-112`

---

### overview.sql
**Status**: ✓

- **Outcome**: 3.46M rows, 2011-12-01 to 2023-03-23. 6,694 distinct companies. Key null rates: `tags` 88.9%, `consumer_disputed` 77.8%, `subissue` 20.2%, `subproduct` 6.8%. 20-row sample confirmed data shape and casing mess.
  - **Action**: → `docs/data-quality-notes.md:1-37` (dataset shape + column coverage table). Column descriptions in `staging/_models.yml:9-240`

---

### products.sql
**Status**: partial

- **Outcome**: Raw product taxonomy: 8 legacy product categories that CFPB renamed over time. Debt collection subproduct labels also renamed across eras (added "debt" suffix: "Credit card" → "Credit card debt", etc.). Query 4b (issues × subissues, ~1,500 rows) is in the file but commented out — not yet run.
  - **Action**: → `product_normalized` and `subproduct_normalized` in `staging/stg_cfpb_complaints.sql:63-129`. Column descriptions in `staging/_models.yml:57-77`

- **Outcome**: Narrative rate by product × year (post-June 2015 only) — *not yet run*

---

### temporal.sql
**Status**: partial

- **Outcome**: Year-over-year: 2011 is a stub (2,536 rows), 2023 is partial (frozen 2023-03-25). `consumer_disputed` 100% fill 2012–2016, drops to 0% by 2018 (CFPB policy change mid-2017). `has_narrative` 0% before mid-2015. 2020 +60% YoY (COVID). 2022 is peak year (800K).
  - **Action**: → staging date filter `staging/stg_cfpb_complaints.sql:14-17` (drops 2011 + 2023). `docs/data-quality-notes.md:39-95`

- **Outcome**: Resolution time distribution (percentile breakdown by era) — *not yet run*. Informs `days_to_resolution` derived field in `fct_complaints`.

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

- **Outcome**: 5a/5b: `top_holder` confirmed as right join grain (~94% of top-50-by-assets institutions have `top_holder` populated). Normalization quirks documented: `&` without spaces (`JPMORGAN CHASE&CO`), BCORP vs BANCORP, trailing THE (`BANK OF NY MELLON CORP THE`), abbreviated words (`FINL`, `BK OF COM`).
  - **Action**: → `top_holder` as crosswalk join key. `staging/_models.yml:225-229`; `docs/data-quality-notes.md:134-167`. Normalization quirks → deferred to `int_fdic_banks_normalized` (Phase 3).

- **Outcome**: 5c (naive uppercase join test — baseline match rate between CFPB names and FDIC `top_holder`) — *not yet run*. Query is active in file (not commented out). Intentionally deferred: crosswalk seed strategy already decided; run later for README/interview talking points. 5d is commented out.

---

## Top level

### verify_product_normalization.sql
**Status**: —

- **Outcome**: Post-`dbt run` verification: confirms `dim_product` has 66 rows, no legacy product names remain in `fct_complaints`, `Consumer Loan` fully split into two new categories, Debt collection subproducts normalized.
  - **Action**: Run in DBCode after `dbt run` on `stg_cfpb_complaints`, `dim_product`, `fct_complaints`
