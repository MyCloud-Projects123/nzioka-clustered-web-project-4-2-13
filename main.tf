provider "google" {            
  project = "project-164d57d1-aea9-4a08-866"
  region  = "us-central1"
}
resource "google_compute_instance_template" "web_server_template" {
  name         = "web-server-template"
  machine_type = "e2-micro"

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "default"
    access_config {} # This gives the servers public IP addresses
  }

  # The "Secret Sauce": This script installs the web server automatically
  metadata_startup_script = "apt-get update && apt-get install -y apache2"

  tags = ["http-server"]
}
# This is the "Factory Manager" that creates and maintains the herd
resource "google_compute_instance_group_manager" "web_server_group" {
  name               = "web-server-group"
  base_instance_name = "web-server"
  zone               = "us-central1-a"
  target_size        = 2 # We want a herd of 2 servers to start

  version {
    instance_template = google_compute_instance_template.web_server_template.id
  }
}
# 3. The health check
resource "google_compute_health_check" "auto_healing"{
  name = "auto-healing-check"
  http_health_check {
    port = "80"
 }
}
# This opens the door so people can see your website
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-traffic"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # This says "Allow anyone from the internet"
  source_ranges = ["0.0.0.0/0"] 
  
  # This makes sure only servers with the "http-server" tag are affected
  target_tags   = ["http-server"] 
}

# This tells Terraform to print the IP addresses of your herd
output "server_ips" {
  value = google_compute_instance_group_manager.web_server_group.instance_group
  description = "The link to your group of servers"
}
# 1. THE FRONT END (The IP Address people type in)
resource "google_compute_global_forwarding_rule" "default" {
  name       = "web-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
}

# 2. THE PROXY (The logic that handles the request)
resource "google_compute_target_http_proxy" "default" {
  name    = "web-proxy"
  url_map = google_compute_url_map.default.id
}

# 3. THE URL MAP (The routing table)
resource "google_compute_url_map" "default" {
  name            = "web-map"
  default_service = google_compute_backend_service.default.id
}

# 4. THE BACKEND SERVICE (The bridge to your "Herd")
resource "google_compute_backend_service" "default" {
  name        = "web-backend"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  backend {
    group = google_compute_instance_group_manager.web_server_group.instance_group
  }

  health_checks = [google_compute_health_check.auto_healing.id]
}
output "load_balancer_ip" {
  value = google_compute_global_forwarding_rule.default.ip_address
}


