with date_spine as (
    select date_val
    from unnest(generate_date_array('2011-01-01', '2023-12-31', interval 1 day)) as date_val
)

select
    date_val                              as date_day,
    extract(year from date_val)           as year,
    extract(quarter from date_val)        as quarter,
    extract(month from date_val)          as month_num,
    format_date('%B', date_val)           as month_name,
    extract(week from date_val)           as week_of_year,
    extract(dayofweek from date_val)      as day_of_week,
    format_date('%A', date_val)           as day_name,
    date_trunc(date_val, month)           as first_day_of_month,
    date_trunc(date_val, quarter)         as first_day_of_quarter,
    date_trunc(date_val, year)            as first_day_of_year
from date_spine
