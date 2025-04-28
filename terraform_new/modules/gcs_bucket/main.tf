# Random suffix to guarantee global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# Bucket with environment and random suffix in name
resource "google_storage_bucket" "this" {
  name          = format("%s-%s-%s", var.bucket_prefix, var.environment, random_id.suffix.hex)
  location      = var.location
  project       = var.project_id
  force_destroy = var.force_destroy

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.delete_after_days
    }
  }

  labels = {
    environment = var.environment
    team        = "data-engineering"
  }
}
