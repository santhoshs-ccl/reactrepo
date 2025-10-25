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
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1️⃣ Check if ECR repo exists using external script
data "external" "check_ecr" {
  program = ["bash", "-c", <<EOT
repo_name="dev-scrum-frontend"
if aws ecr describe-repositories --repository-names "$repo_name" --region us-east-1 > /dev/null 2>&1; then
  echo "{\"exists\":\"true\"}"
else
  echo "{\"exists\":\"false\"}"
fi
EOT
  ]
}

# 2️⃣ Create ECR only if it does not exist
resource "aws_ecr_repository" "frontend_create" {
  count = data.external.check_ecr.result.exists == "true" ? 0 : 1
  name  = "dev-scrum-frontend"

  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 3️⃣ Determine which ECR URL to use
locals {
  ecr_url = data.external.check_ecr.result.exists == "true" ?
            aws_ecr_repository.frontend_create[0].repository_url : 
            aws_ecr_repository.frontend_create[0].repository_url
}

# 4️⃣ Docker build & push
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
export DOCKER_BUILDKIT=1

# Get repository URL
ECR_URL=$(aws ecr describe-repositories --repository-names "dev-scrum-frontend" --query "repositories[0].repositoryUri" --output text)

# Git commit hash for tagging
if command -v git &> /dev/null; then
  IMAGE_TAG=$(git rev-parse --short HEAD)
else
  IMAGE_TAG="latest"
fi

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest ../

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

# 5️⃣ Output repository URL
output "ecr_repository_url" {
  value       = ECR_URL
  description = "ECR repository URL for frontend Docker image"
}
