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

# 1️⃣ Create ECR repository (new unique name, no force deletion)
resource "aws_ecr_repository" "frontend" {
  name                 = "dev-scrum-frontend-v2"  # new unique name
  image_tag_mutability = "MUTABLE"
  force_delete         = false   # prevents deletion if images exist
}

# 2️⃣ Build & push Docker image to ECR after repo creation
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.frontend]

  triggers = {
    ecr_url = aws_ecr_repository.frontend.repository_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# Get ECR repository URL
ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
# Use relative path from Terraform working directory
docker build -t dev-scrum-frontend:latest ../   # Adjust if Dockerfile is elsewhere

echo "Tagging Docker image..."
docker tag dev-scrum-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 3️⃣ Output the ECR URL
output "ecr_repository_url" {
  value       = aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
