-- Dump column lists for both raw tables. Metadata-only, no cost.
-- Paste output into docs/schema.md.

SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable
FROM `dbt-portfolio-493318.raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name IN ('cfpb_complaints', 'fdic_active_banks_lean')
ORDER BY table_name, ordinal_position;
