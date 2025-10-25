terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1️⃣ Check if the ECR repository exists
data "aws_ecr_repository" "existing" {
  name = "dev-scrum-frontend"

  # If it doesn't exist, ignore error
  lifecycle {
    ignore_errors = true
  }
}

# 2️⃣ Create ECR repository if missing
resource "aws_ecr_repository" "frontend_create" {
  count = data.aws_ecr_repository.existing.id != "" ? 0 : 1

  name                 = "dev-scrum-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 3️⃣ Determine ECR URL to use
locals {
  ecr_url = data.aws_ecr_repository.existing.id != "" ?
            data.aws_ecr_repository.existing.repository_url :
            aws_ecr_repository.frontend_create[0].repository_url
}

# 4️⃣ Build & push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

export DOCKER_BUILDKIT=0  # disable if Buildx is missing, or 1 if installed
ECR_URL="${local.ecr_url}"

# Git commit hash for tag
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

echo "Docker images pushed: latest and $IMAGE_TAG"
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 5️⃣ Output the ECR URL
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
