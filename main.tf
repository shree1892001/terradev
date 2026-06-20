terraform {
  required_version = ">= 1.5.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  required_files = [
    "scripts/bootstrap.sh",
    "stacks/devops-stack/docker-compose.yml",
    "stacks/devops-stack/prometheus.yml",
    "stacks/devops-stack/alertmanager.yml",
    "stacks/devops-stack/blackbox.yml",
    "stacks/devops-stack/grafana/provisioning/datasources/prometheus.yml",
    "stacks/devops-stack/grafana/provisioning/dashboards/dashboards.yml",
    "stacks/devops-stack/jenkins/Dockerfile",
    "stacks/devops-stack/jenkins/plugins.txt",
    "stacks/devops-stack/jenkins/casc.yaml",
    "stacks/plane-stack/docker-compose.yml",
    "stacks/huly-stack/docker-compose.yml",
    "stacks/huly-stack/nginx/nginx.conf"
  ]

  optional_files = [
    "configs/plane.env",
    "configs/huly.env",
    "configs/huly-nginx.conf",
    "configs/jenkins-credentials.json",
    "configs/jenkins-credentials.env",
    "scripts/validate-devops-metrics.sh"
  ]

  jenkins_init_files = tolist(fileset(path.module, "stacks/devops-stack/jenkins/init.groovy.d/*.groovy"))

  prometheus_rule_files = concat(
    tolist(fileset(path.module, "stacks/devops-stack/rules/*.yml")),
    tolist(fileset(path.module, "stacks/devops-stack/rules/*.yaml"))
  )

  grafana_dashboard_files = tolist(fileset(path.module, "stacks/devops-stack/grafana/provisioning/dashboards/json/*.json"))
}

resource "null_resource" "redberyl_platform" {
  triggers = merge(
    {
      for file_path in local.required_files :
      file_path => filesha256("${path.module}/${file_path}")
    },
    {
      for file_path in local.optional_files :
      file_path => length(fileset(path.module, file_path)) > 0 ? filesha256("${path.module}/${file_path}") : ""
    },
    {
      jenkins_init_hash       = sha256(join("", [for f in local.jenkins_init_files : filesha256("${path.module}/${f}")]))
      prometheus_rules_hash   = sha256(join("", [for f in local.prometheus_rule_files : filesha256("${path.module}/${f}")]))
      grafana_dashboards_hash = sha256(join("", [for f in local.grafana_dashboard_files : filesha256("${path.module}/${f}")]))
      enabled_stacks          = jsonencode(var.enabled_stacks)
      force_redeploy          = var.force_redeploy
    }
  )

  provisioner "local-exec" {
    command = "sudo bash scripts/bootstrap.sh \"${var.platform_dir}\" \"${var.server_ip}\" '${jsonencode(var.enabled_stacks)}'"
  }
}
