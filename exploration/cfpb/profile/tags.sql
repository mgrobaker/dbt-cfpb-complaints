-- Tags field: distinct values and co-occurrence.
-- Informs parse strategy for tags_is_servicemember / tags_is_older_american staging flags.
-- 88.9% null — field only populated for special populations (Servicemembers, Older Americans).
-- Moved out of anomalies.sql: not an anomaly, just a parse-strategy check.

-- ================================================================
-- Distinct values — confirms full range of non-null tags
-- 3 non-null values expected: 'Servicemember', 'Older American', 'Older American, Servicemember'
-- ================================================================
SELECT
  COALESCE(tags, '(null)')  AS tags,
  COUNT(*)                  AS n
FROM `raw.cfpb_complaints`
GROUP BY tags
ORDER BY n DESC;

-- ================================================================
-- Co-occurrence: confirms LIKE parse handles all 3 values correctly.
-- Every non-null row should be accounted for by is_servicemember OR is_older_american OR both.
-- ================================================================
SELECT
  tags,
  COUNT(*)                                                                AS n,
  COUNTIF(tags LIKE '%Servicemember%')                                  AS n_servicemember,
  COUNTIF(tags LIKE '%Older American%')                                 AS n_older_american,
  COUNTIF(tags LIKE '%Servicemember%' AND tags LIKE '%Older American%') AS n_both
FROM `raw.cfpb_complaints`
WHERE tags IS NOT NULL
GROUP BY tags
ORDER BY n DESC;
