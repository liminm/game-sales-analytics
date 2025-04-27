import logging
import os
from datetime import datetime, timedelta

import requests
from airflow.decorators import dag, task
from airflow.models import Variable
from google.cloud import storage


DEFAULT_ARGS = {
    "owner": "airflow",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


@dag(
    dag_id="taskflow_ingestion_dag1",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    description="Ingest data from a public source into GCS using TaskFlow API",
)
def data_ingestion_dag():
    """
    ### Data Ingestion DAG
    This DAG downloads a CSV file from a public source and uploads it to GCS.
    It uses the TaskFlow API for clearer and more maintainable code.
    """

    @task()
    def download_data() -> str:
        """
        ### Download Data Task
        Downloads a file from a public URL and saves it to a temporary local path.

        Returns:
            str: Path to the downloaded local file.
        """
        # You could store this URL in an Airflow Variable or in code for simplicity
        url = "https://raw.githubusercontent.com/DataTalksClub/nyc-tlc-data/master/green_tripdata_2019-01.csv"
        url = "https://github.com/DataTalksClub/nyc-tlc-data/releases/download/green/green_tripdata_2019-01.csv.gz"

        # Create a local directory to store temp files if needed
        local_dir = "/tmp/data_files"
        os.makedirs(local_dir, exist_ok=True)

        filename = "green_tripdata_2019-01.csv.gz"
        local_filepath = os.path.join(local_dir, filename)

        logging.info(f"Downloading data from {url}")
        response = requests.get(url, timeout=120)
        response.raise_for_status()  # Raise an error for 4XX/5XX responses

        with open(local_filepath, "wb") as f:
            f.write(response.content)

        logging.info(f"File downloaded to {local_filepath}")
        return local_filepath

    @task()
    def upload_to_gcs(local_filepath: str) -> None:
        """
        ### Upload to GCS Task
        Uploads the downloaded file from the local path to the specified GCS bucket.

        Args:
            local_filepath (str): Local path to the file that needs to be uploaded.
        """
        # Best practice: use Airflow Variables or environment variables
        # for bucket names and other configs
        gcs_bucket = Variable.get("GCS_BUCKET_NAME", default_var="data-eng-zcamp-liminm-bucket")
        gcs_blob_path = "raw/green_tripdata_2019-01.csv"  # or dynamically set based on date

        # Initialize the Google Cloud Storage client
        storage_client = storage.Client()  # Will use credentials from GOOGLE_APPLICATION_CREDENTIALS or ADC
        bucket = storage_client.bucket(gcs_bucket)
        blob = bucket.blob(gcs_blob_path)

        logging.info(f"Uploading {local_filepath} to gs://{gcs_bucket}/{gcs_blob_path}")
        blob.upload_from_filename(local_filepath, timeout=400)

        logging.info("Upload complete.")

    # TaskFlow graph
    file_path = download_data()
    upload_to_gcs(file_path)

# Instantiate the DAG
dag = data_ingestion_dag()