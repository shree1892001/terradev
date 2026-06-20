# RedBeryl Platform Terraform Testing Guide

This guide validates the production-grade Terraform automation project on a fresh Ubuntu server.

Recommended test path:

1. Validate files.
2. Deploy `devops` only.
3. Verify Jenkins/Grafana/Prometheus.
4. Verify dynamic Jenkins credential creation/update.
5. Deploy `devops` + `plane` and verify Plane exporters inside the DevOps stack.
6. Deploy full stack with Huly if required.

## 1. Server Requirements

- Ubuntu 22.04 or 24.04.
- Terraform installed.
- `sudo` access.
- Internet access for apt and Docker image pulls.
- Static IP or DNS recommended.

Recommended minimums:

| Test Scope | Suggested Size |
| --- | --- |
| DevOps only | 2 vCPU, 4 GB RAM |
| DevOps + Plane | 4 vCPU, 8 GB RAM |
| DevOps + Plane + Huly | 8 vCPU, 16 GB RAM or more |

## 2. Required Public Ports

Open these in security group/firewall as needed:

```text
22/tcp     SSH
8080/tcp   Jenkins
50000/tcp  Jenkins agent port
3000/tcp   Grafana
9090/tcp   Prometheus
9093/tcp   Alertmanager
8001/tcp   Plane
9898/tcp   Huly
8094/tcp   Huly KVS
```

Do not expose PostgreSQL, Redis/Valkey, RabbitMQ, MinIO, Elasticsearch, CockroachDB, or Redpanda publicly.

## 3. Prepare Project

```bash
cd ~/terradev-production-ready
cp terraform.tfvars.example terraform.tfvars
cp configs/jenkins-credentials.env.example configs/jenkins-credentials.env
cp configs/postgres-exporter.env.example configs/postgres-exporter.env
cp configs/plane.env.example configs/plane.env
cp configs/huly.env.example configs/huly.env
cp configs/huly-nginx.conf.example configs/huly-nginx.conf
chmod 600 configs/jenkins-credentials.env configs/postgres-exporter.env configs/plane.env configs/huly.env
```

Edit:

```bash
nano terraform.tfvars
nano configs/jenkins-credentials.json
nano configs/jenkins-credentials.env
```

## 4. Validate Terraform and Scripts

```bash
terraform init
terraform fmt -check -recursive
terraform validate
bash -n scripts/bootstrap.sh
terraform plan
```

Expected:

- Terraform initializes successfully.
- `terraform validate` succeeds.
- `bash -n` returns no output.
- `terraform plan` shows `null_resource.redberyl_platform` create/replace.

## 5. Test DevOps Stack Only

Set `terraform.tfvars`:

```hcl
server_ip      = "YOUR_SERVER_IP_OR_DOMAIN"
platform_dir   = "/opt/redberyl-platform"
enabled_stacks = ["devops"]
force_redeploy = ""
```

Apply:

```bash
terraform apply
```

Expected containers:

```text
jenkins
prometheus
grafana
alertmanager
node-exporter
cadvisor
blackbox-exporter
```

There should be no `process-exporter`:

```bash
sudo docker ps -a | grep process-exporter || echo "process-exporter removed - OK"
```

Plane exporters should not run with DevOps-only mode:

```bash
sudo docker ps -a | grep -E 'plane-postgres-exporter|plane-redis-exporter' || echo "Plane exporters not active - OK"
```

Verify services:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
curl -I http://localhost:8080/login
curl -I http://localhost:3000/login
curl -I http://localhost:9090/-/ready
curl -I http://localhost:9093/-/ready
```

Check generated base credentials:

```bash
sudo cat /opt/redberyl-platform/credentials.txt
```

## 6. Test Dynamic Jenkins Credentials

Fill at least one safe test credential in:

```bash
nano configs/jenkins-credentials.env
```

Example:

```env
GRAFANA_TOKEN=test-grafana-token-001
GITHUB_USERNAME=test-user
GITHUB_TOKEN=test-token-001
```

Apply:

```bash
terraform apply
```

Check Jenkins credential seeding logs:

```bash
sudo docker logs --tail=300 jenkins 2>&1 | grep -E "Created/Updated Jenkins credential|Skipping Jenkins credential|dynamic credentials seeding"
```

Expected examples:

```text
Created/Updated Jenkins credential 'grafana-token'
Created/Updated Jenkins credential 'githubcred'
Jenkins dynamic credentials seeding completed successfully
```

Open Jenkins:

```text
http://SERVER_IP:8080
```

Go to:

```text
Manage Jenkins → Credentials → System → Global credentials
```

Verify configured credential IDs appear.

## 7. Test Credential Update

Change a value:

```bash
nano configs/jenkins-credentials.env
```

Example:

```env
GRAFANA_TOKEN=test-grafana-token-002
```

Run:

```bash
terraform apply
```

Expected behavior:

```text
bootstrap detects credential hash change
Jenkins container is recreated
existing Jenkins credential ID is removed and recreated with updated value
```

Validate logs:

```bash
sudo docker logs --tail=300 jenkins 2>&1 | grep -E "Removed existing Jenkins credential|Created/Updated Jenkins credential|dynamic credentials seeding"
```

## 8. Add a New Future Credential

Edit registry:

```bash
nano configs/jenkins-credentials.json
```

Add a new item:

```json
{
  "id": "new-api-token",
  "type": "secretText",
  "description": "New API Token",
  "secretEnv": "NEW_API_TOKEN"
}
```

Add value:

```bash
nano configs/jenkins-credentials.env
```

```env
NEW_API_TOKEN=actual-value
```

Apply:

```bash
terraform apply
```

Check Jenkins credentials list for `new-api-token`.

## 9. Test SSH Private Key Credential

Base64 encode a key:

```bash
base64 -w0 ~/.ssh/id_rsa
```

Put it in env:

```env
DEV_REMOTE_SSH_USERNAME=ubuntu
DEV_REMOTE_SSH_PRIVATE_KEY_B64=PASTE_BASE64_KEY_HERE
DEV_REMOTE_SSH_PASSPHRASE=
```

Apply and verify `dev-remote-ssh` exists in Jenkins credentials.

## 10. Test DevOps + Plane

Set:

```hcl
enabled_stacks = ["devops", "plane"]
force_redeploy = "plane-test-1"
```

Ensure real Plane env exists:

```bash
test -f configs/plane.env && echo OK
```

Apply:

```bash
terraform apply
```

Expected Plane exporters run in DevOps stack:

```text
plane-postgres-exporter
plane-redis-exporter
```

Verify:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E 'plane-postgres-exporter|plane-redis-exporter|plane-app-proxy-1'
cd /opt/redberyl-platform/devops-stack && sudo env COMPOSE_PROFILES=plane-monitoring docker compose ps
cd /opt/redberyl-platform/plane-stack && sudo docker compose ps
```

Check exporter metrics from Prometheus container:

```bash
sudo docker exec prometheus wget -qO- http://plane-postgres-exporter:9187/metrics | head
sudo docker exec prometheus wget -qO- http://plane-redis-exporter:9121/metrics | head
```

Check Prometheus targets:

```text
http://SERVER_IP:9090/targets
```

## 11. Test Full Stack

Set:

```hcl
enabled_stacks = ["devops", "plane", "huly"]
force_redeploy = "full-test-1"
```

Ensure real Huly env and nginx config exist:

```bash
test -f configs/huly.env && echo OK
test -f configs/huly-nginx.conf && echo OK
```

Apply:

```bash
terraform apply
```

Check:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Open:

```text
Jenkins:      http://SERVER_IP:8080
Grafana:      http://SERVER_IP:3000
Prometheus:   http://SERVER_IP:9090
Alertmanager: http://SERVER_IP:9093
Plane:        http://SERVER_IP:8001
Huly:         http://SERVER_IP:9898
```

## 12. Troubleshooting

```bash
sudo docker ps -a
sudo docker logs --tail=200 jenkins
sudo docker logs --tail=200 grafana
sudo docker logs --tail=200 prometheus
sudo docker logs --tail=200 alertmanager
cd /opt/redberyl-platform/devops-stack && sudo docker compose ps
```

If Jenkins credentials do not appear:

```bash
sudo docker logs --tail=500 jenkins | grep -i credential
sudo cat /opt/redberyl-platform/devops-stack/jenkins/jenkins-credentials.json
sudo grep -E '^[A-Z0-9_]+=' /opt/redberyl-platform/devops-stack/jenkins/jenkins-credentials.env | sed 's/=.*/=****/'
```

If Grafana password does not work because an old volume exists:

```bash
sudo docker exec -it grafana grafana cli admin reset-admin-password 'Admin@12345'
```
