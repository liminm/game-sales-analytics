# outputs.tf

output "bucket_name" {
  description = "The name of the GCS bucket"
  value       = google_storage_bucket.data_lake_bucket.name
}

output "bigquery_dataset_id" {
  description = "The ID of the BigQuery dataset"
  value       = google_bigquery_dataset.data_warehouse.dataset_id
}

output "service_account_email" {
  description = "The email of the created service account"
  value       = google_service_account.data_pipeline_sa.email
}


# compute the full Docker registry URI for pushing and pulling
output "airflow_repo_uri" {
  description = "Docker push/pull URI for the Airflow repo"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.airflow_docker_repo.repository_id}"
}


# connection string used by the Cloud SQL Proxy
output "cloud_sql_connection_name" {
  value = google_sql_database_instance.airflow_postgres.connection_name
}

# postgres URL Airflow will use (password redacted here)
output "airflow_sqlalchemy_url" {
  value = "postgresql+psycopg2://airflow:<PASSWORD>@localhost:5432/airflow"
}



