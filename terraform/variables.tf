# variables.tf

variable "gcp_project_id" {
  type        = string
  description = "The ID of the GCP project where resources will be created."
}
#
# variable "gcp_region" {
#   type        = string
#   description = "Region for GCP resources."
#   default     = "europe-west4"
# }

variable "gcp_region" {
  type        = string
  description = "Region for GCP resources."
  default     = "us-central1"
}

variable "gcs_bucket_name" {
  type        = string
  description = "Name of the GCS bucket to create (must be globally unique)."
}

variable "bq_dataset_name" {
  type        = string
  description = "Name of the BigQuery dataset."
}

variable "gcp_location" {
  type        = string
  description = "Location for BigQuery dataset (e.g., US, EU)."
  default     = "EU"
}

variable "service_account_name" {
  type        = string
  description = "Name of the service account."
  default     = "data-pipeline-sa"
}
