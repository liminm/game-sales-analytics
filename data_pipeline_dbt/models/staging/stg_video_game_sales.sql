with raw_data as (

    -- pull in every column from the raw video_game_sales source
    select *
{#    from {{ source('raw', 'video_game_sales') }}#}
  from `data-eng-zcamp-liminm.data_eng_zcamp_liminm_bq_bucket.video_game_sales`

)

select

    -- cast the CSV Rank column to an integer
    cast(Rank as INT64) as rank,

    -- preserve the game name as a string
    Name as name,

    -- preserve the platform as a string
    Platform as platform,

    -- cast the Year column to an integer
    cast(Year as INT64) as year,

    -- preserve the genre as a string
    Genre as genre,

    -- preserve the publisher as a string
    Publisher as publisher,

    -- cast each regional sales column to a float
    cast(NA_Sales    as FLOAT64) as na_sales,
    cast(EU_Sales    as FLOAT64) as eu_sales,
    cast(JP_Sales    as FLOAT64) as jp_sales,
    cast(Other_Sales as FLOAT64) as other_sales,
    cast(Global_Sales as FLOAT64) as global_sales

from raw_data

-- remove any records missing the core identifying fields
where
  Name     is not null
  and Platform is not null
  and Year     is not null
