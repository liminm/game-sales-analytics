resource "google_dataproc_cluster" "spark_cluster" {
  name    = "data-pipeline-cluster"
  project = var.gcp_project_id
  region  = var.gcp_region

  depends_on = [google_project_service.dataproc]

  cluster_config {
    gce_cluster_config {
      zone            = "us-central1-a"
      service_account = google_service_account.data_pipeline_sa.email
    }

    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2"
      disk_config {
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 2
      machine_type  = "e2-standard-2"
      disk_config {
        boot_disk_size_gb = 30
      }
    }
  }
  # lifecycle {
  #   ignore_changes = [
  #     cluster_config[0].gce_cluster_config[0].internal_ip_only
  #   ]
  # }

}
