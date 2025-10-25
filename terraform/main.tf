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

# ----------------------------
# 1️⃣ External data source to get ECR URL
# ----------------------------
data "external" "ecr_info" {
  program = ["bash", "-c", <<EOT
repo="dev-scrum-frontend"
url=$(aws ecr describe-repositories --repository-names $repo --query "repositories[0].repositoryUri" --output text 2>/dev/null || echo "")
if [ -z "$url" ]; then
  echo "{\"exists\":\"false\",\"url\":\"\"}"
else
  echo "{\"exists\":\"true\",\"url\":\"$url\"}"
fi
EOT
  ]
}

# ----------------------------
# 2️⃣ Create ECR if missing
# ----------------------------
resource "null_resource" "ecr_create_if_missing" {
  count = data.external.ecr_info.result.exists == "true" ? 0 : 1

  triggers = {
    repo_name = "dev-scrum-frontend"
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
aws ecr create-repository --repository-name dev-scrum-frontend
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# ----------------------------
# 3️⃣ Determine ECR URL
# ----------------------------
data "external" "ecr_url_final" {
  depends_on = [null_resource.ecr_create_if_missing]
  program = ["bash", "-c", <<EOT
repo="dev-scrum-frontend"
url=$(aws ecr describe-repositories --repository-names $repo --query "repositories[0].repositoryUri" --output text)
echo "{\"url\":\"$url\"}"
EOT
  ]
}

locals {
  ecr_url = data.external.ecr_url_final.result.url
}

# ----------------------------
# 4️⃣ Build & push Docker image
# ----------------------------
resource "null_resource" "docker_push" {
  depends_on = [null_resource.ecr_create_if_missing]

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

# Use Git commit hash for tagging
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

# ----------------------------
# 5️⃣ Output ECR URL
# ----------------------------
output "ecr_repository_url" {
  value       = local.ecr_url
  description = "ECR repository URL for frontend Docker image"
}
