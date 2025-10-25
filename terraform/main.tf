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

# 1️⃣ Create ECR repository (keep name stable)
resource "aws_ecr_repository" "frontend" {
  name                 = "dev-scrum-frontend"  # stable repo name
  image_tag_mutability = "MUTABLE"
  force_delete         = false   # prevents deletion if images exist
}

# 2️⃣ Build & push Docker image to ECR after repo creation
# Triggered only when Dockerfile or build context changes
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.frontend]

  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")   # change path if Dockerfile is elsewhere
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# ECR repository URL
ECR_URL="${aws_ecr_repository.frontend.repository_url}"

# Image tag using Git commit hash (versioned)
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

# 3️⃣ Output the ECR URL
output "ecr_repository_url" {
  value       = aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}

# 4️⃣ Optional: Output last pushed image tag
output "docker_image_tag" {
  value       = null_resource.docker_push.triggers.dockerfile_hash
  description = "Hash of Dockerfile used for last push (changes trigger push)"
}
