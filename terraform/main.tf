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

# 1️⃣ Create or reference ECR repository
resource "aws_ecr_repository" "frontend" {
  # Use a unique name; Terraform will fail if the repo exists,
  # so we will handle existing repo via import or CI/CD check
  name                 = "dev-scrum-frontend-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 2️⃣ Build & push Docker image
resource "null_resource" "docker_push" {
  # Depends on the repository existing
  depends_on = [aws_ecr_repository.frontend]

  triggers = {
    # Trigger on repo URL changes (or new commits)
    ecr_url = aws_ecr_repository.frontend.repository_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# ECR repo URL
ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
# Build Docker image; adjust Dockerfile path as needed
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
