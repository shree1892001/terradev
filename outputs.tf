output "jenkins_url" {
  value = "http://${var.server_ip}:8080"
}

output "grafana_url" {
  value = "http://${var.server_ip}:3000"
}

output "prometheus_url" {
  value = "http://${var.server_ip}:9090"
}

output "alertmanager_url" {
  value = "http://${var.server_ip}:9093"
}


output "plane_url" {
  value = "http://${var.server_ip}:8001"
}

output "huly_url" {
  value = "http://${var.server_ip}:9898"
}

output "huly_kvs_url" {
  value = "http://${var.server_ip}:8094"
}

output "credentials_command" {
  value = "sudo cat ${var.platform_dir}/credentials.txt"
}
