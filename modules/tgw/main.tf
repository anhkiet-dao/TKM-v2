###############################################################################
# Module: Transit Gateway
# TGW Singapore + Sydney, Inter-Region Peering, VPC Attachments, Route Tables
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tgw_asn" {
  type = number
}

variable "tgw_name" {
  type = string
}

variable "vpc_attachments" {
  description = "Map of VPC attachments"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    appliance_mode_support = optional(string, "disable")
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Transit Gateway ────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway" "this" {
  amazon_side_asn                 = var.tgw_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  multicast_support               = "disable"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.tgw_name}"
  })
}

# ─── VPC Attachments ────────────────────────────────────────────────────────
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  # Required for inspection VPC pattern
  appliance_mode_support = each.value.appliance_mode_support

  dns_support    = "enable"
  ipv6_support   = "disable"

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-attach-${each.key}"
  })
}

# ─── Route Tables ────────────────────────────────────────────────────────────

# Default Route Table — 0.0.0.0/0 → Inspection VPC
resource "aws_ec2_transit_gateway_route_table" "default" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.tgw_name}-default-rt"
  })
}

# Inspection (Firewall) Route Table — returns traffic back
resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.tgw_name}-inspection-rt"
  })
}

# Security Route Table
resource "aws_ec2_transit_gateway_route_table" "security" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.tgw_name}-security-rt"
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "tgw_arn" {
  value = aws_ec2_transit_gateway.this.arn
}

output "tgw_attachment_ids" {
  value = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}

output "default_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.default.id
}

output "inspection_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.inspection.id
}

output "security_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.security.id
}
