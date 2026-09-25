terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "taskflow-tfstate-935710521571"  =
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"                 
    dynamodb_table = "taskflow-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "TaskFlow"
      Environment = "prod"
      ManagedBy   = "Terraform"
    }
  }
}