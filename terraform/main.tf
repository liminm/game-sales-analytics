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
  # password = random_password.airflow_db_password.result
    password = var.airflow_db_password
}

# give the VM’s service account permission to connect via Cloud SQL Proxy
resource "google_project_iam_member" "vm_cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${data.google_service_account.airflow.email}"
}

# Create a Service Account via the beta provider
resource "google_service_account" "airflow_proxy" {
  provider     = google-beta
  account_id   = "airflow-proxy"
  display_name = "Airflow Cloud SQL Proxy Service Account"
  project      = var.gcp_project_id
}

# Grant it the client role
resource "google_project_iam_member" "proxy_cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.airflow_proxy.email}"
}


# --- leave the key resource exactly as is -------------------
resource "google_service_account_key" "airflow_proxy_key" {
  service_account_id = google_service_account.airflow_proxy.name
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "local_file" "sa_key_json" {
  filename        = "../.gcp/gcp_sa_key.json"
  file_permission = "0440"

  # decode the blob that the provider returns
  content = base64decode(
    google_service_account_key.airflow_proxy_key.private_key
  )
}

# define the VM blueprint that installs Docker, pulls your repo, then runs docker-compose
resource "google_compute_instance_template" "airflow" {
  name    = "airflow-template"
  project = var.gcp_project_id
  region  = var.gcp_region

  # small production-ready machine; adjust as needed
  machine_type = "e2-standard-2"


  # define the boot disk (50 GB SSD from Debian-12 family)
  disk {
    auto_delete  = true
    boot         = true
    source_image = "projects/debian-cloud/global/images/family/debian-12"
    disk_size_gb = 50
    disk_type    = "pd-ssd"
  }


  # let the VM act as your data-pipeline SA for GCS, BQ, Dataproc, Cloud SQL
  service_account {
    email  = google_service_account.data_pipeline_sa.email
    scopes = ["cloud-platform"]
  }

  # tag instances “airflow” for firewall rules
  tags = ["airflow"]

  network_interface {
    network    = "default"
    # assign external IP so you can reach 8080
    access_config {}
  }

  metadata = {
    # runs on first boot – installs Docker + Compose, clones your repo, then starts Airflow
    startup-script = <<-EOF
      #!/usr/bin/env bash

      # install Docker, Compose, git & curl
      apt-get update -y
      apt-get install -y docker.io docker-compose git curl

      # let Docker talk to Artifact Registry
      gcloud auth configure-docker ${var.gcp_region}-docker.pkg.dev --quiet

      # grab your repo (HTTPS clone; replace with SSH if you’ve set up keys)
      rm -rf /opt/airflow
      git clone --depth 1 https://github.com/liminm/game-sales-analytics /opt/airflow

      # start the Airflow stack
      cd /opt/airflow
      docker-compose up -d
    EOF
  }
}





# create a regional MIG so Terraform can scale or heal your Airflow VMs
resource "google_compute_region_instance_group_manager" "airflow_mig" {
  name               = "airflow-mig"
  project            = var.gcp_project_id
  region             = var.gcp_region

  # reference the template above
  version {
    instance_template = google_compute_instance_template.airflow.self_link
  }

  # VM names will start with “airflow-”
  base_instance_name = "airflow"
  # start with one VM; you can increase later
  target_size        = 1
}


# allow SSH (22) and Airflow UI (8080) from anywhere
resource "google_compute_firewall" "airflow_allow" {
  name    = "airflow-allow"
  project = var.gcp_project_id
  network = "default"

  # open ports
  allow {
    protocol = "tcp"
    ports    = ["22", "8080"]
  }

  # be careful in prod—restrict this CIDR if needed
  source_ranges = ["0.0.0.0/0"]

  # apply to VMs tagged “airflow”
  target_tags = ["airflow"]
}



# Allow the credentials mounted in the Airflow containers (airflow-proxy@…)
# to PUT new files into the raw-data bucket.
resource "google_storage_bucket_iam_member" "proxy_can_write_to_bucket" {
  bucket = google_storage_bucket.data_lake_bucket.name          # <- your bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.airflow_proxy.email}"
}


resource "google_project_iam_member" "proxy_dataproc_editor" {
  project = var.gcp_project_id
  role    = "roles/dataproc.editor"           # ← valid role
  member  = "serviceAccount:${google_service_account.airflow_proxy.email}"
}

resource "google_project_iam_member" "proxy_bq_jobuser" {
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.airflow_proxy.email}"
}

resource "google_bigquery_dataset_iam_member" "proxy_bq_dataeditor" {
  project  = var.gcp_project_id
  dataset_id = google_bigquery_dataset.data_warehouse.dataset_id
  role     = "roles/bigquery.dataEditor"
  member   = "serviceAccount:${google_service_account.airflow_proxy.email}"
}

# ─── Artifact Registry: allow pushes ────────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "airflow_repo_writer" {
  project    = var.gcp_project_id
  location   = var.gcp_region                    # "us-central1"
  repository = google_artifact_registry_repository.airflow_docker_repo.repository_id
  role       = "roles/artifactregistry.writer"

  # 👇 the principal that runs `docker push`
  member     = "serviceAccount:l6194005@data-eng-zcamp-liminm.iam.gserviceaccount.com"
}

# ─── VM may pull any tags from the repo ────────────────────────────────────────
resource "google_artifact_registry_repository_iam_member" "airflow_repo_reader" {
  project    = var.gcp_project_id
  location   = var.gcp_region                       # us-central1
  repository = google_artifact_registry_repository.airflow_docker_repo.repository_id
  role       = "roles/artifactregistry.reader"

  member     = "serviceAccount:l6194005@data-eng-zcamp-liminm.iam.gserviceaccount.com"
}
