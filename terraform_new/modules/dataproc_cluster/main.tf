# Use locals for common names and labels
locals {
  cluster_name = format("%s-%s", var.name_prefix, var.environment)
}

# Create a Dataproc Autoscaling policy (optional but recommended)
resource "google_dataproc_autoscaling_policy" "policy" {
  provider = google-beta

  location = var.region

  basic_algorithm {
    yarn_config {
      graceful_decommission_timeout = "300s"
    }
  }

  worker_config {
    min_instances = 2
    max_instances = 10
    weight        = 1
  }

  secondary_worker_config {
    min_instances = 0
    max_instances = 20
    weight        = 1
  }
}

# Dataproc cluster
resource "google_dataproc_cluster" "this" {
  name   = local.cluster_name
  region = var.region
  project = var.project_id

  lifecycle {
    ignore_changes = [cluster_config[0].software_config[0].properties]
  }

  cluster_config {
    autoscaling_config {
      policy_uri = google_dataproc_autoscaling_policy.policy.id
    }

    gce_cluster_config {
      service_account = var.service_account_email
      subnet_uri      = var.subnet
      tags            = ["dataproc", var.environment]
      metadata = {
        enable-oslogin = "TRUE"
      }
    }

    master_config {
      num_instances = 1
      machine_type  = var.master_machine_type
      disk_config {
        boot_disk_type   = "pd-ssd"
        boot_disk_size_gb = 50
      }
    }

    worker_config {
      num_instances = var.worker_count
      machine_type  = var.worker_machine_type
    }

    secondary_worker_config {
      num_instances = 0
      is_preemptible = true
    }

    software_config {
      image_version = "2.2-debian11"
      optional_components = ["JUPYTER"]
    }
  }
}
