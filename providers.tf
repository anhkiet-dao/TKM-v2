###############################################################################
# EduBridge Vietnam — AWS Multi-Region Network Architecture
# Providers Configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state — thay đổi theo môi trường thực tế
  backend "s3" {
    bucket         = "edubridge-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# ─── Primary Region: Singapore ───────────────────────────────────────────────
provider "aws" {
  region = "ap-southeast-1"

  default_tags {
    tags = {
      Project     = "EduBridge"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Company     = "EduBridge Vietnam"
    }
  }
}

# ─── DR Region: Sydney ──────────────────────────────────────────────────────
provider "aws" {
  alias  = "sydney"
  region = "ap-southeast-2"

  default_tags {
    tags = {
      Project     = "EduBridge"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Company     = "EduBridge Vietnam"
      Role        = "DR-PilotLight"
    }
  }
}

# ─── Global services (CloudFront, WAF, Route53) ─────────────────────────────
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "EduBridge"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Company     = "EduBridge Vietnam"
      Role        = "Global-Services"
    }
  }
}
