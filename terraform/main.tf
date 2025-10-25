terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# 1️⃣ Create ECR if missing
# ----------------------------
resource "null_resource" "ecr_create_if_missing" {
  triggers = {
    repo_name = "dev-scrum-frontend"
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

REPO_NAME="dev-scrum-frontend"

# Check if repo exists
if aws ecr describe-repositories --repository-names $REPO_NAME > /dev/null 2>&1; then
  echo "ECR repository $REPO_NAME already exists."
else
  echo "Creating ECR repository $REPO_NAME..."
  aws ecr create-repository --repository-name $REPO_NAME
fi
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ----------------------------
# 2️⃣ Determine ECR URL
# ----------------------------
locals {
  ecr_url = chomp(trimspace(shell("aws ecr describe-repositories --repository-names dev-scrum-frontend --query 'repositories[0].repositoryUri' --output text")))
}

# ----------------------------
# 3️⃣ Build & push Docker image
# ----------------------------
resource "null_resource" "docker_push" {
  depends_on = [null_resource.ecr_create_if_missing]

  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")
    ecr_url         = local.ecr_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
export DOCKER_BUILDKIT=1

ECR_URL="${local.ecr_url}"

# Git commit hash for tagging
if command -v git &> /dev/null; then
  IMAGE_TAG=$(git rev-parse --short HEAD)
else
  IMAGE_TAG="latest"
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../

docker tag dev-scrum-frontend:latest $ECR_URL:latest
docker tag dev-scrum-frontend:latest $ECR_URL:$IMAGE_TAG

echo "Pushing Docker image..."
docker push $ECR_URL:latest
docker push $ECR_URL:$IMAGE_TAG

echo "✅ Docker images pushed: latest and $IMAGE_TAG"
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ----------------------------
# 4️⃣ Output ECR URL
# ----------------------------
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
