
{#  File: models/marts/fact_video_game_summary.sql#}
{#  Description: Yearly summary of video game sales#}
{#  Builds off stg_video_game_sales, aggregating count and sales metrics.#}
with vgs as (
    select *
    from {{ ref('stg_video_game_sales') }}
)

select
    year,
    count(*)                    as num_games,
    sum(global_sales)           as total_global_sales,
    avg(global_sales)           as avg_global_sales,
    sum(na_sales)               as total_na_sales,
    sum(eu_sales)               as total_eu_sales,
    sum(jp_sales)               as total_jp_sales,
    sum(other_sales)            as total_other_sales
from vgs
group by year
order by year
