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

###############################
# 1️⃣ Try to get existing ECR repository
###############################
data "aws_ecr_repository" "existing" {
  count = 1

  name = "dev-scrum-frontend"

  # Wrap in try() to avoid errors if repo doesn't exist
  lifecycle {
    ignore_errors = true
  }
}

###############################
# 2️⃣ Create ECR repository only if missing
###############################
resource "aws_ecr_repository" "create_if_missing" {
  count = length(data.aws_ecr_repository.existing) > 0 ? 0 : 1

  name                 = "dev-scrum-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

###############################
# 3️⃣ Use existing or newly created repository URL
###############################
locals {
  ecr_url = length(data.aws_ecr_repository.existing) > 0 ?
            data.aws_ecr_repository.existing[0].repository_url :
            aws_ecr_repository.create_if_missing[0].repository_url
}

###############################
# 4️⃣ Build & push Docker image
###############################
resource "null_resource" "docker_push" {
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
IMAGE_TAG=$(git rev-parse --short HEAD || echo "latest")

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../

echo "Tagging Docker image..."
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

###############################
# 5️⃣ Output the repository URL
###############################
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
