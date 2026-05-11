# jenkins-hello-world-python

Minimal Python Flask app that ships through a Jenkins pipeline: **GitHub push → Jenkins build → ECR push → Docker Compose rollout on the same EC2 host**.

```
GitHub  ──webhook──▶  Jenkins (EC2 50.19.0.175)
                          │
                          ├── docker build
                          ├── docker push  ──▶  Amazon ECR
                          └── deploy.sh    ──▶  docker compose pull && up -d   (same EC2)
                                                       │
                                                       └── http://50.19.0.175:5000
```

## Why Docker Compose rollout (not raw `docker run`)

Pick **compose**. Reasons:
- One declarative file (`docker-compose.yml`) — env vars, ports, healthcheck, restart policy in source control.
- Rollback is trivial — change `IMAGE_TAG`, `docker compose up -d`.
- `docker compose up -d` only restarts containers whose config changed → in-place rollout for free.
- Scales naturally when you add a DB, Redis, sidecar, etc. Raw `docker run` doesn't.

---

## Files in this repo

| File | Purpose |
|---|---|
| `app.py` | Flask app, `GET /` and `GET /health` |
| `requirements.txt` | Python deps |
| `Dockerfile` | Builds the image (python:3.12-slim) |
| `docker-compose.yml` | Declares the runtime service |
| `deploy.sh` | Runs on the EC2 host — ECR login + compose pull + up |
| `Jenkinsfile` | The pipeline |

---

## One-time setup (do this once, in order)

### 1. AWS — create an IAM user for Jenkins

In AWS Console → IAM → Users → **Create user** → name it `jenkins-ci`.

Attach these AWS-managed policies:
- `AmazonEC2ContainerRegistryFullAccess`

Then under **Security credentials → Create access key** → "Application running outside AWS" → save **Access key ID** and **Secret access key** (you'll paste them into Jenkins below).

### 2. AWS — create the ECR repo (optional, the pipeline auto-creates it)

Console → ECR → **Create repository** → name `hello-world-python` → region `us-east-1`. Note the URI, it looks like:
```
<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/hello-world-python
```

### 3. EC2 — prep the Jenkins host

SSH in once and install Docker + Docker Compose plugin + AWS CLI, then give the `jenkins` user docker access:

```bash
ssh -i ansible-key.pem ubuntu@ec2-50-19-0-175.compute-1.amazonaws.com

# Docker engine + compose v2 plugin
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin awscli
sudo systemctl enable --now docker

# Let the jenkins user run docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Sanity check
sudo -u jenkins docker version
sudo -u jenkins docker compose version
sudo -u jenkins aws --version
```

Also open **port 5000** in the EC2 security group (Inbound rule: TCP 5000 from 0.0.0.0/0 — or restrict to your IP).

### 4. Jenkins — install plugins

`Manage Jenkins → Plugins → Available plugins`, search and install:

- **Pipeline** (usually installed by default)
- **Git** (default)
- **GitHub** (default)
- **GitHub Integration** — provides the `githubPush()` trigger
- **Docker Pipeline**
- **AWS Credentials** — adds the `AmazonWebServicesCredentialsBinding` Jenkinsfile step
- **Pipeline: AWS Steps** (optional — only if you want `withAWS { … }`)
- **AnsiColor** — for colored logs (used in Jenkinsfile)
- **Timestamper** — for `timestamps()` (used in Jenkinsfile)

Restart Jenkins after install.

### 5. Jenkins — add credentials

`Manage Jenkins → Credentials → System → Global credentials → Add Credentials`:

**a)** AWS keys for ECR
- Kind: **AWS Credentials**
- ID: `aws-ecr-creds`   ← must match the Jenkinsfile exactly
- Access key ID / Secret access key: from step 1
- Description: `AWS user for ECR push`

**b)** GitHub token (only needed if the repo is private — it is not, so you can skip)
- Kind: Username with password
- Username: `iamakshay777`
- Password: your PAT
- ID: `github-token`

### 6. Jenkins — create the pipeline job

`New Item → Pipeline → name: hello-world-python → OK`

In the job config:

- **GitHub project** → `https://github.com/iamakshay777/jenkins-hello-world-python/`
- **Build Triggers** → check **GitHub hook trigger for GITScm polling**
- **Pipeline**
  - Definition: **Pipeline script from SCM**
  - SCM: **Git**
  - Repository URL: `https://github.com/iamakshay777/jenkins-hello-world-python.git`
  - Branch: `*/main`
  - Script Path: `Jenkinsfile`

Save.

### 7. Edit the Jenkinsfile env block

Open `Jenkinsfile` in this repo and replace:
```
AWS_ACCOUNT   = '123456789012'
```
with your real AWS account ID. Commit + push → that push itself will be your first webhook trigger.

### 8. GitHub — wire up the webhook

Repo → **Settings → Webhooks → Add webhook**:

- Payload URL: `http://50.19.0.175:8080/github-webhook/`    ← note the trailing slash, this is the path the GitHub plugin listens on
- Content type: `application/json`
- Secret: leave empty (or set one and configure in `Manage Jenkins → System → GitHub` if you want)
- Events: **Just the push event**
- Active: ✔

After saving, scroll down — GitHub will fire a test ping. You should see a green check and a `200` response. If you see a connection refused or timeout, fix the Jenkins EC2 security group: allow TCP 8080 from `0.0.0.0/0` (or from GitHub's webhook IP ranges).

---

## How a deploy flows after setup

1. You `git push` to `main`.
2. GitHub fires the webhook → Jenkins.
3. Jenkins job runs the `Jenkinsfile`:
   - Checks out code
   - Builds image, tags `:BUILD_NUMBER` and `:latest`
   - Logs into ECR, pushes both tags
   - Copies `docker-compose.yml` + `deploy.sh` to `/opt/hello-world-python`
   - Runs `deploy.sh` → `aws ecr get-login-password | docker login`, `docker compose pull`, `docker compose up -d`
   - Smoke-tests `http://localhost:5000/health`
4. Browse `http://50.19.0.175:5000/` → see the JSON hello.

## Rollback in one command

On the EC2 host:
```bash
cd /opt/hello-world-python
IMAGE_TAG=<previous_build_number> docker compose up -d
```

That's it — flips the running container back to a known good ECR tag.

---

## Troubleshooting cheatsheet

| Symptom | Likely cause | Fix |
|---|---|---|
| Webhook delivery fails on GitHub side | Security group blocks 8080 | Allow inbound TCP 8080 in EC2 SG |
| `aws: command not found` in Jenkins | AWS CLI not installed for jenkins user | `sudo apt-get install -y awscli` |
| `permission denied` on `/var/run/docker.sock` | `jenkins` user not in `docker` group | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `denied: requested access to the resource is denied` on push | IAM user missing ECR permission | Attach `AmazonEC2ContainerRegistryFullAccess` |
| `sudo: a password is required` in pipeline | Jenkins user lacks passwordless sudo for `mkdir`/`chown` | Either pre-create `/opt/hello-world-python` owned by jenkins, or add a sudoers rule |
| App returns old version | Compose didn't pick up new image | Confirm `IMAGE_TAG` env was exported; `docker compose pull` then `up -d` |
