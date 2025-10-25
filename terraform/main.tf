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

# 1️⃣ Try to read existing ECR repository
data "aws_ecr_repository" "frontend_existing" {
  # This will fail if repo doesn't exist, so we handle that in the create step
  for_each = try({ for r in ["dev-scrum-frontend"] : r => r }, {})
  name     = each.key
}

# 2️⃣ Create ECR repository only if it doesn't exist
resource "aws_ecr_repository" "frontend_create" {
  for_each = length(keys(data.aws_ecr_repository.frontend_existing)) == 0 ? { "dev-scrum-frontend" = "dev-scrum-frontend" } : {}

  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 3️⃣ Determine which ECR URL to use
locals {
  ecr_url = length(keys(data.aws_ecr_repository.frontend_existing)) != 0 ?
            data.aws_ecr_repository.frontend_existing["dev-scrum-frontend"].repository_url :
            aws_ecr_repository.frontend_create["dev-scrum-frontend"].repository_url
}

# 4️⃣ Build & push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")  # Adjust path to your Dockerfile
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

export DOCKER_BUILDKIT=1
ECR_URL="${local.ecr_url}"

# Use Git commit hash as image tag if available
if command -v git &> /dev/null; then
  IMAGE_TAG=$(git rev-parse --short HEAD)
else
  IMAGE_TAG="latest"
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../   # Adjust path to Dockerfile/context

echo "Tagging Docker image..."
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

# 5️⃣ Output ECR URL
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}

# 6️⃣ Optional: Output Dockerfile hash for tracking
output "dockerfile_hash" {
  value       = null_resource.docker_push.triggers.dockerfile_hash
  description = "Hash of Dockerfile used for last Docker push (changes trigger push)"
}
