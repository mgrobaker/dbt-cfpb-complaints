# Raw Source Schemas

Reference for the raw tables this project reads from. Living doc — update when source tables change.

## `dbt-portfolio-493318.raw.cfpb_complaints`

Materialized from `bigquery-public-data.cfpb_complaints.complaint_database` (last modified 2023-03-25). `consumer_complaint_narrative` dropped to reduce table size from 2.31 GB → 768 MB; replaced with boolean `has_narrative`.

- Rows: 3,458,906
- Date range: 2011-12-01 to 2023-03-23
- 18 columns (all nullable per INFORMATION_SCHEMA)

| # | Column | Type | Null % | Notes |
|---|---|---|---|---|
| 1 | `complaint_id` | STRING | 0 | Natural PK |
| 2 | `date_received` | DATE | 0 | |
| 3 | `date_sent_to_company` | DATE | 0 | |
| 4 | `product` | STRING | 0 | 18 distinct |
| 5 | `subproduct` | STRING | 6.8 | 76 distinct |
| 6 | `issue` | STRING | 0 | 165 distinct |
| 7 | `subissue` | STRING | 20.2 | 221 distinct |
| 8 | `company_name` | STRING | 0 | 6,694 distinct — normalization target |
| 9 | `state` | STRING | 1.2 | 63 distinct (check outliers) |
| 10 | `zip_code` | STRING | 1.2 | |
| 11 | `tags` | STRING | 88.9 | 3 distinct |
| 12 | `submitted_via` | STRING | 0 | 7 distinct |
| 13 | `company_response_to_consumer` | STRING | <0.1 | 8 distinct |
| 14 | `company_public_response` | STRING | 55.6 | 11 distinct |
| 15 | `timely_response` | BOOL | 0 | |
| 16 | `consumer_disputed` | BOOL | 77.8 | CFPB stopped collecting ~2017 |
| 17 | `consumer_consent_provided` | STRING | 25.2 | 4 distinct |
| 18 | `has_narrative` | BOOL | 0 | Derived; narrative text dropped at materialize |

## `dbt-portfolio-493318.raw.fdic_active_banks_lean`

Active FDIC institutions, trimmed from 117 → 95 cols. All `active = TRUE`. Loaded prior session.

- Rows: 4,756
- 95 columns, all nullable per INFORMATION_SCHEMA

### Identity & ownership (cols 1–7, 58–63)

| # | Column | Type | Notes |
|---|---|---|---|
| 1 | `fdic_certificate_number` | STRING | PK candidate |
| 2 | `institution_name` | STRING | Operating bank name (e.g. "JPMorgan Chase Bank, National Association") |
| 3 | `trade_name_1` | STRING | DBA |
| 4 | `fdic_id` | STRING | |
| 5 | `rssd_id` | STRING | Fed ID |
| 6 | `ultimate_cert_number` | STRING | |
| 7 | `parent_parcert` | STRING | |
| 58 | `holding_company_flag` | BOOL | |
| 59 | `holding_company_state` | STRING | |
| 60 | `high_holder_city` | STRING | |
| 61 | `top_holder` | STRING | **⭐ Parent holding company name — likely bridge to CFPB `company_name`** |
| 62 | `ownership_type` | STRING | |
| 63 | `subchap_s_indicator` | BOOL | |

### Status flags (cols 8–10, 50–57)

| # | Column | Type | Notes |
|---|---|---|---|
| 8 | `active` | BOOL | All TRUE in this table |
| 9 | `conservatorship` | BOOL | |
| 10 | `denovo_institute` | BOOL | |
| 50 | `fdic_insured` | BOOL | |
| 51 | `deposit_insurance_date` | DATE | |
| 52 | `deposit_insurance_fund_member` | BOOL | |
| 53 | `bank_insurance_fund_member` | BOOL | |
| 54 | `insurance_fund_membership` | STRING | |
| 55 | `secondary_insurance_fund` | STRING | |
| 56 | `insured_commercial_bank` | BOOL | |
| 57 | `insured_savings_institute` | BOOL | |

### Location (cols 11–28)

| # | Column | Type | Notes |
|---|---|---|---|
| 11 | `address` | STRING | |
| 12 | `city` | STRING | |
| 13 | `state` | STRING | 2-char code |
| 14 | `state_name` | STRING | |
| 15 | `state_fips_code` | STRING | |
| 16 | `zip_code` | STRING | |
| 17 | `county_name` | STRING | |
| 18 | `county_fips_code` | STRING | |
| 19 | `cbsa_name` | STRING | Core-Based Statistical Area name |
| 20 | `cbsa_fips_code` | STRING | |
| 21 | `cbsa_metro_flag` | BOOL | |
| 22 | `cbsa_micro_flag` | BOOL | |
| 23 | `cbsa_division_name` | STRING | |
| 24 | `cbsa_division_fips_code` | STRING | |
| 25 | `cbsa_division_flag` | BOOL | |
| 26 | `csa_name` | STRING | Combined Statistical Area name |
| 27 | `csa_fips_code` | STRING | |
| 28 | `csa_indicator` | BOOL | |

### Charter & regulator (cols 29–46)

| # | Column | Type | Notes |
|---|---|---|---|
| 29 | `bank_charter_class` | STRING | |
| 30 | `chartering_agency` | STRING | |
| 31 | `federal_charter` | BOOL | |
| 32 | `state_chartered` | BOOL | |
| 33 | `occ_charter` | STRING | |
| 34 | `occ_district` | STRING | |
| 35 | `regulator` | STRING | |
| 36 | `category_code` | STRING | |
| 37 | `ots_region` | STRING | ⚠️ "West" vs "Western" inconsistency — staging normalization |
| 38 | `qbp_region` | STRING | |
| 39 | `fdic_geo_region` | STRING | |
| 40 | `fdic_supervisory_region` | STRING | |
| 41 | `fdic_supervisory_region_code` | STRING | |
| 42 | `fdic_field_office` | STRING | |
| 43 | `fed_reserve_district` | STRING | |
| 44 | `fed_reserve_district_id` | STRING | |
| 45 | `fed_reserve_unique_id` | STRING | |
| 46 | `docket` | STRING | |

### CFPB supervisory scope (cols 47–49) ⭐

| # | Column | Type | Notes |
|---|---|---|---|
| 47 | `cfpb_supervisory_flag` | BOOL | **Whether bank is under CFPB supervision** |
| 48 | `cfpb_supervisory_start_date` | DATE | Mostly 2011-07-21 for large banks |
| 49 | `cfpb_supervisory_end_date` | DATE | |

### Business characteristics (cols 64–71)

| # | Column | Type | Notes |
|---|---|---|---|
| 64 | `primary_specialization` | STRING | |
| 65 | `asset_concentration_hierarchy` | STRING | |
| 66 | `credit_card_institution` | BOOL | |
| 67 | `ag_lending_flag` | BOOL | |
| 68 | `trust_powers_status` | STRING | |
| 69 | `iba` | BOOL | International Banking Act |
| 70 | `ffiec_call_report_filer` | BOOL | |
| 71 | `law_sasser` | BOOL | |

### Financials (cols 72–83)

| # | Column | Type | Notes |
|---|---|---|---|
| 72 | `total_assets` | INT64 | Sort key for size |
| 73 | `total_deposits` | INT64 | |
| 74 | `total_domestic_deposits` | INT64 | |
| 75 | `equity_capital` | INT64 | |
| 76 | `net_income` | INT64 | |
| 77 | `quarterly_net_income` | INT64 | |
| 78 | `return_on_assets` | FLOAT64 | |
| 79 | `roa_quarterly` | FLOAT64 | |
| 80 | `roa_pretax` | FLOAT64 | |
| 81 | `row_pretax_quarterly` | FLOAT64 | (sic — source typo) |
| 82 | `return_on_equity` | FLOAT64 | |
| 83 | `roe_quarterly` | FLOAT64 | |

### Offices & dates (cols 84–95)

| # | Column | Type | Notes |
|---|---|---|---|
| 84 | `offices_count` | INT64 | |
| 85 | `office_count_domestic` | INT64 | |
| 86 | `office_count_foreign` | INT64 | |
| 87 | `office_count_us_territories` | INT64 | |
| 88 | `established_date` | DATE | |
| 89 | `last_structural_change` | DATE | |
| 90 | `effective_date` | DATE | |
| 91 | `end_effective_date` | DATE | |
| 92 | `report_date` | DATE | |
| 93 | `reporting_period_end_date` | DATE | |
| 94 | `last_updated` | DATE | |
| 95 | `run_date` | DATE | |

## Joining Strategy

CFPB uses **parent corporation names** ("JPMORGAN CHASE & CO."); FDIC has both:
- `institution_name` = operating subsidiary ("JPMorgan Chase Bank, National Association")
- `top_holder` = parent holding company ("JPMORGAN CHASE & CO.") ← **likely join key**

Top CFPB names like credit bureaus and debt collectors won't appear in either field (non-banks). Still expect a hand-maintained crosswalk seed for those, but `top_holder` match may cover most bank-side volume without fuzzy matching.
