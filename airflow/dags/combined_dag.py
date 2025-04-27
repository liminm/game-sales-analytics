import logging
import os
import subprocess
import sys
import zipfile
from datetime import datetime, timedelta

from airflow import DAG
# from airflow.dags.spark_transformation_dag import OUTPUT_PATH
from airflow.decorators import task
from airflow.models import Variable
from airflow.operators.python import get_current_context
from airflow.providers.google.cloud.operators.dataproc import DataprocSubmitJobOperator
from airflow.providers.google.cloud.transfers.gcs_to_bigquery import GCSToBigQueryOperator
from google.cloud import storage

DEFAULT_ARGS = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

PROJECT_ID = "data-eng-zcamp-liminm"
REGION = "us-central1"
CLUSTER_NAME = "data-pipeline-cluster"
BUCKET = "data-eng-zcamp-liminm-bucket"
SCRIPT_PATH = f"gs://{BUCKET}/code/spark_transformation.py"
# OUTPUT_PATH = f"gs://{BUCKET}/processed/green_tripdata_2019-01"
OUTPUT_PATH = f"gs://{BUCKET}/processed/video_game_sales"

# dbt configuration (pulled from Airflow Variables or defaults)
DBT_PROJECT_DIR = Variable.get("DBT_PROJECT_DIR", default_var="/opt/airflow/dbt_project")
DBT_PROFILES_DIR = Variable.get("DBT_PROFILES_DIR", default_var="/opt/airflow/dbt_project/.dbt")

with DAG(
        dag_id="ingestion_and_spark_dag",
        default_args=DEFAULT_ARGS,
        start_date=datetime(2025, 1, 1),
        schedule_interval="@daily",
        catchup=False,
        description="Download data and run a Spark transformation on Dataproc",
) as dag:
    # @task()
    # def download_data() -> str:
    #     url = "https://github.com/DataTalksClub/nyc-tlc-data/releases/download/green/green_tripdata_2019-01.csv.gz"
    #     local_dir = "/tmp/data_files"
    #     os.makedirs(local_dir, exist_ok=True)
    #
    #     compressed_filepath = os.path.join(local_dir, "green_tripdata_2019-01.csv.gz")
    #     decompressed_filepath = os.path.join(local_dir, "green_tripdata_2019-01.csv")
    #
    #     logging.info(f"Downloading data from {url}")
    #     response = requests.get(url, timeout=120)
    #     response.raise_for_status()
    #
    #     # Write the compressed file
    #     with open(compressed_filepath, "wb") as f:
    #         f.write(response.content)
    #     logging.info(f"Compressed file downloaded to {compressed_filepath}")
    #
    #     # Decompress the file and save as CSV
    #     with gzip.open(compressed_filepath, "rb") as f_in:
    #         with open(decompressed_filepath, "wb") as f_out:
    #             f_out.write(f_in.read())
    #     logging.info(f"Decompressed CSV file saved to {decompressed_filepath}")
    #
    #     return decompressed_filepath

    @task
    def download_video_game_sales() -> str:
        # URL for the Kaggle dataset download endpoint
        url = "https://www.kaggle.com/api/v1/datasets/download/gregorut/videogamesales"
        # Local directory to save the zip
        local_dir = "/tmp/video_game_sales_data"
        extracted_dir = "/tmp/video_game_sales_data/vgsales.csv"
        os.makedirs(local_dir, exist_ok=True)

        # Full path for the downloaded zip file
        zip_path = os.path.join(local_dir, "video_game_sales.zip")

        logging.info(f"Downloading VideoGameSales.zip via curl from {url}")
        # Use curl to download the file
        subprocess.run([
            "curl",
            "-L",  # follow redirects
            "-o", zip_path,  # output file
            url
        ], check=True)

        logging.info(f"Downloaded zip to {zip_path}")

        # Unzip the contents
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(local_dir)
        logging.info(f"Extracted zip contents to {local_dir}")

        return extracted_dir


    @task()
    def upload_to_gcs(local_filepath: str) -> str:
        gcs_bucket = Variable.get("GCS_BUCKET_NAME", default_var=BUCKET)
        # gcs_blob_path = "raw/green_tripdata_2019-01.csv"
        gcs_blob_path = "raw/video_game_sales.csv"  # or dynamically set based on date

        storage_client = storage.Client()
        bucket = storage_client.bucket(gcs_bucket)
        blob = bucket.blob(gcs_blob_path)

        logging.info(f"Uploading {local_filepath} to gs://{gcs_bucket}/{gcs_blob_path}")
        blob.upload_from_filename(local_filepath, timeout=400)

        return f"gs://{gcs_bucket}/{gcs_blob_path}"


    @task()
    def build_spark_job(gcs_input_path: str):
        return {
            "reference": {"project_id": PROJECT_ID},
            "placement": {"cluster_name": CLUSTER_NAME},
            "pyspark_job": {
                "main_python_file_uri": SCRIPT_PATH,
                "args": [gcs_input_path, OUTPUT_PATH],
            },
        }


    @task()
    def submit_spark_job(job_config: dict):
        ctx = get_current_context()
        # Check that 'ti' is in the context
        if "ti" not in ctx:
            raise ValueError("TaskInstance 'ti' not found in context.")
        operator = DataprocSubmitJobOperator(
            task_id="submit_spark_job_operator",
            job=job_config,
            region=REGION,
            project_id=PROJECT_ID,
        )
        # Let Airflow handle context passing by calling execute
        return operator.execute(context=ctx)


    @task()
    def load_to_bigquery():
        return GCSToBigQueryOperator(
            task_id="gcs_to_bq",
            bucket=BUCKET,  # or Variable.get("GCS_BUCKET_NAME")
            source_objects=["processed/video_game_sales/cleaned/*.parquet"],  # or the exact file name
            destination_project_dataset_table=f"{PROJECT_ID}.data_eng_zcamp_liminm_bq_bucket.video_game_sales",
            source_format="PARQUET",
            write_disposition="WRITE_TRUNCATE",  # or WRITE_APPEND, depending on your use case
            autodetect=True,
        ).execute(context=get_current_context())


    @task()
    def run_dbt() -> str:
        """
        Change into the dbt project directory, verify connectivity,
        run models, then tests—streaming all output into the Airflow log.
        """
        # change into the dbt project directory
        # change into the dbt project directory so dbt picks up project/config implicitly
        os.chdir(DBT_PROJECT_DIR)

        # base dbt invocation
        dbt_cmd = ["dbt"]

        # install dbt deps if you have a packages.yml
        packages_file = os.path.join(DBT_PROJECT_DIR, "packages.yml")
        if os.path.isfile(packages_file):
            subprocess.run(dbt_cmd + ["deps"], check=True)

        def _run_dbt_step(step: list[str]):
            logging.info("Running: %s", " ".join(step))
            proc = subprocess.run(step, text=True, capture_output=True)
            logging.info(proc.stdout)
            logging.error(proc.stderr)
            if proc.returncode != 0:
                raise subprocess.CalledProcessError(proc.returncode, step)

        # quick connectivity check
        _run_dbt_step(dbt_cmd + ["debug"])

        # run all models
        _run_dbt_step(dbt_cmd + ["run"])

        # run tests
        _run_dbt_step(dbt_cmd + ["test"])

        logging.info("dbt run & test completed")
        return "dbt_completed"

    # TaskFlow chain using XComArg objects:
    # download_task = download_data()
    download_task = download_video_game_sales()
    upload_task = upload_to_gcs(download_task)
    job_config_task = build_spark_job(upload_task)
    submit_task = submit_spark_job(job_config_task)
    load_bq_task = load_to_bigquery()
    dbt_finished = run_dbt()

    # download_video_game_sales_task >> download_task >> upload_task >> job_config_task >> submit_task >> load_bq_task >> dbt_finished
    download_task >> upload_task >> job_config_task >> submit_task >> load_bq_task >> dbt_finished


# local_file = download_data()
# gcs_path = upload_to_gcs(local_file)
# job_config = build_spark_job(gcs_path)
# submit_job(job_config)
