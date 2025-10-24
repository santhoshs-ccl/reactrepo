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

# Create a new ECR repository
resource "aws_ecr_repository" "frontend_new" {
  name = "dev-new-react-frontend"   # NEW repository name
  force_delete = false              # Keep old images safe
}

# Trigger Docker push after repo creation or repo URL change
resource "null_resource" "docker_push" {
  # Run whenever the ECR URL changes
  triggers = {
    ecr_url = aws_ecr_repository.frontend_new.repository_url
  }

  provisioner "local-exec" {
    command = <<EOT
#!/bin/bash
set -e

ECR_URL="${self.triggers.ecr_url}"

echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

echo "Building Docker image..."
# Make sure Dockerfile path is correct
docker build -t dev-new-react-frontend:latest ..

echo "Tagging Docker image..."
docker tag dev-new-react-frontend:latest $ECR_URL:latest

echo "Pushing Docker image..."
docker push $ECR_URL:latest
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Output the new ECR URL
output "ecr_repository_url" {
  value       = aws_ecr_repository.frontend_new.repository_url
  description = "ECR repository URL for frontend Docker image"
  sensitive   = false
}

