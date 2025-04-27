# spark/spark_transformation.py

# import sys
# from pyspark.sql import SparkSession
# from pyspark.sql.functions import col, to_date
#
# def main(input_path: str, output_path: str):
#     """
#     PySpark job to read raw NYC Taxi data from GCS, clean/transform it,
#     and write the results back to GCS (or to BigQuery).
#     Args:
#         input_path (str): GCS path to the input data (e.g., gs://bucket/raw/*.csv)
#         output_path (str): GCS path or BigQuery table to store processed data.
#     """
#     spark = SparkSession.builder \
#         .appName("NYC_Taxi_Transformation") \
#         .getOrCreate()
#
#     # 1. Read data
#     df = spark.read \
#         .option("header", "true") \
#         .option("inferSchema", "true") \
#         .csv(input_path)
#
#     # 2. Example transformations
#     #    - Convert date/time columns to Spark Timestamp or Date.
#     #    - Filter out any null or invalid data if needed.
#     df_cleaned = df \
#         .withColumn("lpep_pickup_datetime", to_date(col("lpep_pickup_datetime"), "yyyy-MM-dd HH:mm:ss")) \
#         .withColumn("lpep_dropoff_datetime", to_date(col("lpep_dropoff_datetime"), "yyyy-MM-dd HH:mm:ss")) \
#         .filter(col("passenger_count") > 0)
#
#     # 3. Write the result back to GCS in Parquet format
#     #    Alternatively, write directly to BigQuery using the spark-bigquery connector.
#     df_cleaned.write \
#         .mode("overwrite") \
#         .parquet(output_path)
#
#     spark.stop()
#
# if __name__ == "__main__":
#     """
#     Example usage:
#     spark-submit spark_transformation.py gs://my-bucket/raw/green_tripdata_2019-01.csv gs://my-bucket/processed/green_tripdata_2019-01
#     or if writing to BigQuery:
#     spark-submit --jars="gs://spark-lib/bigquery/spark-bigquery-latest_2.12.jar" \
#         spark_transformation.py gs://my-bucket/raw/*.csv bigquery://my-project.my_dataset.my_table
#     """
#     if len(sys.argv) != 3:
#         print("Usage: spark_transformation.py <input_path> <output_path>")
#         sys.exit(-1)
#
#     input_path_arg = sys.argv[1]
#     output_path_arg = sys.argv[2]
#     main(input_path_arg, output_path_arg)

import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, sum as _sum
from pyspark.sql.types import IntegerType, FloatType

def main(input_path: str, output_path: str):
    """
    PySpark job to read raw video game sales data from a CSV,
    clean/transform it, and write cleaned and aggregated datasets.

    Args:
        input_path (str): Path to the input CSV file(s) (e.g., gs://bucket/raw/*.csv)
        output_path (str): GCS path or local directory to store processed data.
                           Two subfolders will be created:
                           - cleaned: cleaned individual records in Parquet
                           - genre_sales: aggregated sales by genre in Parquet
    """
    spark = SparkSession.builder \
        .appName("VideoGameSales_Transformation") \
        .getOrCreate()

    # 1. Read raw CSV data with header and inferred schema
    df = spark.read \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .csv(input_path)

    # 2. Cast columns to proper types and filter invalid rows
    df_cleaned = (
        df
        # Cast Year to integer
        .withColumn("Year", col("Year").cast(IntegerType()))
        # Cast sales columns to float
        .withColumn("NA_Sales", col("NA_Sales").cast(FloatType()))
        .withColumn("EU_Sales", col("EU_Sales").cast(FloatType()))
        .withColumn("JP_Sales", col("JP_Sales").cast(FloatType()))
        .withColumn("Other_Sales", col("Other_Sales").cast(FloatType()))
        .withColumn("Global_Sales", col("Global_Sales").cast(FloatType()))
        # Remove records missing key fields
        .filter(
            col("Name").isNotNull() &
            col("Platform").isNotNull() &
            col("Year").isNotNull()
        )
    )

    # 3. Write cleaned data to Parquet
    cleaned_path = f"{output_path.rstrip('/')}" + "/cleaned"
    df_cleaned.write \
        .mode("overwrite") \
        .parquet(cleaned_path)

    # 4. Aggregate sales by Genre
    df_genre_sales = (
        df_cleaned
        .groupBy("Genre")
        .agg(
            _sum("NA_Sales").alias("Total_NA_Sales"),
            _sum("EU_Sales").alias("Total_EU_Sales"),
            _sum("JP_Sales").alias("Total_JP_Sales"),
            _sum("Other_Sales").alias("Total_Other_Sales"),
            _sum("Global_Sales").alias("Total_Global_Sales")
        )
    )

    # 5. Write aggregated genre sales to Parquet
    agg_path = f"{output_path.rstrip('/')}" + "/genre_sales"
    df_genre_sales.write \
        .mode("overwrite") \
        .parquet(agg_path)

    # Stop the Spark session
    spark.stop()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: spark_video_game_transformation.py <input_path> <output_path>")
        sys.exit(-1)

    input_path_arg = sys.argv[1]
    output_path_arg = sys.argv[2]
    main(input_path_arg, output_path_arg)
