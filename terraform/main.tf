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
  name = "dev-test-react-frontend"
}

# Trigger Docker push after repo creation
resource "null_resource" "docker_push" {
  depends_on = [aws_ecr_repository.frontend]

  triggers = {
    ecr_url = aws_ecr_repository.frontend.repository_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

# Get the ECR URL from triggers
ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL


echo "Building Docker image..."
# Point to parent directory where Dockerfile exists
docker build -t dev-test-react-frontend:latest ..

echo "Tagging Docker image..."
docker tag dev-test-react-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Output the ECR URL in CI/CD-friendly format
output "ecr_repository_url" {
  value       = aws_ecr_repository.frontend.repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}
