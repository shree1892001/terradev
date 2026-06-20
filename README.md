# RedBeryl Platform Terraform Automation

This project deploys the RedBeryl self-hosted platform on an Ubuntu Linux server where Terraform runs locally on the same server. Terraform is used as the controlled automation runner and Docker Compose runs the containers.

The platform is deployed under:

```text
/opt/redberyl-platform
```

## Production Architecture

```text
Ubuntu Linux Server
├── Terraform local-exec
├── Docker Engine installed with sudo/root
├── Docker Compose plugin
└── /opt/redberyl-platform/
    ├── credentials.txt
    ├── devops-stack/
    │   ├── Jenkins with Docker CLI, AWS CLI, JCasC and dynamic credential seeding
    │   ├── Prometheus
    │   ├── Grafana
    │   ├── Alertmanager
    │   ├── Node Exporter
    │   ├── cAdvisor
    │   ├── Blackbox Exporter
    │   ├── Plane PostgreSQL Exporter
    │   └── Plane Redis/Valkey Exporter
    ├── plane-stack/
    │   ├── Plane app containers
    │   ├── PostgreSQL
    │   ├── Valkey
    │   ├── RabbitMQ
    │   └── MinIO
    └── huly-stack/
        ├── Huly app containers
        ├── Nginx
        ├── CockroachDB
        ├── Elasticsearch
        ├── MinIO
        └── Redpanda
```

## Key Design Decisions

- Docker is installed and managed by `sudo bash scripts/bootstrap.sh`.
- Jenkins, Grafana, Prometheus, Alertmanager, exporters, Plane and Huly are deployed as Docker Compose stacks.
- `process-exporter` is completely removed.
- `plane-postgres-exporter` and `plane-redis-exporter` are part of the **DevOps stack** and start only when both `devops` and `plane` are enabled.
- Plane and Huly use real env files copied securely by bootstrap. Secret env files are ignored by Git.
- Internal DB/cache/message queue/object storage/search ports are not published to the host.
- Jenkins credentials are not hardcoded in Groovy. They are dynamically controlled by a credential registry and env values:

```text
configs/jenkins-credentials.json     # credential definitions: id, type, env mapping
configs/jenkins-credentials.env      # actual secret values, ignored by Git
```

When either file changes and `terraform apply` is run, bootstrap recreates Jenkins and the init Groovy script creates or updates Jenkins credentials automatically.

## Supported Jenkins Credential Types

The dynamic credential seeder supports:

```text
secretText
usernamePassword
sshPrivateKey
fileCredential
```

This makes the setup future-ready. To add a new Jenkins credential later, add a new object in `configs/jenkins-credentials.json`, add the matching env value in `configs/jenkins-credentials.env`, then run `terraform apply`.

## Project Structure

```text
terradev-production-ready/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
├── .gitignore
├── README.md
├── TESTING.md
├── WINDOWS_EC2_TESTING_GUIDE.md
├── configs/
│   ├── jenkins-credentials.json
│   ├── jenkins-credentials.json.example
│   ├── jenkins-credentials.env.example
│   ├── postgres-exporter.env.example
│   ├── plane.env.example
│   ├── huly.env.example
│   └── huly-nginx.conf.example
├── stacks/
│   ├── devops-stack/
│   ├── plane-stack/
│   └── huly-stack/
└── scripts/
    └── bootstrap.sh
```

Real secret files ignored by Git:

```text
terraform.tfvars
configs/jenkins-credentials.env
configs/postgres-exporter.env
configs/plane.env
configs/huly.env
configs/huly-nginx.conf
```

## Prepare Configuration Files

```bash
cp terraform.tfvars.example terraform.tfvars
cp configs/jenkins-credentials.env.example configs/jenkins-credentials.env
cp configs/postgres-exporter.env.example configs/postgres-exporter.env
cp configs/plane.env.example configs/plane.env
cp configs/huly.env.example configs/huly.env
cp configs/huly-nginx.conf.example configs/huly-nginx.conf

chmod 600 configs/jenkins-credentials.env configs/postgres-exporter.env configs/plane.env configs/huly.env
```

Edit required files:

```bash
nano terraform.tfvars
nano configs/jenkins-credentials.json
nano configs/jenkins-credentials.env
```

## Dynamic Jenkins Credential Configuration

`configs/jenkins-credentials.json` defines which credentials should exist in Jenkins.

Example `secretText` credential:

```json
{
  "id": "grafana-token",
  "type": "secretText",
  "description": "Grafana API Token",
  "secretEnv": "GRAFANA_TOKEN"
}
```

Matching value in `configs/jenkins-credentials.env`:

```env
GRAFANA_TOKEN=actual-token-value
```

Example `usernamePassword` credential:

```json
{
  "id": "githubcred",
  "type": "usernamePassword",
  "description": "GitHub Credentials",
  "usernameEnv": "GITHUB_USERNAME",
  "passwordEnv": "GITHUB_TOKEN"
}
```

Matching values:

```env
GITHUB_USERNAME=your-github-user
GITHUB_TOKEN=your-github-token
```

Example `sshPrivateKey` credential:

```json
{
  "id": "dev-remote-ssh",
  "type": "sshPrivateKey",
  "description": "DEV remote SSH private key",
  "usernameEnv": "DEV_REMOTE_SSH_USERNAME",
  "privateKeyBase64Env": "DEV_REMOTE_SSH_PRIVATE_KEY_B64",
  "passphraseEnv": "DEV_REMOTE_SSH_PASSPHRASE"
}
```

Generate base64 private key value:

```bash
base64 -w0 ~/.ssh/id_rsa
```

Then set:

```env
DEV_REMOTE_SSH_USERNAME=ubuntu
DEV_REMOTE_SSH_PRIVATE_KEY_B64=PASTE_BASE64_PRIVATE_KEY_HERE
DEV_REMOTE_SSH_PASSPHRASE=
```

## Credential Update Flow

```text
Update configs/jenkins-credentials.json or configs/jenkins-credentials.env
        ↓
Run terraform apply
        ↓
bootstrap.sh copies files into /opt/redberyl-platform/devops-stack/jenkins
        ↓
Jenkins container is recreated only when credential config hash changes
        ↓
init.groovy.d/seed-credentials.groovy reads JSON + env values
        ↓
Jenkins credentials are created or updated
```

Empty env values are skipped. Existing credentials with the same ID are replaced with the new value.

## Stack Selection

Edit `terraform.tfvars`:

```hcl
server_ip      = "YOUR_SERVER_IP_OR_DOMAIN"
platform_dir   = "/opt/redberyl-platform"
enabled_stacks = ["devops", "plane", "huly"]
force_redeploy = ""
```

Supported selections:

```hcl
enabled_stacks = ["devops"]
enabled_stacks = ["devops", "plane"]
enabled_stacks = ["devops", "plane", "huly"]
```

## Deploy

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## Access URLs

```text
Jenkins:      http://SERVER_IP:8080
Grafana:      http://SERVER_IP:3000
Prometheus:   http://SERVER_IP:9090
Alertmanager: http://SERVER_IP:9093
Plane:        http://SERVER_IP:8001
Huly:         http://SERVER_IP:9898
Huly KVS:     http://SERVER_IP:8094
```

## Credentials

```bash
sudo cat /opt/redberyl-platform/credentials.txt
```

Jenkins and Grafana base admin passwords are stored there.

Jenkins dynamic credentials are visible at:

```text
Jenkins → Manage Jenkins → Credentials → System → Global credentials
```

## AWS/ECR Recommendation

Best production method: attach an EC2 IAM role with ECR permissions. Then Jenkins can use AWS CLI without storing static AWS keys:

```bash
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 421454275266.dkr.ecr.ap-southeast-2.amazonaws.com
```

If your lead requires credentials to be created by Terraform/bootstrap, define them in `jenkins-credentials.json` and set values in `jenkins-credentials.env`. Do not put secret values directly into `.tf` or `terraform.tfvars`.

## Useful Commands

```bash
sudo docker ps
sudo docker logs --tail=200 jenkins
sudo docker logs --tail=200 grafana
sudo docker logs --tail=200 prometheus
cd /opt/redberyl-platform/devops-stack && sudo docker compose ps
```

If Grafana login fails because an old volume exists:

```bash
sudo docker exec -it grafana grafana cli admin reset-admin-password 'Admin@12345'
```
