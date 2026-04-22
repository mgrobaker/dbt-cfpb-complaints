{{ config(materialized='table') }}

select date_day from {{ ref('dim_date') }}
