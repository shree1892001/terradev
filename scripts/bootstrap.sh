#!/bin/bash
set -euo pipefail

PLATFORM_DIR="${1:-}"
SERVER_IP="${2:-}"
ENABLED_STACKS_JSON="${3:-}"

if [[ -z "${PLATFORM_DIR}" || -z "${SERVER_IP}" || -z "${ENABLED_STACKS_JSON}" ]]; then
  echo "Usage: bootstrap.sh <platform_dir> <server_ip> <enabled_stacks_json>" >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: bootstrap.sh must run as root. Use sudo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_MONITORING_NET="redberyl-monitoring-net"
PLANE_NET="plane-net"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

install_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Installing base packages"
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    ufw \
    jq \
    htop \
    net-tools \
    openssl \
    unzip
}

parse_enabled_stacks() {
  if ! echo "${ENABLED_STACKS_JSON}" | jq -e 'type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null; then
    echo "ERROR: enabled_stacks must be a non-empty JSON array of strings." >&2
    exit 1
  fi

  mapfile -t ENABLED_STACKS < <(echo "${ENABLED_STACKS_JSON}" | jq -r '.[]')

  local stack
  for stack in "${ENABLED_STACKS[@]}"; do
    case "${stack}" in
      devops|plane|huly) ;;
      *)
        echo "ERROR: unsupported stack '${stack}'. Supported stacks: devops, plane, huly." >&2
        exit 1
        ;;
    esac
  done
}

stack_enabled() {
  local wanted="$1"
  local stack
  for stack in "${ENABLED_STACKS[@]}"; do
    [[ "${stack}" == "${wanted}" ]] && return 0
  done
  return 1
}

install_docker() {
  log "Installing Docker Engine and Compose plugin if needed"

  if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
      chmod a+r /etc/apt/keyrings/docker.asc
    fi

    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif ! docker compose version >/dev/null 2>&1; then
    apt-get update
    apt-get install -y docker-compose-plugin
  fi

  systemctl enable docker
  systemctl start docker
  docker version >/dev/null
  docker compose version >/dev/null
}

configure_firewall() {
  log "Configuring UFW firewall"
  ufw allow 22/tcp
  ufw allow 8080/tcp
  ufw allow 50000/tcp
  ufw allow 3000/tcp
  ufw allow 9090/tcp
  ufw allow 9093/tcp
  ufw allow 18080/tcp
  ufw allow 9121/tcp
  ufw allow 9187/tcp
  ufw allow 8001/tcp
  ufw allow 9898/tcp
  ufw allow 8094/tcp
  ufw --force enable
}

prepare_directories() {
  log "Preparing platform directories and shared Docker networks"
  mkdir -p "${PLATFORM_DIR}"
  chmod 755 "${PLATFORM_DIR}"

  docker network inspect "${SHARED_MONITORING_NET}" >/dev/null 2>&1 || docker network create "${SHARED_MONITORING_NET}" >/dev/null
  docker network inspect "${PLANE_NET}" >/dev/null 2>&1 || docker network create "${PLANE_NET}" >/dev/null
}

copy_stack() {
  local name="$1"
  local source="${PROJECT_DIR}/stacks/${name}-stack"
  local target="${PLATFORM_DIR}/${name}-stack"

  if [[ ! -d "${source}" ]]; then
    echo "ERROR: stack source directory not found: ${source}" >&2
    exit 1
  fi

  mkdir -p "${target}"
  cp -a "${source}/." "${target}/"
}

compose_pull_up() {
  local name="$1"
  log "Pulling and starting ${name} stack"

  if [[ "${name}" == "devops" ]] && stack_enabled plane; then
    (
      cd "${PLATFORM_DIR}/${name}-stack"
      COMPOSE_PROFILES=plane-monitoring docker compose pull --ignore-buildable
      COMPOSE_PROFILES=plane-monitoring docker compose up -d --build
    )
  else
    (
      cd "${PLATFORM_DIR}/${name}-stack"
      docker compose pull --ignore-buildable
      docker compose up -d --build
    )
  fi
}

ensure_devops_env() {
  local env_file="${PLATFORM_DIR}/devops-stack/.env"
  local grafana_password=""
  local jenkins_password=""
  local postgres_password=""
  local postgres_db="redberyl"
  local postgres_user="postgres"

  if [[ -f "${env_file}" ]]; then
    grafana_password="$(grep -E '^GRAFANA_ADMIN_PASSWORD=' "${env_file}" | head -n1 | cut -d= -f2- || true)"
    jenkins_password="$(grep -E '^JENKINS_ADMIN_PASSWORD=' "${env_file}" | head -n1 | cut -d= -f2- || true)"
    postgres_password="$(grep -E '^POSTGRES_PASSWORD=' "${env_file}" | head -n1 | cut -d= -f2- || true)"
    postgres_db="$(grep -E '^POSTGRES_DB=' "${env_file}" | head -n1 | cut -d= -f2- || true)"
    postgres_user="$(grep -E '^POSTGRES_USER=' "${env_file}" | head -n1 | cut -d= -f2- || true)"
  fi

  [[ -z "${grafana_password}" ]] && grafana_password="$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24)"
  [[ -z "${jenkins_password}" ]] && jenkins_password="$(openssl rand -base64 24 | tr -d '=+/\n' | cut -c1-24)"
  [[ -z "${postgres_password}" ]] && postgres_password="$(openssl rand -base64 32 | tr -d '=+/\n' | cut -c1-32)"
  [[ -z "${postgres_db}" ]] && postgres_db="redberyl"
  [[ -z "${postgres_user}" ]] && postgres_user="postgres"

  cat > "${env_file}" <<EOF_ENV
GRAFANA_ADMIN_PASSWORD=${grafana_password}
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=${jenkins_password}
POSTGRES_DB=${postgres_db}
POSTGRES_USER=${postgres_user}
POSTGRES_PASSWORD=${postgres_password}
EOF_ENV
  chmod 600 "${env_file}"

  GRAFANA_ADMIN_PASSWORD="${grafana_password}"
  JENKINS_ADMIN_PASSWORD="${jenkins_password}"
  POSTGRES_DB="${postgres_db}"
  POSTGRES_USER="${postgres_user}"
  POSTGRES_PASSWORD="${postgres_password}"
}

ensure_jenkins_credentials() {
  local source_env="${PROJECT_DIR}/configs/jenkins-credentials.env"
  local source_env_example="${PROJECT_DIR}/configs/jenkins-credentials.env.example"
  local source_registry="${PROJECT_DIR}/configs/jenkins-credentials.json"
  local source_registry_example="${PROJECT_DIR}/configs/jenkins-credentials.json.example"

  local target_dir="${PLATFORM_DIR}/devops-stack/jenkins"
  local target_env="${target_dir}/jenkins-credentials.env"
  local target_registry="${target_dir}/jenkins-credentials.json"
  local hash_file="${target_dir}/.jenkins-credentials.sha256"

  mkdir -p "${target_dir}"

  local old_hash=""
  if [[ -f "${hash_file}" ]]; then
    old_hash="$(cat "${hash_file}" || true)"
  fi

  if [[ -f "${source_registry}" ]]; then
    cp "${source_registry}" "${target_registry}"
  elif [[ -f "${source_registry_example}" ]]; then
    cp "${source_registry_example}" "${target_registry}"
  else
    echo '{"credentials":[]}' > "${target_registry}"
  fi

  if [[ -f "${source_env}" ]]; then
    cp "${source_env}" "${target_env}"
  elif [[ -f "${source_env_example}" ]]; then
    cp "${source_env_example}" "${target_env}"
  else
    cat > "${target_env}" <<'EOF_ENV'
# Jenkins dynamic credential values.
# Empty values are skipped by Jenkins dynamic credential seeder.
EOF_ENV
  fi

  chmod 600 "${target_env}"
  chmod 600 "${target_registry}"

  local new_hash=""
  new_hash="$(sha256sum "${target_env}" "${target_registry}" | sha256sum | awk '{print $1}')"

  if [[ "${old_hash}" != "${new_hash}" ]]; then
    JENKINS_CREDENTIALS_CHANGED="true"
    echo "${new_hash}" > "${hash_file}"
    chmod 600 "${hash_file}"
    log "Jenkins credential configuration changed. Jenkins container will be recreated to reload and upsert credentials."
  else
    JENKINS_CREDENTIALS_CHANGED="false"
    log "Jenkins credential configuration unchanged."
  fi
}

write_prometheus_config() {
  local prometheus_file="${PLATFORM_DIR}/devops-stack/prometheus.yml"

  cat > "${prometheus_file}" <<'EOF_PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules/*.yml
  - /etc/prometheus/rules/*.yaml

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

scrape_configs:
  - job_name: prometheus-server
    static_configs:
      - targets: ['prometheus:9090']
        labels:
          service: prometheus
          application: prometheus
          tier: tier-2

  - job_name: jenkins-server
    metrics_path: /prometheus
    static_configs:
      - targets: ['jenkins:8080']
        labels:
          service: jenkins
          application: jenkins
          tier: tier-3

  - job_name: postgres-exporter
    static_configs:
      - targets: ['postgres-exporter:9187']
        labels:
          service: postgres
          application: postgres
          tier: tier-0

  - job_name: redis-exporter
    static_configs:
      - targets: ['redis-exporter:9121']
        labels:
          service: redis
          application: redis
          tier: tier-0

  - job_name: node-exporter
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          service: node-exporter
          application: node-exporter
          tier: tier-3

  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
        labels:
          service: cadvisor
          application: cadvisor
          tier: tier-3

  - job_name: blackbox-exporter
    static_configs:
      - targets: ['blackbox-exporter:9115']
        labels:
          service: blackbox-exporter
          application: blackbox-exporter
          tier: tier-3

  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - http://jenkins:8080/login
          - http://grafana:3000/login
          - http://prometheus:9090/-/ready
          - http://alertmanager:9093/-/ready
          - http://cadvisor:8080/metrics
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
EOF_PROM
}

ensure_postgres_exporter_env() {
  local target_env="${PLATFORM_DIR}/devops-stack/postgres-exporter.env"
  local db_name="${POSTGRES_DB:-redberyl}"
  local db_user="${POSTGRES_USER:-postgres}"
  local db_password="${POSTGRES_PASSWORD:-}"

  if [[ -z "${db_password}" ]]; then
    echo "ERROR: POSTGRES_PASSWORD was not generated or loaded." >&2
    exit 1
  fi

  cat > "${target_env}" <<EOF_ENV
DATA_SOURCE_NAME=postgresql://${db_user}:${db_password}@postgres:5432/${db_name}?sslmode=disable
EOF_ENV
  chmod 600 "${target_env}"
}

write_credentials() {
  local credentials_file="${PLATFORM_DIR}/credentials.txt"
  local grafana_password="${GRAFANA_ADMIN_PASSWORD:-not-generated-devops-stack-disabled}"
  local jenkins_password="${JENKINS_ADMIN_PASSWORD:-not-generated-devops-stack-disabled}"

  cat > "${credentials_file}" <<EOF_CREDS
RedBeryl Platform Credentials
=============================
Generated: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

Grafana
-------
URL: http://${SERVER_IP}:3000
Username: admin
Password: ${grafana_password}

Jenkins
-------
URL: http://${SERVER_IP}:8080
Username: admin
Password: ${jenkins_password}

Jenkins notes:
- AWS/ECR/GitHub credentials are seeded from /opt/redberyl-platform/devops-stack/jenkins/jenkins-credentials.env and jenkins-credentials.json when values are present.
- Recommended AWS/ECR production method: attach an IAM role to the EC2 instance and let Jenkins use AWS CLI without static keys.

Service URLs
------------
Jenkins: http://${SERVER_IP}:8080
Grafana: http://${SERVER_IP}:3000
Prometheus: http://${SERVER_IP}:9090
Alertmanager: http://${SERVER_IP}:9093
Plane: http://${SERVER_IP}:8001
Huly: http://${SERVER_IP}:9898
Huly KVS: http://${SERVER_IP}:8094
EOF_CREDS
  chmod 600 "${credentials_file}"
}

deploy_devops() {
  copy_stack devops
  ensure_devops_env
  ensure_jenkins_credentials
  write_prometheus_config

  ensure_postgres_exporter_env

  compose_pull_up devops

  if [[ "${JENKINS_CREDENTIALS_CHANGED:-false}" == "true" ]]; then
    log "Recreating Jenkins container so updated dynamic Jenkins credentials are loaded and upserted"
    if stack_enabled plane; then
      (cd "${PLATFORM_DIR}/devops-stack" && COMPOSE_PROFILES=plane-monitoring docker compose up -d --build --force-recreate jenkins)
    else
      (cd "${PLATFORM_DIR}/devops-stack" && docker compose up -d --build --force-recreate jenkins)
    fi
  fi
}

deploy_plane() {
  local source_env="${PROJECT_DIR}/configs/plane.env"
  local target_env="${PLATFORM_DIR}/plane-stack/.env"

  if [[ ! -f "${source_env}" ]]; then
    echo "ERROR: plane stack enabled but configs/plane.env does not exist. Copy configs/plane.env.example to configs/plane.env and fill real values." >&2
    exit 1
  fi

  copy_stack plane
  cp "${source_env}" "${target_env}"
  chmod 600 "${target_env}"
  compose_pull_up plane
}

deploy_huly() {
  local source_env="${PROJECT_DIR}/configs/huly.env"
  local source_nginx="${PROJECT_DIR}/configs/huly-nginx.conf"
  local target_env="${PLATFORM_DIR}/huly-stack/.env"
  local target_nginx="${PLATFORM_DIR}/huly-stack/nginx/nginx.conf"

  if [[ ! -f "${source_env}" ]]; then
    echo "ERROR: huly stack enabled but configs/huly.env does not exist. Copy configs/huly.env.example to configs/huly.env and fill real values." >&2
    exit 1
  fi

  copy_stack huly
  cp "${source_env}" "${target_env}"
  chmod 600 "${target_env}"

  if [[ -f "${source_nginx}" ]]; then
    cp "${source_nginx}" "${target_nginx}"
  fi

  compose_pull_up huly
}

print_status() {
  echo
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  echo "Final URLs:"
  echo "Jenkins: http://${SERVER_IP}:8080"
  echo "Grafana: http://${SERVER_IP}:3000"
  echo "Prometheus: http://${SERVER_IP}:9090"
  echo "Alertmanager: http://${SERVER_IP}:9093"
  echo "Plane: http://${SERVER_IP}:8001"
  echo "Huly: http://${SERVER_IP}:9898"
  echo "Huly KVS: http://${SERVER_IP}:8094"
  echo
  echo "Credentials command: sudo cat ${PLATFORM_DIR}/credentials.txt"
  echo

  local stack
  for stack in "${ENABLED_STACKS[@]}"; do
    if [[ -d "${PLATFORM_DIR}/${stack}-stack" ]]; then
      echo "${stack} compose status:"
      if [[ "${stack}" == "devops" ]] && stack_enabled plane; then
        (cd "${PLATFORM_DIR}/${stack}-stack" && COMPOSE_PROFILES=plane-monitoring docker compose ps)
      else
        (cd "${PLATFORM_DIR}/${stack}-stack" && docker compose ps)
      fi
      echo
    fi
  done
}

main() {
  install_base_packages
  parse_enabled_stacks
  install_docker
  prepare_directories
  configure_firewall

  stack_enabled plane && deploy_plane
  stack_enabled huly && deploy_huly
  stack_enabled devops && deploy_devops

  write_credentials
  print_status
}

main "$@"
