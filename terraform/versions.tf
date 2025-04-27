# # versions.tf
# terraform {
#   required_version = ">= 1.11.1"
#
#   required_providers {
#     google = {
#       source  = "hashicorp/google"
#       version = "~> 4.0"
#     }
#   }
# }
#
# provider "google" {
#   project = var.gcp_project_id
#   region  = var.gcp_region
# }

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}