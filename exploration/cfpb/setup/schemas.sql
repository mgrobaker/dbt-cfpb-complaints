-- INFORMATION_SCHEMA column listings. Metadata only — free, no bytes scanned.
-- Run to inspect column names, types, and nullability without touching data.

-- ================================================================
-- Both raw tables side-by-side
-- ================================================================
SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable
FROM `dbt-portfolio-493318.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('cfpb_complaints', 'fdic_active_banks_lean')
ORDER BY table_name, ordinal_position;

-- ================================================================
-- FDIC only (full column list for stg_fdic_banks reference)
-- ================================================================
SELECT
  ordinal_position,
  column_name,
  data_type
FROM `dbt-portfolio-493318.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fdic_active_banks_lean'
ORDER BY ordinal_position;
