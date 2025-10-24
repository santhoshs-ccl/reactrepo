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
# 1️⃣ Create ECR repository
resource "aws_ecr_repository" "frontend" {
  name = "dev-scrum-frontend"
}
# 2️⃣ Build & push Docker image to ECR after repo is created
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.frontend]
  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e
# Get ECR repository URL
ECR_URL=${aws_ecr_repository.frontend.repository_url}
echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
echo "Building Docker image..."
docker build -t dev-scrum-frontend:latest /home/ubuntu/angulartesting   #change directories only
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
  value = aws_ecr_repository.frontend.repository_url
}
