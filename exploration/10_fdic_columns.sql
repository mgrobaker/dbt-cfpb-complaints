-- Get the actual column list for fdic_active_banks_lean.
-- Metadata only (free). Paste the full CSV back so stg_fdic_banks can be fixed.

SELECT
  ordinal_position,
  column_name,
  data_type
FROM `dbt-portfolio-493318.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fdic_active_banks_lean'
ORDER BY ordinal_position;
