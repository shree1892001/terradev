#!/bin/bash
set -euo pipefail
STACK_DIR="${1:-/opt/redberyl-platform/devops-stack}"
cd "${STACK_DIR}"

echo "Validating Docker Compose configuration..."
docker compose config >/tmp/redberyl-compose-config.out

echo "Validating Prometheus configuration..."
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml

echo "Checking exporter metrics..."
echo "Redis:"
curl -fsS http://localhost:9121/metrics | grep -E '^redis_up ' || true

echo "Postgres:"
curl -fsS http://localhost:9187/metrics | grep -E '^pg_up' || true

echo "cAdvisor:"
curl -fsS http://localhost:18080/metrics | head -n 5

echo "Grafana dashboard provisioning files:"
ls -la grafana/provisioning/dashboards grafana/provisioning/dashboards/json

echo "Grafana provisioning logs:"
docker logs --tail=300 grafana 2>&1 | grep -iE 'provision|dashboard|datasource' || true
