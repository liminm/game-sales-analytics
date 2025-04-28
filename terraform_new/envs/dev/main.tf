# Call storage module
module "raw_bucket" {
  source      = "../../modules/gcs_bucket"
  project_id  = var.project_id
  bucket_prefix = "raw"
  location    = var.region
  environment = var.environment
}

# Call dataset module
module "warehouse" {
  source       = "../../modules/bigquery_dataset"
  project_id   = var.project_id
  dataset_name = "data_warehouse"
  location     = var.bq_location
  environment  = var.environment
}

# Service account
module "pipeline_sa" {
  source      = "../../modules/iam_bindings"
  project_id  = var.project_id
  service_account_name = "data-pipeline"
  roles = [
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
  ]
}

# Dataproc cluster
# module "dataproc_cluster" {
#   source      = "../../modules/dataproc_cluster"
#   project_id  = var.project_id
#   region      = var.region
#   service_account_email = module.pipeline_sa.email
#   name_prefix = "data-pipeline"
#   environment = var.environment
# }

module "dataproc_cluster" {
  source                = "../../modules/dataproc_cluster"
  project_id            = var.project_id                # from envs/dev/variables.tf or terraform.tfvars
  region                = var.region
  name_prefix           = "data-pipeline"
  environment           = var.environment               # e.g. "dev"
  service_account_email = module.pipeline_sa.email      # from your IAM module output
  subnet                = "projects/${var.project_id}/regions/${var.region}/subnetworks/my-subnet"
  master_machine_type   = "n1-standard-8"
  worker_machine_type   = "n1-standard-4"
  worker_count          = 3
}
