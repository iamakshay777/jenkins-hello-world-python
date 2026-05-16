# 20 Common Jenkins Interview Questions (2025-26)

Short, plain-English answers. Aimed at junior / mid-level DevOps interviews.

---

### 1. What is Jenkins, and why do teams use it?

Jenkins is an open-source automation server. Teams use it to **build, test, and deploy code** automatically whenever someone pushes to Git, so humans don't run those steps by hand. It's the most widely deployed CI/CD tool because it's free, has 1,800+ plugins, and runs anywhere Java runs.

### 2. What is the difference between CI, Continuous Delivery, and Continuous Deployment?

- **CI (Continuous Integration):** every commit triggers a build + tests.
- **Continuous Delivery:** every passing build is *ready* to ship, but a human clicks "deploy".
- **Continuous Deployment:** every passing build *automatically* ships to production, no human gate.

### 3. Freestyle job vs Pipeline job — when do you pick which?

- **Freestyle** = all configured in the web UI, no code. Fine for one-off, simple jobs.
- **Pipeline** = defined in a `Jenkinsfile` checked into Git. Version-controlled, reviewable, reusable. Use Pipeline for anything you care about.

### 4. What is a `Jenkinsfile`?

A text file (Groovy syntax) checked into your repo's root that defines your CI/CD pipeline as code. Jenkins reads it on every build, so changing pipeline logic = a normal pull request, not a UI click.

### 5. Declarative vs Scripted pipeline?

- **Declarative** — newer, opinionated structure (`pipeline { agent ... stages { ... } }`). Easier to read, catches errors early. Use this by default.
- **Scripted** — older, pure Groovy (`node { stage(...) { ... } }`). More flexible but harder to maintain. Only reach for it when Declarative truly can't express what you need.

### 6. What do `stages`, `steps`, and `post` mean in a pipeline?

- `stages` — the ordered phases of your pipeline (Checkout, Build, Test, Deploy).
- `steps` — the actual commands inside a stage (`sh '...'`, `checkout scm`).
- `post` — hooks that run *after* all stages (`always`, `success`, `failure`); great for cleanup or notifications.

### 7. List the ways to trigger a Jenkins job.

1. Manual click — "Build Now"
2. **SCM polling** — Jenkins checks Git on a cron
3. **Webhook** — GitHub / GitLab / Bitbucket POSTs to Jenkins on every push (preferred)
4. **Cron schedule** — `triggers { cron('H 2 * * *') }`
5. **Upstream/downstream** — one job triggers another on success
6. **Remote API** — POST to `…/build?token=X` from any script

### 8. How exactly does a GitHub webhook trigger a Jenkins build?

GitHub → POST JSON to `http://<jenkins>:8080/github-webhook/` → Jenkins **GitHub plugin** parses it → matches the payload's repo URL against jobs that have *GitHub hook trigger for GITScm polling* enabled → those jobs queue a build.

### 9. Controller vs Agent (was: Master vs Slave) — what's the difference?

- **Controller** — the Jenkins brain: web UI, scheduler, config store. Should ideally not run heavy builds.
- **Agent** — a worker node that actually executes build steps. Each agent has *executors* (parallel slots).
Splitting them lets you scale builds horizontally and isolate noisy workloads.

### 10. How do you add a build agent?

Manage Jenkins → **Nodes → New Node** → name + #executors + remote root dir + launch method (SSH, JNLP, or Docker/Kubernetes cloud). For dynamic agents, use the EC2 / Kubernetes / Docker plugin under **Clouds**.

### 11. Name 5 plugins you'd install on any serious Jenkins box.

1. **Pipeline** — Pipeline-as-code support
2. **Git** — Git SCM integration
3. **Docker Pipeline** — `docker build/push/run` from Jenkinsfile
4. **AWS Credentials / Pipeline: AWS Steps** — for ECR, S3, etc.
5. **GitHub Integration** — webhook trigger via `githubPush()`

(Honorable mentions: Blue Ocean for UI, Slack Notification, Configuration as Code.)

### 12. How does Jenkins store credentials, and how do you use them in a pipeline?

Manage Jenkins → **Credentials** stores them encrypted on disk. Common kinds: username/password, SSH private key, secret text, AWS keys, secret file. In a Jenkinsfile, bind them inside a `withCredentials` block — values become env vars only inside that block, and Jenkins masks them in logs.

### 13. What does `withCredentials` do?

It safely injects a stored credential into env vars for the duration of a block, then unsets them afterwards. Example:

```groovy
withCredentials([usernamePassword(credentialsId: 'gh-token',
                                  usernameVariable: 'U',
                                  passwordVariable: 'P')]) {
    sh 'curl -u $U:$P https://api.github.com/...'
}
```

### 14. How do you define environment variables in a Jenkinsfile?

Three ways:
- **Pipeline-wide** — top-level `environment { KEY = 'value' }` block.
- **Stage-level** — `environment {}` inside a `stage`.
- **Step-level** — `withEnv(['KEY=val']) { sh '...' }` for one block only.
Jenkins also provides built-ins: `env.BUILD_NUMBER`, `env.BRANCH_NAME`, `env.WORKSPACE`, etc.

### 15. What is a Multibranch Pipeline and when do you use it?

A job type that auto-discovers every branch (and optionally every PR) in a repo and creates a sub-job per branch. Use it when each branch needs its own pipeline runs — typical for trunk-based or feature-branch workflows.

### 16. What is a Jenkins Shared Library?

A separate Git repo containing reusable Groovy code (variables, classes, custom DSL steps). Configure it once in **Manage Jenkins → System → Global Pipeline Libraries**, then any Jenkinsfile can `@Library('my-lib') _` and call its functions. Stops 100 repos copy-pasting the same 200 lines of Jenkinsfile.

### 17. How do you run things in parallel in a pipeline?

```groovy
stage('Tests') {
    parallel {
        stage('Unit')        { steps { sh 'pytest tests/unit'  } }
        stage('Integration') { steps { sh 'pytest tests/integ' } }
    }
}
```

Each branch needs its own executor. Speeds up CI a lot for test-heavy projects.

### 18. How do you back up Jenkins?

Back up `$JENKINS_HOME` — that single directory holds jobs, config, plugins, credentials, build history. Two common strategies:
- **Filesystem snapshot** (rsync, EBS snapshot) on a schedule.
- **ThinBackup / Backup plugin** for scheduled, retained backups.
Bonus: keep all job configs as **Configuration as Code (JCasC)** YAML in Git so you can rebuild Jenkins from scratch.

### 19. Five security best practices for Jenkins.

1. Enable **authentication** + role-based authorization (don't leave "anyone can do anything").
2. Run Jenkins **behind HTTPS** (nginx/caddy reverse proxy with Let's Encrypt).
3. Lock SSH/8080 in the security group to **specific IPs** when possible.
4. Use **least-privilege IAM** for cloud credentials stored in Jenkins.
5. **Rotate credentials** regularly; never paste secrets directly in Jenkinsfiles — use the credentials store.

### 20. A pipeline keeps failing at one stage. How do you debug it?

1. Open the **build console output** — read from the *first* error, not the last.
2. Tick **Restart from Stage** to re-run only the broken stage instead of waiting for everything.
3. Reproduce the failing command **on the agent host** as the `jenkins` user (e.g. `sudo -u jenkins <cmd>`) — most CI bugs are user/permission issues.
4. Add `sh 'set -eux; ...'` so every command echoes before running.
5. If the stage uses credentials, check that the `credentialsId` exists and matches the Jenkinsfile string exactly.
6. Last resort: SSH into the agent and look at `$JENKINS_HOME/workspace/<job>/` — the workspace files are still there after a failure.

---

## Bonus practical question — likely to come up in a DevOps interview

> *"Walk me through a Jenkins pipeline that builds a Docker image and pushes it to AWS ECR."*

**Short answer (what to say):**

1. Trigger: GitHub webhook → `githubPush()` in Jenkinsfile.
2. **Checkout** stage: `checkout scm`.
3. **Build & push** stage: wrap in `withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-ecr-creds']])`. Inside:
   - `aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY`
   - `docker buildx build --platform linux/amd64 --provenance=false --sbom=false -t $REGISTRY/$REPO:$BUILD_NUMBER --push .`
4. **Deploy** stage: SSH to the target or call `docker compose pull && up -d` locally.
5. **Smoke test** stage: `curl /health`, fail the build if it doesn't return 200.
6. **post.always**: `docker image prune -f`.

Mention buildx because the legacy `docker push` breaks on Docker 25+ with multi-arch base images.
