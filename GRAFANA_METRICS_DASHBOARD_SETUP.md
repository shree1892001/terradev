# Grafana Metrics Dashboard Setup

This package provisions Grafana dashboards from JSON files and configures Prometheus to scrape Redis, PostgreSQL, cAdvisor, Node Exporter, Jenkins, Alertmanager, and Blackbox Exporter.

## Included dashboards

- Unified Production + SRE + Redis Dashboard
- RedBeryl Exporters Health - Redis Postgres cAdvisor

## Important service mappings

- cAdvisor: host port `18080`, container port `8080`, Prometheus target `cadvisor:8080`
- Redis: container name `redis`, internal port `6379`
- Redis exporter: target `redis://redis:6379`, Prometheus target `redis-exporter:9121`
- PostgreSQL: container name `postgres`, internal port `5432`
- Postgres exporter: target `postgres:5432`, Prometheus target `postgres-exporter:9187`

## Deploy

```bash
terraform apply
```

## Recreate Grafana after dashboard changes

```bash
cd /opt/redberyl-platform/devops-stack
sudo docker compose up -d --force-recreate grafana
```

## Validate

```bash
sudo bash scripts/validate-devops-metrics.sh /opt/redberyl-platform/devops-stack
curl http://localhost:9121/metrics | grep redis_up
curl http://localhost:9187/metrics | grep pg_up
curl http://localhost:18080/metrics | head
```

Expected:

```text
redis_up 1
pg_up 1
```
