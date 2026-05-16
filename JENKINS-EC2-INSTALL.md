# Jenkins on Ubuntu EC2 — Full Install Steps

Single-file walkthrough to bring up a working Jenkins host on a fresh Ubuntu 24.04 EC2 instance. Includes Java, Jenkins LTS, Docker engine, Docker Compose v2 plugin, Docker Buildx plugin, AWS CLI v2, Jenkins user permissions, and the deploy directory used by this repo's pipeline.

**Tested on:** Ubuntu Server 24.04 LTS, instance type **t3.small** (minimum) or **t3.medium** (recommended).
**Open in security group:** TCP 22 (SSH from My IP), TCP 8080 (Jenkins + webhook), TCP 5000 (app).

---

## 1. Update system

```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Install Java 21

```bash
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

## 3. Add Jenkins GPG key

```bash
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x7198F4B714ABFC68" \
  | sudo gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg
sudo chmod 644 /usr/share/keyrings/jenkins-keyring.gpg
```

## 4. Add Jenkins repository

```bash
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
```

## 5. Install Jenkins

```bash
sudo apt update
sudo apt install -y jenkins
```

## 6. Make sure port 8080 is free

```bash
sudo ss -tlnp | grep 8080
```

If something else is listening on 8080, stop it before continuing.

## 7. Start Jenkins

```bash
sudo systemctl enable jenkins
sudo systemctl reset-failed jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins
```

## 8. Get initial admin password

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open `http://<EC2_PUBLIC_IP>:8080/`, paste the password, click **Install suggested plugins**, create your admin user, finish the wizard.

---

## 9. Install Docker engine

```bash
sudo apt install -y docker.io
sudo systemctl enable --now docker
docker --version
```

## 10. Install Docker Compose v2 plugin

Ubuntu's `docker.io` package does NOT bundle the compose plugin, so install it as a binary:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL \
  https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version
```

## 11. Install Docker Buildx plugin

Needed for clean single-platform image push on Docker 25+ (avoids the "manifest list/index" error):

```bash
sudo curl -SL \
  https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
docker buildx version
```

## 12. Install AWS CLI v2

Ubuntu 24.04 removed the apt `awscli` package, so install AWS CLI v2 from Amazon:

```bash
sudo apt install -y unzip curl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws
aws --version
```

## 13. Let the Jenkins user run Docker

```bash
sudo usermod -aG docker jenkins
```

## 14. Pre-create the deploy directory (owned by jenkins, no sudo in pipeline)

```bash
sudo mkdir -p /opt/hello-world-python
sudo chown jenkins:jenkins /opt/hello-world-python
```

## 15. Add 2 GB swap (OOM safety net for small instances)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
```

## 16. Restart Jenkins so it picks up the new docker group

```bash
sudo systemctl restart jenkins
sleep 5
```

## 17. Verify as the Jenkins user

The Jenkins service runs as the `jenkins` Linux user, not as `ubuntu`. Always sanity-check as `jenkins`:

```bash
sudo -u jenkins docker version --format "Server: {{.Server.Version}}"
sudo -u jenkins docker compose version
sudo -u jenkins docker buildx version
sudo -u jenkins aws --version
```

All four should print version info with no permission or "unknown command" errors.

---

## Next steps (inside Jenkins UI)

1. **Manage Jenkins → Plugins → Available** — install: **Docker Pipeline**, **AWS Credentials**, **GitHub Integration**, **AnsiColor**, **Timestamper**. Restart Jenkins.
2. **Manage Jenkins → Credentials → Add** → kind **AWS Credentials**, ID **`aws-ecr-creds`**, paste your IAM access key + secret.
3. **New Item → Pipeline** → name `hello-world-python-pipeline` → tick *GitHub hook trigger for GITScm polling* → Pipeline script from SCM → repo URL → branch `*/main` → script path `Jenkinsfile` → Save.
4. GitHub repo → **Settings → Webhooks → Add webhook** → Payload URL `http://<EC2_PUBLIC_IP>:8080/github-webhook/` → push events.

You're now ready to build.

---

## Troubleshooting one-liner table

| Symptom | Fix |
|---|---|
| `permission denied … /var/run/docker.sock` | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `docker: unknown command: docker compose` | Step 10 didn't actually install — re-run, check file is ~60 MB |
| `Unable to locate package docker-compose-plugin` / `awscli` | Use the binary installers (steps 10 + 12), NOT apt |
| `trying to push a manifest list/index …` | Install buildx (step 11), switch Jenkinsfile to `docker buildx build --push` |
| `sudo: a password is required` in pipeline | Pre-create the deploy dir (step 14), drop `sudo` from Jenkinsfile |
| EC2 freezes mid-build | Resize to t3.small/medium, add swap (step 15) |
