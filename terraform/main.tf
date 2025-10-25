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

# 1️⃣ Check if ECR repository already exists
data "aws_ecr_repository" "frontend" {
  count = 1
  name  = "dev-scrum-frontend-v2"
}

# 2️⃣ Create ECR repository only if it does NOT exist
resource "aws_ecr_repository" "frontend_create" {
  count                = length(data.aws_ecr_repository.frontend) == 0 ? 1 : 0
  name                 = "dev-scrum-frontend-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 3️⃣ Determine the ECR URL to use
locals {
  ecr_url = length(data.aws_ecr_repository.frontend) > 0 ?
            data.aws_ecr_repository.frontend[0].repository_url :
            aws_ecr_repository.frontend_create[0].repository_url
}

# 4️⃣ Build & push Docker image to ECR
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
docker build -t dev-scrum-frontend:latest ../   # Adjust path to your Dockerfile

echo "Tagging Docker image..."
docker tag dev-scrum-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 5️⃣ Output the ECR repository URL
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
