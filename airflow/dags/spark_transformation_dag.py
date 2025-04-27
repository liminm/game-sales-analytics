from datetime import datetime, timedelta

from airflow import DAG
from airflow.decorators import task
from airflow.providers.google.cloud.operators.dataproc import DataprocSubmitJobOperator


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

INPUT_PATH = f"gs://{BUCKET}/raw/green_tripdata_2019-01.csv"
OUTPUT_PATH = f"gs://{BUCKET}/processed/green_tripdata_2019-01"
SCRIPT_PATH = f"gs://{BUCKET}/code/spark_transformation.py"


with DAG(
    dag_id="taskflow_spark_transformation_dag",
    default_args=DEFAULT_ARGS,
    schedule_interval="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    description="Submit Spark job to Dataproc using TaskFlow API",
) as dag:

    @task
    def build_spark_job():
        return {
            "reference": {
                "project_id": PROJECT_ID
            },
            "placement": {
                "cluster_name": CLUSTER_NAME
            },
            "pyspark_job": {
                "main_python_file_uri": SCRIPT_PATH,
                "args": [INPUT_PATH, OUTPUT_PATH],
            },
        }

    @task
    def submit_job(job_config: dict):
        return DataprocSubmitJobOperator(
            task_id="submit_spark_job",
            job=job_config,
            region=REGION,
            project_id=PROJECT_ID,
        ).execute({})

    job_spec = build_spark_job()
    submit_job(job_spec)
