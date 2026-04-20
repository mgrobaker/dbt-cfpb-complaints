# Data Quality Notes

Findings from the exploration phase. Documents known quirks, policy-driven gaps, and
modeling decisions so downstream consumers don't misread them as bugs.

Exploration queries referenced here live in `exploration/`.

---

## Dataset shape

- **Source**: `bigquery-public-data.cfpb_complaints.complaint_database`, frozen 2023-03-25
- **Rows (raw)**: 3,458,906 — date range 2011-12-01 to 2023-03-23
- **Rows (staging)**: ~3.21M after dropping 2011 and 2023 (see date range section below)
- **`consumer_complaint_narrative` dropped** at raw materialization; replaced with boolean
  `has_narrative`. Reduced table from 2.31 GB → 768 MB.

---

## Column coverage

| Column | Null % | Distinct | Notes |
|---|---|---|---|
| `complaint_id` | 0% | — | Natural PK |
| `product` | 0% | 18 | See accepted_values caveat below |
| `subproduct` | 6.8% | 76 | |
| `issue` | 0% | 165 | |
| `subissue` | 20.2% | 221 | |
| `company_name` | 0% | 6,694 | See company name section below |
| `state` | 1.2% | 63 | Remapped in staging — see state section below |
| `tags` | 88.9% | 3 | Servicemember / Older American / both |
| `company_public_response` | 55.6% | 11 | |
| `consumer_disputed` | 77.8% | 2 | **Policy change ~2017 — see below** |
| `has_narrative` | ~64% false | 2 | Opt-in; behavior changed over time — see below |

---

## Date range — 2011 and 2023 excluded from staging

`stg_cfpb_complaints` filters to `date_received >= '2012-01-01' AND < '2023-01-01'`.

**2011**: stub year. CFPB launched 2011-07-21; only 2,536 complaints and 76 companies in
the dataset. Too thin to be analytically meaningful alongside full years.

**2023**: partial year, frozen at 2023-03-23 (~Q1 only). Narrative rate (16.6%) and public
response rate (30.3%) are well below steady-state, depressing any full-year comparison.

Both years remain in the raw table and can be included by querying the source directly or
modifying the staging filter.

---

## Year-over-year profile

Query: `exploration/08_cfpb_by_year.sql`

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

---

## `consumer_disputed` — policy change, not a bug

77.8% null overall. CFPB stopped collecting the consumer dispute field partway through 2017:
fill rate is 100% through 2016, drops to 29.8% in 2017 (stopped mid-year), then 0% from
2018 onward.

**Any dispute-rate metric must be gated on `date_received < '2017-01-01'`** to avoid
comparing years with 100% fill against years with 0% fill. Computing an overall dispute
rate across all years produces a misleading result (~22%) that reflects the policy gap, not
consumer behavior.

---

## `has_narrative` — zero before June 2015

0% narrative rate for 2011–2014. CFPB launched the consumer narrative feature (with
opt-in consent) in June 2015. Models using `has_narrative` should document 2015 as the
effective floor; the 2015 rate (32.5%) reflects a partial year of collection.

---

## `state` — non-standard codes remapped

Query: `exploration/11_cfpb_by_state.sql`

63 distinct raw values. All legitimate USPS codes. Categories:
- 50 US states + DC
- Territories: PR, VI, GU, AS, MP
- Military APO codes: AA (Americas), AE (Europe/Middle East/Canada), AP (Pacific)
- Freely associated states (use US postal system): FM (Micronesia), MH (Marshall Islands), PW (Palau)

Two values remapped in `stg_cfpb_complaints`:
- `NULL` (41,114 rows, 1.2%) → `'not-provided'`
- `'UNITED STATES MINOR OUTLYING ISLANDS'` (305 rows) → `'UM'` (ISO 3166-1 alpha-2)

A safety-catch `CASE` branch maps any other unexpected long-form value to `'not-provided'`.
`accepted_values` test on `state` uses `severity: error` — list confirmed against actual data.

---

## `date_sent_to_company` ordering violations

Query: `exploration/12_date_ordering_violations.sql`

7,036 rows (~0.2%) where `date_sent_to_company < date_received`. Investigation showed:
- All exactly **1 day** early
- All between **2012-01-22 and 2014-04-26**
- Proportionally distributed across every major filer (Experian, Equifax, BofA, JPMorgan, etc.)

Conclusion: systematic artifact from CFPB's early intake system, likely a timezone or
batch-processing clock issue. Not a meaningful data error. Rows are kept;
`assert_complaint_dates_ordered` test runs with `severity: warn`.

---

## Company name normalization

6,694 distinct values in `company_name`. Known issues:
- Mixed casing: mostly UPPERCASE, some Title Case, some inconsistent punctuation
- Parent corporation vs. subsidiary naming (e.g. "JPMORGAN CHASE & CO." vs. "JPMorgan Chase Bank, N.A.")
- Entity renames mid-dataset: SunTrust → Truist (2019), Alliance Data Systems → Bread Financial (~2021), Ditech exits (2020)

`company_name_normalized` in `stg_cfpb_complaints` applies UPPER, collapses internal
whitespace, and strips trailing punctuation. Full canonicalization — including parent/child
resolution and rename handling — is deferred to the company crosswalk seed in Phase 2.

**Credit bureau concentration**: Equifax + TransUnion + Experian account for ~47% of all
complaints. These companies have no FDIC record; FDIC enrichment applies only to the
bank-category subset of complaints.

## Non-bank company types in top 50

The top-50 companies by complaint volume include several non-bank categories that will not match FDIC data. Any FDIC enrichment applies only to the bank-category subset.

| Category | Examples |
|---|---|
| Credit bureaus | Equifax, TransUnion, Experian, LexisNexis |
| Debt collectors | Portfolio Recovery, Encore Capital, Resurgent, I.C. System, Convergent |
| Mortgage servicers | Ocwen, Ditech, Nationstar, Shellpoint, LoanCare, Specialized Loan Servicing |
| Student loan servicers | Navient, AES/PHEAA, Nelnet |
| Fintechs | PayPal, Coinbase |
| Auto/subprime lenders | Santander Consumer, Ally |

---

## FDIC join strategy

A naive `JOIN ON company_name = fdic_institution_name` (even after uppercasing and trimming) will match well under 30% of complaint volume because:
1. **CFPB uses parent corporation names**; FDIC lists operating bank subsidiaries (e.g. CFPB: "JPMORGAN CHASE & CO." / FDIC: "JPMorgan Chase Bank, National Association")
2. **47% of volume is credit bureaus** — no FDIC record exists for these companies
3. **Casing, punctuation, and suffixes** are inconsistent across both sources

**Approach: hand-built crosswalk seed** (`seeds/company_crosswalk.csv`) mapping top CFPB `company_name` values to canonical names, company categories, and FDIC certificate numbers where applicable. Scope: top ~50 companies ≈ 85% of complaint volume. Long tail stays uncategorized.

**FDIC `top_holder` is the right join grain** — confirmed via exploration. The `top_holder` column (parent holding company name) maps to CFPB's parent-corp naming convention much better than `institution_name`. Populated for ~94% of top-50-by-assets institutions.

`top_holder` normalization quirks that the intermediate model (`int_fdic_banks_normalized`, Phase 3) must handle:
- `&` without surrounding spaces: `JPMORGAN CHASE&CO`
- `BCORP` vs `BANCORP` abbreviation variants
- Trailing `THE`: `BANK OF NY MELLON CORP THE`
- Abbreviated words: `FINL` (financial), `BK OF COM` (bank of commerce)

---

## `product` and `submitted_via` — accepted_values unverified

The `accepted_values` tests on `product` and `submitted_via` use `severity: warn` and are
marked TODO in `_models.yml`. The value lists were written from general knowledge of CFPB
taxonomy and have not been verified against `SELECT DISTINCT product FROM raw.cfpb_complaints`.
Run that query before promoting either test to `severity: error`.

---

## `product` taxonomy normalization

CFPB renamed several product categories over time. Raw `product` has 18 distinct values but only ~10 analytical categories — 8 are legacy names that were consolidated into current labels. A naive `GROUP BY product` double-counts these categories across eras.

`product_normalized` and `subproduct_normalized` in `stg_cfpb_complaints` resolve this. Raw `product` and `subproduct` are preserved for auditability.

**Legacy product → normalized product:**

| Legacy `product` | Normalized to |
|---|---|
| Bank account or service | Checking or savings account |
| Consumer Loan *(vehicle subproducts)* | Vehicle loan or lease |
| Consumer Loan *(other subproducts)* | Payday loan, title loan, or personal loan |
| Credit card | Credit card or prepaid card |
| Credit reporting | Credit reporting, credit repair services, or other personal consumer reports |
| Money transfers | Money transfer, virtual currency, or money service |
| Payday loan | Payday loan, title loan, or personal loan |
| Prepaid card | Credit card or prepaid card |
| Virtual currency | Money transfer, virtual currency, or money service |

**`Debt collection` subproduct normalization:** CFPB added a "debt" suffix to subproduct labels in newer taxonomy. Legacy labels normalized: `Credit card` → `Credit card debt`, `Medical` → `Medical debt`, `Auto` → `Auto debt`, `Mortgage` → `Mortgage debt`, `Federal student loan` → `Federal student loan debt`, `Non-federal student loan` → `Private student loan debt`, `Other (i.e. phone, health club, etc.)` → `Other debt`.

**Unrecognized values pass through unchanged** — if CFPB adds future categories they will appear as new rows in `dim_product` without breaking the model.

---

## FDIC analytical opportunities

The following analyses are possible once the FDIC bank dim (Phase 3) is built. All metrics apply only to the bank-category subset of complaints; gate on `crosswalk.category = 'bank'` and document the scope in the mart.

- **Complaints per $B assets by bank** — normalizes complaint volume for fair size comparison
- **CFPB-supervised vs non-supervised banks** — volume and resolution-rate delta; uses `cfpb_supervisory_flag`
- **Specialization × issue type** — `credit_card_institution` × `product_normalized` to test whether card-focused banks drive disproportionate card complaints
- **Bank-HQ state vs complaint state** — mismatch as a customer-reach proxy
- **ROA decile × complaint rate** — stressed-bank hypothesis (do lower-profitability banks generate more complaints?)
- **ML handoff feature table** — per-bank `{total_assets, roa, offices_count, established_date, primary_specialization, cfpb_supervisory_flag}` → target `complaint_rate` or `timely_response_rate`. Clean "AE delivers features to DS" portfolio artifact.
