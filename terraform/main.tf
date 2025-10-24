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

# Create ECR repository
resource "aws_ecr_repository" "frontend" {
  name = "dev-react-frontend"
}

# Build & push Docker image to ECR after repo is created
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
docker build -t dev-react-frontend:latest /home/ubuntu/reactrepo

echo "Tagging Docker image..."
docker tag dev-react-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Output the ECR URL
output "ecr_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}
