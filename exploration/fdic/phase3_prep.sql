-- Phase 3 preparation queries
-- Run before building int_fdic_banks_normalized and dim_bank.
-- Each query is independent — run individually in DBCode or bq CLI.

-- ─────────────────────────────────────────────────────────────────────────────
-- Query 0: Uncrosswalked complaint breakdown by implied entity type
-- Outcome: the 22% NULL-category slice is NOT a homogeneous long tail.
--   As % of total complaints (3.46M):
--   Uncrosswalked banks:            3.9%  (136K) — HSBC, Citizens, Fifth Third, Regions, M&T, etc.
--   Uncrosswalked debt collectors:  3.1%  (107K)
--   Uncrosswalked mortgage servicers: 1.7% (60K)
--   Uncrosswalked auto lenders:     0.8%   (28K)
--   Uncrosswalked fintechs:         0.8%   (27K)
--   True long tail (other):        11.5%  (398K, 4,923 companies)
-- The category column on fct_complaints already handles the crosswalked 78%;
-- this query characterizes what remains.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  CASE
    WHEN REGEXP_CONTAINS(company_name_normalized, r'MORTGAGE|HOME LOAN|LOAN SERVIC|SHELLPOINT|PENNYMAC|LOANCARE|RUSHMORE|CALIBER|FREEDOM|CARRINGTON|SETERUS|BAYVIEW|COMMUNITY LOAN')
      THEN 'mortgage_servicer'
    WHEN REGEXP_CONTAINS(company_name_normalized, r'STUDENT LOAN|NELNET|PHEAA|SALLIE MAE|GREAT LAKES|EDFINANCIAL')
      THEN 'student_loan_servicer'
    WHEN REGEXP_CONTAINS(company_name_normalized, r'COLLECTION|CREDIT SYSTEM|RECOVERY|TRANSWORLD|PORTFOLIO|ENCORE|RESURGENT|AFNI|DIVERSIFIED CONSULT|CCS FINANCIAL|CL HOLDING|COMMONWEALTH FINANCIAL|NATIONAL CREDIT|SOUTHWEST CREDIT|WESTLAKE')
      THEN 'debt_collector'
    WHEN REGEXP_CONTAINS(company_name_normalized, r'TOYOTA|HONDA|HYUNDAI|GENERAL MOTORS FINANCIAL|FORD MOTOR CREDIT|NISSAN|CREDIT ACCEPTANCE|WESTLAKE')
      THEN 'auto_lender'
    WHEN REGEXP_CONTAINS(company_name_normalized, r'COINBASE|CHIME|PAYPAL|VENMO|SQUARE|STRIPE|KLARNA|AFFIRM|WESTERN UNION|MONEYGRAM|FIDELITY NATIONAL INFO|FNIS')
      THEN 'fintech'
    WHEN REGEXP_CONTAINS(company_name_normalized, r'BANK|FINANCIAL CORP|FINANCIAL GROUP|BANCORP|CREDIT UNION|SAVINGS|FEDERAL SAVINGS|NATIONAL ASSOCIATION|N\.A\b|FSB\b|HSBC|GOLDMAN|CITIBANK|BBVA|CITIZENS|COMERICA|KEYCORP|REGIONS|FLAGSTAR')
      THEN 'bank'
    ELSE 'other'
  END AS implied_category,
  COUNT(DISTINCT company_name_normalized) AS distinct_companies,
  COUNT(*) AS complaint_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct_of_uncrosswalked
FROM `dbt-portfolio-493318.dbt_dev.fct_complaints`
WHERE is_crosswalked = false
GROUP BY implied_category
ORDER BY complaint_count DESC;

-- ─────────────────────────────────────────────────────────────────────────────
-- Query 1: Bank coverage summary (already run; saved for reference)
-- Outcome: bank = 21.4% of complaints (739K), 98% FDIC fill rate (725K rows enrichable).
--   Credit bureau dominates at 47.6%; NULL (uncrosswalked long tail) = 22%.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  f.category,
  COUNT(*)                                                          AS complaint_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 3)                       AS pct_of_total,
  COUNTIF(d.fdic_top_holder IS NOT NULL)                           AS has_fdic,
  ROUND(COUNTIF(d.fdic_top_holder IS NOT NULL) / COUNT(*), 3)      AS fdic_fill_rate
FROM `dbt-portfolio-493318.dbt_dev.fct_complaints` f
LEFT JOIN `dbt-portfolio-493318.dbt_dev.dim_company` d USING (company_sk)
GROUP BY f.category
ORDER BY complaint_count DESC;

-- ─────────────────────────────────────────────────────────────────────────────
-- Query 2: FDIC top_holder normalization preview
-- Applies the planned int_fdic_banks_normalized transformations to raw top_holder.
-- Shows before → after for the 30 largest holders by total assets.
-- Note: total_assets is in thousands USD (JPMorgan 3.38B → $3.38T).
-- Outcome: all normalization rules produce clean values. Key transforms:
--   JPMORGAN CHASE&CO → JPMORGAN CHASE & CO
--   U S BCORP → U S BANCORP, FIFTH THIRD BCORP → FIFTH THIRD BANCORP
--   GOLDMAN SACHS GROUP INC THE → GOLDMAN SACHS GROUP INC
--   PNC FINL SERVICES GROUP INC → PNC FINANCIAL SERVICES GROUP INC
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  top_holder AS raw_top_holder,
  REGEXP_REPLACE(
    REPLACE(
      REPLACE(
        REPLACE(
          REGEXP_REPLACE(TRIM(UPPER(top_holder)), r'\s+', ' '),
          '&', ' & '           -- add spaces around ampersand
        ),
        'BCORP', 'BANCORP'     -- expand abbreviation
      ),
      ' FINL ', ' FINANCIAL '  -- expand abbreviation
    ),
    r' THE$', ''               -- strip trailing THE
  )                                                      AS top_holder_normalized,
  COUNT(*)                                               AS charter_count,
  SUM(total_assets)                                      AS total_assets_thousands
FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
WHERE top_holder IS NOT NULL
GROUP BY raw_top_holder, top_holder_normalized
ORDER BY total_assets_thousands DESC
LIMIT 30;

-- ─────────────────────────────────────────────────────────────────────────────
-- Query 3: Match rate — dim_company.fdic_top_holder vs raw FDIC top_holder
-- Join is RAW-to-RAW: dim_company.fdic_top_holder stores the raw FDIC string.
-- Normalization in int_fdic_banks_normalized adds a display column only;
-- the actual join key in dim_bank → dim_company must be raw top_holder.
-- Outcome: 15/15 non-null fdic_top_holder values match. Only Barclays has
--   fdic_top_holder = NULL (not resolved during Phase 2 — known gap).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
  d.canonical_name,
  d.fdic_top_holder,
  CASE WHEN f.top_holder IS NOT NULL THEN 'match' ELSE 'no match' END AS join_status
FROM `dbt-portfolio-493318.dbt_dev.dim_company` d
LEFT JOIN (SELECT DISTINCT top_holder FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`) f
  ON d.fdic_top_holder = f.top_holder
WHERE d.category = 'bank'
ORDER BY join_status, d.canonical_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- Query 4: Asset tier distribution + CFPB supervision + ROA
-- Outcome:
--   - All 15 matched banks are CFPB-supervised (100%) — flag won't differentiate
--     within our universe; document for production framing with a broader bank set.
--   - Two tiers only: 9 mega (>$250B), 6 large ($50B–$250B). No mid/regional/community
--     in our crosswalk — by design (top institutions by complaint volume).
--   - ROA varies ~10x: USAA 13.1% (atypical), AmEx 5.0%, Capital One 2.8%,
--     JPMorgan 0.79%. Useful variable for correlation mart.
--   - total_assets is in thousands USD; multiply ×1000 for USD in the model.
-- ─────────────────────────────────────────────────────────────────────────────
WITH bank_fdic AS (
  SELECT
    top_holder,
    SUM(total_assets)         AS total_assets_thousands,
    COUNT(*)                  AS charter_count,
    MAX(cfpb_supervisory_flag) AS is_supervised_cfpb,
    ROUND(AVG(return_on_assets), 4) AS avg_roa
  FROM `dbt-portfolio-493318.raw.fdic_active_banks_lean`
  WHERE top_holder IS NOT NULL
  GROUP BY top_holder
)
SELECT
  d.canonical_name,
  ROUND(f.total_assets_thousands / 1e6, 1)  AS total_assets_billions,
  f.charter_count,
  f.is_supervised_cfpb,
  f.avg_roa,
  CASE
    WHEN f.total_assets_thousands >= 250000000 THEN 'mega (>$250B)'
    WHEN f.total_assets_thousands >= 50000000  THEN 'large ($50B-$250B)'
    WHEN f.total_assets_thousands >= 10000000  THEN 'mid ($10B-$50B)'
    WHEN f.total_assets_thousands >= 1000000   THEN 'regional ($1B-$10B)'
    ELSE                                            'community (<$1B)'
  END AS bank_size_bucket
FROM `dbt-portfolio-493318.dbt_dev.dim_company` d
JOIN bank_fdic f ON d.fdic_top_holder = f.top_holder
WHERE d.category = 'bank'
ORDER BY f.total_assets_thousands DESC;
