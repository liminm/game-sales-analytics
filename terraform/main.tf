# main.tf

resource "google_storage_bucket" "data_lake_bucket" {
  name          = var.gcs_bucket_name
  project       = var.gcp_project_id
  location      = var.gcp_region
  force_destroy = true  # Optional, allows bucket to be destroyed with Terraform

  uniform_bucket_level_access = true

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30  # e.g., delete objects older than 30 days
    }
  }
}

resource "google_storage_bucket_object" "spark_transformation" {
  name   = "code/spark_transformation.py"  # This is the path inside the bucket
  bucket = google_storage_bucket.data_lake_bucket.name
  source = "spark/spark_transformation.py"       # Local file path relative to the Terraform config directory
  content_type = "text/x-python"           # Optional: set an appropriate content type
}


resource "google_bigquery_dataset" "data_warehouse" {
  dataset_id                  = var.bq_dataset_name
  project                     = var.gcp_project_id
  location                    = var.gcp_location
  default_table_expiration_ms = null
  description                 = "Data Warehouse dataset for the data pipeline"

  labels = {
    environment = "dev"
    team        = "data-engineering"
  }
}

resource "google_service_account" "data_pipeline_sa" {
  account_id   = var.service_account_name
  display_name = "Data Pipeline Service Account"
  project      = var.gcp_project_id
}

# Example of attaching roles to the service account
# Add or remove roles as needed for your pipeline
resource "google_project_iam_member" "data_pipeline_sa_storage_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

resource "google_project_iam_member" "data_pipeline_sa_bigquery_admin" {
  project = var.gcp_project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

resource "google_project_iam_member" "data_pipeline_sa_dataproc_worker" {
  project = var.gcp_project_id
  role    = "roles/dataproc.worker"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

resource "google_project_iam_member" "data_pipeline_sa_dataproc_editor" {
  project = var.gcp_project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.data_pipeline_sa.email}"
}

resource "google_project_service" "dataproc" {
  project = var.gcp_project_id
  service = "dataproc.googleapis.com"
  disable_on_destroy = false
}


data "google_service_account" "airflow" {
  account_id = "airflow"
  project    = var.gcp_project_id
}


resource "google_project_iam_member" "storage_object_viewer" {
  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${data.google_service_account.airflow.email}"
}

resource "google_project_iam_member" "storage_object_creator" {
  project = var.gcp_project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${data.google_service_account.airflow.email}"
}


# enable the Artifact Registry API in the project
resource "google_project_service" "artifactregistry" {
  # project ID variable you already use elsewhere
  project = var.gcp_project_id
  # name of the API
  service = "artifactregistry.googleapis.com"
  # keep it enabled even if someone runs terraform destroy
  disable_on_destroy = false
}


# create a docker-type Artifact Registry repo in the chosen region
resource "google_artifact_registry_repository" "airflow_docker_repo" {
  # repo ID must be unique within the project
  repository_id = "airflow-docker"
  # one of DOCKER | MAVEN | NPM …
  format        = "DOCKER"
  # project & region variables you already have
  project       = var.gcp_project_id
  location      = var.gcp_region
  # optional descriptive labels
  labels = {
    environment = "dev"
    team        = "data-engineering"
  }
  depends_on = [google_project_service.artifactregistry]
}

# enable Cloud SQL Admin API so Terraform can create the instance
resource "google_project_service" "sqladmin" {
  # project ID variable you already have
  project = var.gcp_project_id
  # name of the service
  service = "sqladmin.googleapis.com"
  # do not disable on destroy
  disable_on_destroy = false
}


# secure random password for the airflow DB user
resource "random_password" "airflow_db_password" {
  # 16-char random pass incl. symbols
  length  = 16
  special = true
}

# Cloud SQL Postgres instance sized for dev / PoC
resource "google_sql_database_instance" "airflow_postgres" {
  # unique instance name
  name             = "airflow-postgres"
  # project + region variables
  project          = var.gcp_project_id
  region           = var.gcp_region
  # Postgres version
  database_version = "POSTGRES_15"

  # block until API is enabled
  depends_on = [google_project_service.sqladmin]

  settings {
    # shared-core machine good enough for small Airflow
    tier = "db-g1-small"

    # turn off public IP if you plan to use Private Service Connect
    ip_configuration {
      ipv4_enabled = true
    }

    # 10 GB storage with auto-grow
    disk_size = 10
    disk_type = "PD_SSD"
    activation_policy = "ALWAYS"
    # backup & maintenance windows (optional)
  }
}

# create an empty database named airflow
resource "google_sql_database" "airflow" {
  name     = "airflow"
  instance = google_sql_database_instance.airflow_postgres.name
}

# create the airflow DB user
resource "google_sql_user" "airflow" {
  name     = "airflow"
  instance = google_sql_database_instance.airflow_postgres.name
  password = random_password.airflow_db_password.result
}

# give the VM’s service account permission to connect via Cloud SQL Proxy
resource "google_project_iam_member" "vm_cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${data.google_service_account.airflow.email}"
}
