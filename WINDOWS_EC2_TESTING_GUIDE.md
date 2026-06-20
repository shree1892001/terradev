# Windows to EC2 Testing Guide for RedBeryl Terraform Project

This guide is written for testing from a Windows laptop using PowerShell and an Ubuntu EC2 server.

Follow the steps in order. Do not skip directly to `terraform apply`.

## What You Have

Local Windows project path:

```powershell
E:\terradev\redberyl-platform-terraform
```

Private key:

```powershell
E:\terradev\shreyas.pem
```

EC2 server:

```text
13.218.169.95
```

EC2 username:

```text
ubuntu
```

## Step 1: Open PowerShell in the Correct Folder

Open PowerShell and run:

```powershell
cd E:\terradev
```

Confirm files exist:

```powershell
dir
```

You should see:

```text
redberyl-platform-terraform
shreyas.pem
```

If you do not see both, you are in the wrong folder.

## Step 2: Fix PEM File Permissions on Windows

Your error:

```text
WARNING: UNPROTECTED PRIVATE KEY FILE
Load key "shreyas.pem": bad permissions
```

means Windows permissions on `shreyas.pem` are too open.

Run these commands exactly:

```powershell
cd E:\terradev

$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

icacls .\shreyas.pem /inheritance:r
icacls .\shreyas.pem /grant:r "$me:R"
icacls .\shreyas.pem /remove "NT AUTHORITY\Authenticated Users"
icacls .\shreyas.pem /remove "BUILTIN\Users"
icacls .\shreyas.pem /remove "Everyone"
```

Now check permissions:

```powershell
icacls .\shreyas.pem
```

Good output should show your Windows user has read access.

It should not show:

```text
Everyone
BUILTIN\Users
NT AUTHORITY\Authenticated Users
```

## Step 3: Test SSH Login First

Before copying the project, test SSH:

```powershell
ssh -i .\shreyas.pem ubuntu@13.218.169.95
```

If it works, you will enter the EC2 server and see a Linux prompt.

Example:

```text
ubuntu@ip-xxx-xxx-xxx-xxx:~$
```

Exit back to Windows:

```bash
exit
```

If SSH does not work, do not continue. Fix SSH first.

Common SSH errors:

| Error | Meaning |
| --- | --- |
| `bad permissions` | PEM file permissions are too open |
| `Load key Permission denied` | Your Windows user cannot read the PEM file |
| `Permission denied (publickey)` | Wrong key, wrong username, or EC2 security group issue |
| Connection timeout | Port 22 is not open in EC2 security group |

## Step 4: Copy Project to EC2

Run this from Windows PowerShell:

```powershell
cd E:\terradev
scp -i .\shreyas.pem -r .\redberyl-platform-terraform ubuntu@13.218.169.95:~/
```

Important:

- Use `scp`, not `cp`.
- Run this from `E:\terradev`.
- Do not run it from inside `redberyl-platform-terraform`.

Correct:

```powershell
cd E:\terradev
scp -i .\shreyas.pem -r .\redberyl-platform-terraform ubuntu@13.218.169.95:~/
```

Wrong:

```powershell
cp -i shreyas.pem -r redberyl-platform-terraform ubuntu@13.218.169.95:~/
```

PowerShell `cp` is a Windows copy command. It does not copy files to EC2.

## Step 5: Login to EC2

```powershell
ssh -i .\shreyas.pem ubuntu@13.218.169.95
```

Go to the project:

```bash
cd ~/redberyl-platform-terraform
```

Check files:

```bash
ls -la
```

You should see:

```text
main.tf
variables.tf
outputs.tf
terraform.tfvars.example
configs
stacks
scripts
README.md
```

## Step 6: Install Terraform on EC2 if Missing

Check:

```bash
terraform version
```

If Terraform is installed, continue.

If Terraform is not installed, run:

```bash
sudo apt-get update
sudo apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
```

Check again:

```bash
terraform 

```

## Step 7: Start With DevOps Stack Only

For first test, do not deploy Plane and Huly.

First deploy only:

```text
Jenkins
Grafana
Prometheus
Alertmanager
Node Exporter
cAdvisor
```

Create Terraform variables:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Put this:

```hcl
server_ip = "13.218.169.95"
platform_dir = "/opt/redberyl-platform"
enabled_stacks = ["devops"]
force_redeploy = ""
```

Save and exit:

- Press `Ctrl + O`
- Press `Enter`
- Press `Ctrl + X`

## Step 8: Create Env Files

Even though DevOps does not use Plane/Huly env files, create them now so the project is ready later:

```bash
cp configs/plane.env.example configs/plane.env
cp configs/huly.env.example configs/huly.env
cp configs/huly-nginx.conf.example configs/huly-nginx.conf
```

Do not worry about editing Plane/Huly env files yet if you are only testing DevOps.

## Step 9: Run Terraform Validation

Run:

```bash
terraform init
```

Expected result:

```text
Terraform has been successfully initialized
```

Then:

```bash
terraform validate
```

Expected result:

```text
Success! The configuration is valid.
```

Then:

```bash
terraform plan
```

Expected result:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

## Step 10: Apply Terraform

Run:

```bash
terraform apply
```

Terraform will ask:

```text
Do you want to perform these actions?
```

Type:

```text
yes
```

This will take time because the script installs Docker and downloads images.

Wait until it finishes.

## Step 11: Verify Docker Containers

Run:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

For DevOps-only test, you should see containers like:

```text
jenkins
grafana
prometheus
alertmanager
node-exporter
cadvisor
```

If a container is missing, check logs.

Example:

```bash
sudo docker logs -f jenkins
```

Stop log watching with:

```text
Ctrl + C
```

## Step 12: Check Credentials

Run:

```bash
sudo cat /opt/redberyl-platform/credentials.txt
```

This shows:

- Grafana username
- Grafana password
- Jenkins initial password command
- Service URLs

Get Jenkins password:

```bash
sudo docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

## Step 13: Open URLs in Browser

Open these on your laptop browser:

```text
http://13.218.169.95:8080
http://13.218.169.95:3000
http://13.218.169.95:9090
http://13.218.169.95:9093
```

Expected:

| URL | Expected Page |
| --- | --- |
| `:8080` | Jenkins setup page |
| `:3000` | Grafana login page |
| `:9090` | Prometheus UI |
| `:9093` | Alertmanager UI |

Grafana login:

```text
username: admin
password: from credentials.txt
```

## Step 14: If Browser Does Not Open

Check EC2 security group inbound rules.

You must allow:

```text
22/tcp
8080/tcp
50000/tcp
3000/tcp
9090/tcp
9093/tcp
```

For testing, allow them from your IP address.

Also check firewall on EC2:

```bash
sudo ufw status verbose
```

Check if containers expose ports:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Ports}}"
```

## Step 15: Test Plane After DevOps Works

Only do this after DevOps is working.

Edit Terraform variables:

```bash
nano terraform.tfvars
```

Change:

```hcl
enabled_stacks = ["devops", "plane"]
force_redeploy = "plane-test-1"
```

Now edit Plane env:

```bash
nano configs/plane.env
```

Important:

Public URL should use EC2 IP:

```text
WEB_URL=http://13.218.169.95:8001
CORS_ALLOWED_ORIGINS=http://13.218.169.95:8001
```

Internal services should use Docker names:

```text
DATABASE_URL=postgresql://plane:PASSWORD@plane-db:5432/plane
REDIS_URL=redis://plane-redis:6379
AMQP_URL=amqp://plane:PASSWORD@plane-mq:5672/
AWS_S3_ENDPOINT_URL=http://plane-minio:9000
```

Apply:

```bash
terraform plan
terraform apply
```

Check Plane:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
sudo docker logs -f plane-app-api-1
```

Open:

```text
http://13.218.169.95:8001
```

Make sure EC2 security group allows:

```text
8001/tcp
```

## Step 16: Test Huly After Plane Works

Only do this after DevOps and Plane are working.

Edit:

```bash
nano terraform.tfvars
```

Set:

```hcl
enabled_stacks = ["devops", "plane", "huly"]
force_redeploy = "huly-test-1"
```

Edit Huly env:

```bash
nano configs/huly.env
```

Public URL:

```text
HOST_ADDRESS=http://13.218.169.95:9898
```

Internal service names:

```text
ELASTIC_URL=http://huly-elastic:9200
COCKROACH_URL=postgresql://root@huly-cockroach:26257/defaultdb?sslmode=disable
REDPANDA_BROKERS=huly-redpanda:9092
STORAGE_ENDPOINT=http://huly-minio:9000
ACCOUNTS_URL=http://huly-account:3000
FRONT_URL=http://huly-front:8080
TRANSACTOR_URL=http://huly-transactor:8080
COLLABORATOR_URL=http://huly-collaborator:3078
REKONI_URL=http://huly-rekoni:4004
FULLTEXT_URL=http://huly-fulltext:4700
KVS_URL=http://huly-kvs:8094
```

Apply:

```bash
terraform plan
terraform apply
```

Check Huly:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
sudo docker logs -f huly-selfhost-nginx-1
```

Open:

```text
http://13.218.169.95:9898
http://13.218.169.95:8094
```

Make sure EC2 security group allows:

```text
9898/tcp
8094/tcp
```

## Step 17: Useful Debug Commands

Check all running containers:

```bash
sudo docker ps
```

Check all containers, including stopped:

```bash
sudo docker ps -a
```

Check logs:

```bash
sudo docker logs -f CONTAINER_NAME
```

Example:

```bash
sudo docker logs -f grafana
sudo docker logs -f plane-app-proxy-1
sudo docker logs -f huly-selfhost-nginx-1
```

Check stack status:

```bash
cd /opt/redberyl-platform/devops-stack && sudo docker compose ps
cd /opt/redberyl-platform/plane-stack && sudo docker compose ps
cd /opt/redberyl-platform/huly-stack && sudo docker compose ps
```

Restart stack:

```bash
cd /opt/redberyl-platform/devops-stack && sudo docker compose restart
```

Stop stack without deleting data:

```bash
cd /opt/redberyl-platform/devops-stack && sudo docker compose down
```

Start stack again:

```bash
cd /opt/redberyl-platform/devops-stack && sudo docker compose up -d
```

## Step 18: Very Important Warnings

Do not run this unless you want to delete data:

```bash
docker compose down -v
```

`-v` deletes Docker named volumes.

Do not expose these ports publicly:

```text
5432
6379
5672
9000
9200
26257
9092
```

Do not commit real env files:

```text
configs/plane.env
configs/huly.env
configs/huly-nginx.conf
```

## Simple Testing Summary

Use this order:

```text
1. Fix shreyas.pem permissions on Windows.
2. Test SSH.
3. Copy project using scp.
4. SSH into EC2.
5. cd ~/redberyl-platform-terraform.
6. Create terraform.tfvars.
7. Set enabled_stacks = ["devops"].
8. terraform init.
9. terraform validate.
10. terraform plan.
11. terraform apply.
12. Open Jenkins/Grafana/Prometheus/Alertmanager.
13. Then test Plane.
14. Then test Huly.
```

Do not test Plane and Huly until DevOps is working.
