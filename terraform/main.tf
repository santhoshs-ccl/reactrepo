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

# 1️⃣ Create ECR repository (use force_delete=false to avoid accidental deletion)
resource "aws_ecr_repository" "frontend" {
  name                 = "dev-scrum-frontend-v2"  # unique repo name
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

# Enable Docker BuildKit (recommended)
export DOCKER_BUILDKIT=1

# Get ECR repository URL
ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
# Adjust path to your Dockerfile location
docker build -t dev-scrum-frontend:latest ../

echo "Tagging Docker image..."
docker tag dev-scrum-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# 3️⃣ Output ECR repository URL
output "ecr_repository_url" {
  value       = aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
