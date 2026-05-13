###############################################################################
# EduBridge Vietnam — Variables Definition
###############################################################################

# ─── General ─────────────────────────────────────────────────────────────────
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "edubridge"
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
  default     = "edubridge.vn"
}

# ─── VPC CIDR Blocks — Singapore ─────────────────────────────────────────────
variable "vpc_cidrs" {
  description = "CIDR blocks for VPCs in Singapore region"
  type        = map(string)
  default = {
    prod_app   = "10.10.0.0/16"
    prod_data  = "10.20.0.0/16"
    shared     = "10.30.0.0/16"
    inspection = "10.40.0.0/16"
    security   = "10.50.0.0/16"
  }
}

# ─── VPC CIDR Blocks — Sydney (DR) ──────────────────────────────────────────
variable "vpc_cidrs_dr" {
  description = "CIDR blocks for VPCs in Sydney DR region"
  type        = map(string)
  default = {
    dr_app  = "10.110.0.0/16"
    dr_data = "10.120.0.0/16"
  }
}

# ─── Client VPN ──────────────────────────────────────────────────────────────
variable "client_vpn_cidr" {
  description = "CIDR for Client VPN"
  type        = string
  default     = "172.16.0.0/22"
}

# ─── Transit Gateway ────────────────────────────────────────────────────────
variable "tgw_asn_singapore" {
  description = "BGP ASN for Transit Gateway in Singapore"
  type        = number
  default     = 64512
}

variable "tgw_asn_sydney" {
  description = "BGP ASN for Transit Gateway in Sydney"
  type        = number
  default     = 64513
}

# ─── Site-to-Site VPN — On-Premises Branches ────────────────────────────────
variable "on_prem_sites" {
  description = "On-premises site configurations for S2S VPN"
  type = map(object({
    name       = string
    cidr       = string
    bgp_asn    = number
    public_ip  = string
    users      = number
    device     = string
    bandwidth  = string
    isp        = string
  }))
  default = {
    hq_hcm = {
      name      = "HQ-HCM-Q10"
      cidr      = "192.168.10.0/24"
      bgp_asn   = 65010
      public_ip = "REPLACE_WITH_REAL_IP"   # FortiGate WAN IP
      users     = 35
      device    = "FortiGate-60F"
      bandwidth = "200Mbps"
      isp       = "FPT-DualWAN"
    }
    br_hn = {
      name      = "BR-HN-HoangMai"
      cidr      = "192.168.20.0/24"
      bgp_asn   = 65020
      public_ip = "REPLACE_WITH_REAL_IP"
      users     = 5
      device    = "FortiGate-40F"
      bandwidth = "100Mbps"
      isp       = "Viettel"
    }
    br_dn = {
      name      = "BR-DN-HaiChau"
      cidr      = "192.168.30.0/24"
      bgp_asn   = 65030
      public_ip = "REPLACE_WITH_REAL_IP"
      users     = 5
      device    = "FortiGate-40F"
      bandwidth = "100Mbps"
      isp       = "VNPT"
    }
  }
}

# ─── Availability Zones ─────────────────────────────────────────────────────
variable "azs_singapore" {
  description = "Availability Zones in Singapore"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "azs_sydney" {
  description = "Availability Zones in Sydney"
  type        = list(string)
  default     = ["ap-southeast-2a", "ap-southeast-2b"]
}

# ─── ECS / Compute ──────────────────────────────────────────────────────────
variable "ecs_app_config" {
  description = "ECS Fargate application configuration"
  type = object({
    cpu           = number
    memory        = number
    desired_count = number
    container_port = number
    image          = string
  })
  default = {
    cpu            = 512
    memory         = 1024
    desired_count  = 2
    container_port = 8080
    image          = "ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/edubridge-app:latest"
  }
}

# ─── Database ────────────────────────────────────────────────────────────────
# variable "aurora_config" {
#   description = "Aurora PostgreSQL configuration"
#   type = object({
#     engine_version  = string
#     instance_class  = string
#     instance_count  = number
#     database_name   = string
#     master_username = string
#     min_capacity    = number
#     max_capacity    = number
#   })
#   default = {
#     engine_version  = "15.4"
#     instance_class  = "db.serverless"
#     instance_count  = 2
#     database_name   = "edubridge"
#     master_username = "edubridge_admin"
#     min_capacity    = 0.5
#     max_capacity    = 4.0
#   }
# }
variable "rds_config" {
  description = "RDS PostgreSQL configuration"
  type = object({
    engine_version     = string
    instance_class     = string
    database_name      = string
    master_username    = string
    allocated_storage  = number
  })

  default = {
    engine_version     = "15"
    instance_class     = "db.t3.micro"
    database_name      = "edubridge"
    master_username    = "postgres"
    allocated_storage  = 20
  }
}

variable "redis_config" {
  description = "ElastiCache Redis configuration"
  type = object({
    node_type       = string
    num_cache_nodes = number
    engine_version  = string
  })
  default = {
    node_type       = "cache.r6g.large"
    num_cache_nodes = 2
    engine_version  = "7.0"
  }
}

# ─── Monitoring / Security ──────────────────────────────────────────────────
variable "enable_guardduty" {
  description = "Enable GuardDuty"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable Security Hub"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch log group retention for VPC Flow Logs"
  type        = number
  default     = 90
}

variable "s3_log_bucket_name" {
  description = "S3 bucket name for centralized logs"
  type        = string
  default     = "edubridge-security-logs"
}

# ─── CloudFront / WAF ───────────────────────────────────────────────────────
variable "waf_rate_limit" {
  description = "WAF rate limit per 5 minutes per IP"
  type        = number
  default     = 2000
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN for CloudFront (must be in us-east-1)"
  type        = string
  default     = ""
}

# ─── Tags ────────────────────────────────────────────────────────────────────
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
