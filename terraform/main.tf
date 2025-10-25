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

# Try to read the repo if it exists
data "aws_ecr_repository" "frontend" {
  name = "dev-scrum-frontend-v2"
}

# Only create if not exists (ignore error if it exists)
resource "aws_ecr_repository" "frontend_create" {
  count                = length([for r in [data.aws_ecr_repository.frontend] : r if r.id == ""]) # 1 if repo does not exist
  name                 = "dev-scrum-frontend-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# Build & push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    ecr_url = coalesce(data.aws_ecr_repository.frontend.repository_url,
                        aws_ecr_repository.frontend_create[0].repository_url)
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
docker build -t dev-scrum-frontend:latest ../   # Adjust path to Dockerfile

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
  value       = coalesce(data.aws_ecr_repository.frontend.repository_url,
                          aws_ecr_repository.frontend_create[0].repository_url)
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
