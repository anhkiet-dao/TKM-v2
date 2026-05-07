###############################################################################
# Module: VPC IPAM
# AWS VPC IP Address Manager for centralized CIDR pool management
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "regions" {
  description = "Regions to manage CIDR pools for"
  type        = list(string)
  default     = ["ap-southeast-1", "ap-southeast-2"]
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── IPAM ────────────────────────────────────────────────────────────────────
resource "aws_vpc_ipam" "this" {
  description = "EduBridge VPC IPAM - Centralized CIDR Pool Management"

  dynamic "operating_regions" {
    for_each = var.regions
    content {
      region_name = operating_regions.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ipam"
  })
}

# ─── Top-level Pool (10.0.0.0/8) ────────────────────────────────────────────
resource "aws_vpc_ipam_pool" "top_level" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  description    = "Top-level pool for all VPCs"

  tags = merge(var.tags, {
    Name = "${var.project_name}-ipam-top-level"
  })
}

resource "aws_vpc_ipam_pool_cidr" "top_level" {
  ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  cidr         = "10.0.0.0/8"
}

# ─── Singapore Pool (10.10.0.0/12) ──────────────────────────────────────────
resource "aws_vpc_ipam_pool" "singapore" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  locale              = "ap-southeast-1"
  description         = "Singapore region pool"

  tags = merge(var.tags, {
    Name   = "${var.project_name}-ipam-singapore"
    Region = "ap-southeast-1"
  })
}

resource "aws_vpc_ipam_pool_cidr" "singapore" {
  ipam_pool_id = aws_vpc_ipam_pool.singapore.id
  cidr         = "10.0.0.0/12"

  depends_on = [aws_vpc_ipam_pool_cidr.top_level]
}

# ─── Sydney Pool (10.110.0.0/12) ────────────────────────────────────────────
resource "aws_vpc_ipam_pool" "sydney" {
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  locale              = "ap-southeast-2"
  description         = "Sydney region pool"

  tags = merge(var.tags, {
    Name   = "${var.project_name}-ipam-sydney"
    Region = "ap-southeast-2"
  })
}

resource "aws_vpc_ipam_pool_cidr" "sydney" {
  ipam_pool_id = aws_vpc_ipam_pool.sydney.id
  cidr         = "10.96.0.0/12"

  depends_on = [aws_vpc_ipam_pool_cidr.top_level]
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "ipam_id" {
  value = aws_vpc_ipam.this.id
}

output "singapore_pool_id" {
  value = aws_vpc_ipam_pool.singapore.id
}

output "sydney_pool_id" {
  value = aws_vpc_ipam_pool.sydney.id
}
