-- Company name variant analysis — spot near-duplicates before building the crosswalk.
-- Two passes:
--   1. Distribution: how many companies have only 1-5 complaints? (likely noise/typos)
--   2. Full list sorted alphabetically so visually similar names cluster together.
--      Paste into a spreadsheet, sort, scan for variants of the same entity.

-- Pass 1: long-tail distribution
SELECT
  CASE
    WHEN complaints = 1        THEN '1'
    WHEN complaints BETWEEN 2 AND 5   THEN '2-5'
    WHEN complaints BETWEEN 6 AND 20  THEN '6-20'
    WHEN complaints BETWEEN 21 AND 100 THEN '21-100'
    WHEN complaints BETWEEN 101 AND 1000 THEN '101-1000'
    ELSE '1001+'
  END                           AS complaint_bucket,
  COUNT(*)                      AS company_count,
  SUM(complaints)               AS total_complaints
FROM (
  SELECT company_name, COUNT(*) AS complaints
  FROM `dbt-portfolio-493318.raw.cfpb_complaints`
  GROUP BY company_name
)
GROUP BY complaint_bucket
ORDER BY MIN(complaints);

-- Pass 2: full company list, alphabetical (run separately — returns all 6,694 rows)
-- Scan for: same root word, different casing/punctuation/suffix (Inc. vs Inc vs INC),
-- known rebrands (SunTrust / Truist), parent vs subsidiary naming.

SELECT
  company_name,
  COUNT(*)                    AS complaints,
  MIN(date_received)          AS first_seen,
  MAX(date_received)          AS last_seen,
  COUNT(DISTINCT product)     AS products
FROM `dbt-portfolio-493318.raw.cfpb_complaints`
GROUP BY company_name
ORDER BY company_name;

