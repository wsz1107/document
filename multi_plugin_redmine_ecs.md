# 🚀 Simplifying Redmine Plugin Deployment to AWS ECS Without CodePipeline

When you’re building a plugin for Redmine, it’s tempting to over-engineer the deployment pipeline. AWS CodePipeline, CodeBuild, ECS blue-green deployments — they all sound great until you realize… you don’t actually need them.  

If your team isn’t actively developing Redmine itself and only needs to **occasionally build and deploy** your plugin as part of a Redmine Docker image, you can do everything **locally** and push straight to **Amazon ECR** and **ECS**.  

Here’s how to structure your repository and automate the process without adding unnecessary AWS complexity.

---

## 💡 The Simplified Goal

We want to:

- Build a custom Docker image based on Redmine.  
- Include our plugin code in that image.  
- Push the image to Amazon ECR.  
- Deploy it to Amazon ECS (Fargate or EC2-backed cluster).  

All done locally — no CodePipeline, no CodeBuild.

---

## 🧱 Project Structure

Keep everything in **one Git repository**, with deployment artifacts under a `deploy/` directory:

```
redmine-plugin-for-jira/
├─ init.rb
├─ app/
├─ lib/
└─ deploy/
   ├─ Dockerfile
   ├─ ecs-taskdef.json
   ├─ compose.dev.yml          # optional (local testing)
   └─ scripts/
      ├─ ecr-login.sh
      ├─ build-push.sh
      └─ ecs-deploy.sh
```

This keeps the plugin self-contained — source code, deployment scripts, and infrastructure bits all in one place.

---

## 🐳 Step 1: Create the Dockerfile

`deploy/Dockerfile` builds a Redmine image with your plugin included.

```dockerfile
FROM redmine:5.1-alpine

RUN mkdir -p /usr/src/redmine/plugins
COPY ../ /usr/src/redmine/plugins/redmine-plugin-for-jira/

WORKDIR /usr/src/redmine
# If your plugin needs extra gems:
# RUN bundle install --without development test
```

When you build this image, it will already contain your plugin under `/usr/src/redmine/plugins/`.

---

## 🧩 Step 2: Local Development (Optional)

You can use Docker Compose to run Redmine locally with your plugin mounted as a volume.

`deploy/compose.dev.yml`

```yaml
services:
  redmine:
    image: redmine:5.1
    ports: [ "3000:3000" ]
    volumes:
      - ../:/usr/src/redmine/plugins/redmine-plugin-for-jira:ro
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: redmine
      POSTGRES_USER: redmine
      POSTGRES_DB: redmine
```

Run:

```bash
docker compose -f deploy/compose.dev.yml up
```

You’ll have Redmine running at [http://localhost:3000](http://localhost:3000) with your plugin live-mounted.

---

## 🔐 Step 3: Log in to Amazon ECR

`deploy/scripts/ecr-login.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
REGION="${1:-ap-northeast-1}"
aws ecr get-login-password --region "$REGION"   | docker login --username AWS --password-stdin "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$REGION.amazonaws.com"
```

Usage:

```bash
./deploy/scripts/ecr-login.sh ap-northeast-1
```

---

## 🧱 Step 4: Build and Push the Image

`deploy/scripts/build-push.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-ap-northeast-1}"
REPO_NAME="${2:-redmine-custom}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Ensure repository exists
aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$REGION" >/dev/null 2>&1   || aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" >/dev/null

IMAGE_TAG="$(git rev-parse --short HEAD)-$(date +%Y%m%d%H%M)"
IMAGE_URI="${ECR}/${REPO_NAME}:${IMAGE_TAG}"

docker build -t "$IMAGE_URI" -f deploy/Dockerfile .
docker push "$IMAGE_URI"

echo "IMAGE_URI=${IMAGE_URI}"
```

Usage:

```bash
./deploy/scripts/build-push.sh ap-northeast-1 redmine-custom
```

Output example:

```
IMAGE_URI=123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/redmine-custom:4f7a2e1-20251110
```

---

## 🚀 Step 5: Deploy to ECS

`deploy/scripts/ecs-deploy.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ecs-deploy.sh <cluster> <service> <image-uri> [region]
CLUSTER="$1"
SERVICE="$2"
IMAGE_URI="$3"
REGION="${4:-ap-northeast-1}"

aws ecs update-service   --cluster "$CLUSTER"   --service "$SERVICE"   --force-new-deployment   --region "$REGION"

echo "Triggered new deployment for ${SERVICE} on ${CLUSTER} with image ${IMAGE_URI}"
```

Usage:

```bash
./deploy/scripts/ecs-deploy.sh my-ecs-cluster redmine-service   123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/redmine-custom:4f7a2e1-20251110
```

ECS will pull the new image and roll out a fresh task revision automatically.

---

## 🧠 Why This Simpler Setup Works Well

| Feature | Approach |
|----------|-----------|
| Source code | Single repo (plugin + deploy scripts) |
| Build | Local Docker CLI |
| Artifact | Image pushed to ECR |
| Deployment | Manual or scripted ECS update |
| CI/CD overhead | None |
| Repeatability | High — all build logic scripted |

For occasional plugin updates, this is **lightweight, transparent, and maintainable**.  
You can always move to CodePipeline or CodeBuild later if the project grows.

---

## 🏁 Summary

You don’t need a full AWS CI/CD stack just to ship a Redmine plugin.  
By keeping deployment scripts and Docker configuration right inside your plugin repository, you can:

- Reproducibly build and publish Redmine images from your local machine.  
- Keep AWS artifacts versioned alongside your plugin code.  
- Deploy to ECS in minutes — no pipeline, no YAML jungle.  

Simple, fast, and perfect for small teams who just want their plugin running in production.

---

**Next step:** Try this once manually. Once it feels solid, you can later wrap these scripts into a Makefile or GitHub Action if you ever want light automation — without leaving this clean single-repo model.
