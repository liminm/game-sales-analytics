# GCP project
variable "project_id" {
  type        = string
  description = "GCP project id (e.g. data‑eng‑zcamp‑liminm)"
}

# Region
variable "region" {
  type        = string
  description = "Compute / Dataproc region"
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+[0-9]$", var.region))
    error_message = "Region must look like 'us-central1'."
  }
}

