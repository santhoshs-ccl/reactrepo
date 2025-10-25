terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1️⃣ Use an existing ECR repository
data "aws_ecr_repository" "frontend" {
  name = "dev-scrum-frontend"   # existing repository name
}

# 2️⃣ Build & push Docker image to existing ECR repo
# Triggered when Dockerfile or source code changes
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")       # Dockerfile changes
    code_hash       = filesha256("../src")             # source code changes
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# ECR repository URL
ECR_URL="${data.aws_ecr_repository.frontend.repository_url}"

# Image tag using Git commit hash (fallback to 'latest')
if command -v git &> /dev/null; then
  IMAGE_TAG=$(git rev-parse --short HEAD)
else
  IMAGE_TAG="latest"
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../   # adjust path to Dockerfile/context

echo "Tagging Docker image..."
docker tag dev-scrum-frontend:latest $ECR_URL:latest
docker tag dev-scrum-frontend:latest $ECR_URL:$IMAGE_TAG

echo "Pushing Docker images..."
docker push $ECR_URL:latest
docker push $ECR_URL:$IMAGE_TAG

echo "Docker images pushed: latest and $IMAGE_TAG"
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 3️⃣ Output the ECR repository URL
output "ecr_repository_url" {
  value       = data.aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend Docker image"
}

# 4️⃣ Output Dockerfile + source code hash to track changes
output "dockerfile_hash" {
  value       = null_resource.docker_push.triggers.dockerfile_hash
  description = "Hash of Dockerfile used for last Docker push (changes trigger push)"
}

output "code_hash" {
  value       = null_resource.docker_push.triggers.code_hash
  description = "Hash of source code folder used for last Docker push"
}
