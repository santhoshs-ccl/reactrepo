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

# Try to get the repo if it exists
data "aws_ecr_repository" "frontend" {
  count = try(length(aws_ecr_repository.frontend_create), 0) == 0 ? 1 : 0
  name  = "dev-scrum-frontend-v2"
  # ignore if does not exist
  lifecycle {
    ignore_errors = true
  }
}

# Create the repo only if it does not exist
resource "aws_ecr_repository" "frontend_create" {
  count                = length(data.aws_ecr_repository.frontend) == 0 ? 1 : 0
  name                 = "dev-scrum-frontend-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# Determine repo URL dynamically
locals {
  ecr_url = length(data.aws_ecr_repository.frontend) > 0 ?
            data.aws_ecr_repository.frontend[0].repository_url :
            aws_ecr_repository.frontend_create[0].repository_url
}

# Build & push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    ecr_url = local.ecr_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

export DOCKER_BUILDKIT=1

ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../   # adjust path

echo "Tagging Docker image..."
docker tag dev-scrum-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Output ECR URL
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
