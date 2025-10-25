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
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1️⃣ External data source to check if ECR exists and get its URL
data "external" "check_ecr" {
  program = ["bash", "-c", <<EOT
repo_name="dev-scrum-frontend"
url=$(aws ecr describe-repositories --repository-names "$repo_name" --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "")
if [ -n "$url" ]; then
  echo "{\"exists\":\"true\", \"url\":\"$url\"}"
else
  echo "{\"exists\":\"false\", \"url\":\"\"}"
fi
EOT
  ]
}

# 2️⃣ Create ECR if missing
resource "aws_ecr_repository" "frontend_create" {
  count = data.external.check_ecr.result.exists == "true" ? 0 : 1

  name                 = "dev-scrum-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = false
}

# 3️⃣ Determine final ECR URL (existing or newly created)
locals {
  ecr_url = data.external.check_ecr.result.exists == "true" ?
            data.external.check_ecr.result.url :
            aws_ecr_repository.frontend_create[0].repository_url
}

# 4️⃣ Build & push Docker image
resource "null_resource" "docker_push" {
  triggers = {
    dockerfile_hash = filesha256("../Dockerfile")
    ecr_url         = local.ecr_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
export DOCKER_BUILDKIT=1

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

# 5️⃣ Output ECR repository URL
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
