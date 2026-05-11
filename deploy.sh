#!/usr/bin/env bash
set -euo pipefail

: "${ECR_REGISTRY:?ECR_REGISTRY is required}"
: "${ECR_REPO:?ECR_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${AWS_REGION:?AWS_REGION is required}"

echo ">>> Logging into ECR ${ECR_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

export ECR_REGISTRY ECR_REPO IMAGE_TAG

echo ">>> Pulling ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
docker compose pull

echo ">>> Rolling out new container"
docker compose up -d --remove-orphans

echo ">>> Active containers:"
docker compose ps

echo ">>> Done."
