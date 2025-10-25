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
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

###################################################
# 1️⃣ Check if ECR repository exists
###################################################
data "external" "check_ecr" {
  program = ["bash", "-c", <<EOT
repo_name="dev-scrum-frontend"
if aws ecr describe-repositories --repository-names "$repo_name" --region us-east-1 > /dev/null 2>&1; then
  echo "{\"exists\": \"true\"}"
else
  echo "{\"exists\": \"false\"}"
fi
EOT
  ]
}

###################################################
# 2️⃣ Create ECR repo only if missing
###################################################
resource "aws_ecr_repository" "frontend" {
  count = data.external.check_ecr.result.exists == "true" ? 0 : 1

  name                 = "dev-scrum-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

###################################################
# 3️⃣ Get existing ECR URL if repo exists
###################################################
data "aws_ecr_repository" "existing" {
  count = data.external.check_ecr.result.exists == "true" ? 1 : 0
  name  = "dev-scrum-frontend"
}

###################################################
# 4️⃣ Determine which URL to use (FIXED syntax)
###################################################
locals {
  ecr_url = (
    data.external.check_ecr.result.exists == "true" ?
    data.aws_ecr_repository.existing[0].repository_url :
    aws_ecr_repository.frontend[0].repository_url
  )
}

###################################################
# 5️⃣ Build & Push Docker image
###################################################
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")
    ecr_url         = local.ecr_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
export DOCKER_BUILDKIT=0
ECR_URL="${local.ecr_url}"

# Use Git commit hash if available
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

###################################################
# 6️⃣ Output repository URL
###################################################
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL used for Docker image"
}
