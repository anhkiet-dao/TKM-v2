###############################################################################
# EduBridge Vietnam — Main Orchestration
# AWS Multi-Region Network Architecture
###############################################################################

locals {
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

data "aws_caller_identity" "current" {}

# ═══════════════════════════════════════════════════════════════════════════════
# VPC IPAM
# ═══════════════════════════════════════════════════════════════════════════════
module "ipam" {
  source       = "./modules/ipam"
  project_name = var.project_name
  environment  = var.environment
  regions      = ["ap-southeast-1", "ap-southeast-2"]
  tags         = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# SINGAPORE — VPCs
# ═══════════════════════════════════════════════════════════════════════════════

# ─── VPC-PROD-APP (10.10.0.0/16) ────────────────────────────────────────────
module "vpc_prod_app" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-PROD-APP"
  vpc_cidr              = var.vpc_cidrs["prod_app"]
  azs                   = var.azs_singapore
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = true
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags
}

# ─── VPC-PROD-DATA (10.20.0.0/16) ───────────────────────────────────────────
module "vpc_prod_data" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-PROD-DATA"
  vpc_cidr              = var.vpc_cidrs["prod_data"]
  azs                   = var.azs_singapore
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = false
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags
}

# ─── VPC-SHARED (10.30.0.0/16) — AD, Resolver, SSM, Jenkins ────────────────
module "vpc_shared" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-SHARED"
  vpc_cidr              = var.vpc_cidrs["shared"]
  azs                   = var.azs_singapore
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = false
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags
}

# ─── VPC-INSPECTION (10.40.0.0/16) — Network FW, NAT GW ────────────────────
module "vpc_inspection" {
  source                  = "./modules/vpc"
  vpc_name                = "VPC-INSPECTION"
  vpc_cidr                = var.vpc_cidrs["inspection"]
  azs                     = var.azs_singapore
  environment             = var.environment
  project_name            = var.project_name
  create_public_subnets   = true
  create_private_subnets  = true
  create_tgw_subnets      = true
  create_firewall_subnets = false
  enable_flow_logs        = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                    = local.common_tags
}

# ─── VPC-SECURITY (10.50.0.0/16) — Observability + Compliance ───────────────
module "vpc_security" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-SECURITY"
  vpc_cidr              = var.vpc_cidrs["security"]
  azs                   = var.azs_singapore
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = false
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# SYDNEY (DR) — VPCs
# ═══════════════════════════════════════════════════════════════════════════════

# ─── VPC-DR-APP (10.110.0.0/16) — DesiredCount = 0 ─────────────────────────
module "vpc_dr_app" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-DR-APP"
  vpc_cidr              = var.vpc_cidrs_dr["dr_app"]
  azs                   = var.azs_sydney
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = true
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags

  providers = { aws = aws.sydney }
}

# ─── VPC-DR-DATA (10.120.0.0/16) ───────────────────────────────────────────
module "vpc_dr_data" {
  source                = "./modules/vpc"
  vpc_name              = "VPC-DR-DATA"
  vpc_cidr              = var.vpc_cidrs_dr["dr_data"]
  azs                   = var.azs_sydney
  environment           = var.environment
  project_name          = var.project_name
  create_public_subnets = false
  create_private_subnets = true
  create_tgw_subnets    = true
  enable_flow_logs      = true
  flow_log_retention_days = var.flow_log_retention_days
  tags                  = local.common_tags

  providers = { aws = aws.sydney }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TRANSIT GATEWAY — Singapore
# ═══════════════════════════════════════════════════════════════════════════════
module "tgw_sg" {
  source       = "./modules/tgw"
  project_name = var.project_name
  environment  = var.environment
  tgw_asn      = var.tgw_asn_singapore
  tgw_name     = "TGW-SG"
  tags         = local.common_tags

  vpc_attachments = {
    prod_app = {
      vpc_id     = module.vpc_prod_app.vpc_id
      subnet_ids = module.vpc_prod_app.tgw_subnet_ids
    }
    prod_data = {
      vpc_id     = module.vpc_prod_data.vpc_id
      subnet_ids = module.vpc_prod_data.tgw_subnet_ids
    }
    shared = {
      vpc_id     = module.vpc_shared.vpc_id
      subnet_ids = module.vpc_shared.tgw_subnet_ids
    }
    inspection = {
      vpc_id                 = module.vpc_inspection.vpc_id
      subnet_ids             = module.vpc_inspection.tgw_subnet_ids
    }
    security = {
      vpc_id     = module.vpc_security.vpc_id
      subnet_ids = module.vpc_security.tgw_subnet_ids
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TRANSIT GATEWAY — Sydney
# ═══════════════════════════════════════════════════════════════════════════════
module "tgw_sy" {
  source       = "./modules/tgw"
  project_name = var.project_name
  environment  = var.environment
  tgw_asn      = var.tgw_asn_sydney
  tgw_name     = "TGW-SY"
  tags         = local.common_tags

  providers = { aws = aws.sydney }

  vpc_attachments = {
    dr_app = {
      vpc_id     = module.vpc_dr_app.vpc_id
      subnet_ids = module.vpc_dr_app.tgw_subnet_ids
    }
    dr_data = {
      vpc_id     = module.vpc_dr_data.vpc_id
      subnet_ids = module.vpc_dr_data.tgw_subnet_ids
    }
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# TGW INTER-REGION PEERING (Singapore ↔ Sydney)
# ═══════════════════════════════════════════════════════════════════════════════
resource "aws_ec2_transit_gateway_peering_attachment" "sg_to_sy" {
  peer_region             = "ap-southeast-2"
  peer_transit_gateway_id = module.tgw_sy.tgw_id
  transit_gateway_id      = module.tgw_sg.tgw_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-tgw-peering-sg-sy"
    Cost = "$0.02/GB"
  })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "sy_accept" {
  provider                      = aws.sydney
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.sg_to_sy.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-tgw-peering-sy-accept"
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# NAT GATEWAY — VPC-INSPECTION (Centralized Egress, 1 per AZ)
# ═══════════════════════════════════════════════════════════════════════════════
resource "aws_eip" "nat" {
  count  = length(var.azs_singapore)
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip-${var.azs_singapore[count.index]}"
  })
}

resource "aws_nat_gateway" "inspection" {
  count         = length(var.azs_singapore)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = module.vpc_inspection.public_subnet_ids[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-gw-${var.azs_singapore[count.index]}"
  })

  depends_on = [module.vpc_inspection]
}


# ═══════════════════════════════════════════════════════════════════════════════
# COMPUTE — ECS Fargate (Singapore Primary)
# ═══════════════════════════════════════════════════════════════════════════════
module "compute_primary" {
  source             = "./modules/compute"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc_prod_app.vpc_id
  public_subnet_ids  = module.vpc_prod_app.public_subnet_ids
  private_subnet_ids = module.vpc_prod_app.private_subnet_ids
  ecs_config         = var.ecs_app_config
  acm_certificate_arn = var.acm_certificate_arn
  is_dr              = false
  tags               = local.common_tags
}


# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE — Aurora Global + ElastiCache Redis (Singapore)
# ═══════════════════════════════════════════════════════════════════════════════
module "database_primary" {
  source             = "./modules/database"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc_prod_data.vpc_id
  private_subnet_ids = module.vpc_prod_data.private_subnet_ids

  rds_config = var.rds_config

  redis_config = var.redis_config

  allowed_security_group_ids = [
    module.compute_primary.ecs_security_group_id
  ]

  tags = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# SHARED SERVICES — AD, Resolver, SSM, Jenkins
# ═══════════════════════════════════════════════════════════════════════════════
module "shared_services" {
  source             = "./modules/shared"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc_shared.vpc_id
  private_subnet_ids = module.vpc_shared.private_subnet_ids
  vpc_cidr           = var.vpc_cidrs["shared"]
  on_prem_cidrs      = [for s in var.on_prem_sites : s.cidr]
  tags               = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY — GuardDuty, Security Hub, S3 Logs
# ═══════════════════════════════════════════════════════════════════════════════
module "security" {
  source              = "./modules/security"
  project_name        = var.project_name
  environment         = var.environment
  # enable_guardduty    = var.enable_guardduty
  # enable_security_hub = var.enable_security_hub
  s3_log_bucket_name  = var.s3_log_bucket_name
  tags                = local.common_tags
  enable_guardduty    = false
  enable_security_hub = false
}

# ═══════════════════════════════════════════════════════════════════════════════
# VPN — Client VPN + S2S VPN to FortiGate branches
# ═══════════════════════════════════════════════════════════════════════════════
module "vpn" {
  source          = "./modules/vpn"
  project_name    = var.project_name
  environment     = var.environment
  vpc_id          = module.vpc_prod_app.vpc_id
  subnet_ids      = module.vpc_prod_app.private_subnet_ids
  client_vpn_cidr = var.client_vpn_cidr
  tgw_id          = module.tgw_sg.tgw_id
  on_prem_sites   = var.on_prem_sites
  tags            = local.common_tags
}

# ═══════════════════════════════════════════════════════════════════════════════
# CDN — CloudFront + WAF (deployed in us-east-1)
# ═══════════════════════════════════════════════════════════════════════════════
module "cdn" {
  source              = "./modules/cdn"
  project_name        = var.project_name
  environment         = var.environment
  domain_name         = var.domain_name
  alb_dns_name        = module.compute_primary.alb_dns_name
  s3_assets_domain    = module.security.assets_bucket_regional_domain
  acm_certificate_arn = var.acm_certificate_arn
  waf_rate_limit      = var.waf_rate_limit
  tags                = local.common_tags

  providers = { aws = aws.us_east_1 }
}

# ═══════════════════════════════════════════════════════════════════════════════
# DNS — Route 53
# ═══════════════════════════════════════════════════════════════════════════════
module "dns" {
  source                 = "./modules/dns"
  project_name           = var.project_name
  environment            = var.environment
  domain_name            = var.domain_name
  cloudfront_domain_name = module.cdn.cloudfront_domain_name
  alb_dns_name           = module.compute_primary.alb_dns_name
  alb_zone_id            = module.compute_primary.alb_zone_id
  vpc_ids = [
    module.vpc_prod_app.vpc_id,
    module.vpc_prod_data.vpc_id,
    module.vpc_shared.vpc_id,
    module.vpc_inspection.vpc_id,
    module.vpc_security.vpc_id,
  ]
  tags = local.common_tags
}
