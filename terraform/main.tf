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

# ✅ Flag to control creation
variable "create_ecr" {
  type    = bool
  default = true
}

# 1️⃣ Create ECR repository only if it doesn't exist
resource "aws_ecr_repository" "frontend" {
  count = var.create_ecr ? 1 : 0  # skip creation if false

  name                 = "dev-scrum-frontend-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 2️⃣ Build & push Docker image after repo creation
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.frontend]

  triggers = {
    ecr_url = var.create_ecr ? aws_ecr_repository.frontend[0].repository_url : "EXISTS"
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# Determine ECR URL
if [ "${self.triggers.ecr_url}" = "EXISTS" ]; then
  ECR_URL=$(aws ecr describe-repositories --repository-names dev-scrum-frontend-v2 \
    --query "repositories[0].repositoryUri" --output text)
else
  ECR_URL="${self.triggers.ecr_url}"
fi

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

# 3️⃣ Output the ECR URL
output "ecr_repository_url" {
  value       = var.create_ecr ? aws_ecr_repository.frontend[0].repository_url : aws_ecr_repository.frontend[0].repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
