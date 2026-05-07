###############################################################################
# Module: VPC
# Tạo VPC với public/private/TGW subnets, VPC Flow Logs
###############################################################################

variable "vpc_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "environment" {
  type = string
}

variable "project_name" {
  type = string
}

variable "enable_dns_support" {
  type    = bool
  default = true
}

variable "enable_dns_hostnames" {
  type    = bool
  default = true
}

variable "create_public_subnets" {
  description = "Whether to create public subnets (for ALB, NAT GW, etc.)"
  type        = bool
  default     = false
}

variable "create_private_subnets" {
  description = "Whether to create private subnets"
  type        = bool
  default     = true
}

variable "create_tgw_subnets" {
  description = "Whether to create dedicated TGW attachment subnets"
  type        = bool
  default     = true
}

variable "create_firewall_subnets" {
  description = "Whether to create firewall subnets (for VPC-INSPECTION)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}

variable "flow_log_destination_arn" {
  description = "S3 bucket ARN for flow logs (optional, uses CloudWatch if empty)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Locals ──────────────────────────────────────────────────────────────────
locals {
  # Derive subnet CIDRs from VPC CIDR
  # VPC /16 → subnets /24
  vpc_prefix = split("/", var.vpc_cidr)[0]
  vpc_octets = split(".", local.vpc_prefix)

  # Public subnets:  x.x.1.0/24, x.x.2.0/24
  public_subnets = var.create_public_subnets ? [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 1)
  ] : []

  # Private subnets: x.x.10.0/24, x.x.11.0/24
  private_subnets = var.create_private_subnets ? [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)
  ] : []

  # TGW subnets:     x.x.250.0/28, x.x.250.16/28
  tgw_subnets = var.create_tgw_subnets ? [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, 12, i + 4000)
  ] : []

  # Firewall subnets: x.x.20.0/28, x.x.20.16/28
  firewall_subnets = var.create_firewall_subnets ? [
    for i, az in var.azs : cidrsubnet(var.vpc_cidr, 12, i + 320)
  ] : []
}

# ─── VPC ─────────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}"
  })
}

# ─── Internet Gateway (only if public subnets) ─────────────────────────────
resource "aws_internet_gateway" "this" {
  count  = var.create_public_subnets ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-igw"
  })
}

# ─── Public Subnets ─────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = length(local.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-public-${var.azs[count.index]}"
    Tier = "Public"
  })
}

# ─── Private Subnets ────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(local.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-private-${var.azs[count.index]}"
    Tier = "Private"
  })
}

# ─── TGW Attachment Subnets ─────────────────────────────────────────────────
resource "aws_subnet" "tgw" {
  count             = length(local.tgw_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.tgw_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-tgw-${var.azs[count.index]}"
    Tier = "TGW"
  })
}

# ─── Firewall Subnets (VPC-INSPECTION) ──────────────────────────────────────
resource "aws_subnet" "firewall" {
  count             = length(local.firewall_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.firewall_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-firewall-${var.azs[count.index]}"
    Tier = "Firewall"
  })
}

# ─── Route Tables ────────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  count  = var.create_public_subnets ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-public-rt"
  })
}

resource "aws_route" "public_igw" {
  count                  = var.create_public_subnets ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = length(local.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = var.create_private_subnets ? length(var.azs) : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-private-rt-${var.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(local.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "tgw" {
  count  = var.create_tgw_subnets ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-tgw-rt"
  })
}

resource "aws_route_table_association" "tgw" {
  count          = length(local.tgw_subnets)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[0].id
}

# ─── VPC Flow Logs ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "flow_log" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc-flow-logs/${var.project_name}-${var.vpc_name}"
  retention_in_days = var.flow_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-flow-logs"
  })
}

resource "aws_iam_role" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.project_name}-${var.vpc_name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${var.project_name}-${var.vpc_name}-flow-log-policy"
  role  = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count                = var.enable_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_log[0].arn
  log_destination      = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.this.id
  max_aggregation_interval = 60

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.vpc_name}-flow-log"
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "firewall_subnet_ids" {
  value = aws_subnet.firewall[*].id
}

output "public_route_table_id" {
  value = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "tgw_route_table_id" {
  value = length(aws_route_table.tgw) > 0 ? aws_route_table.tgw[0].id : null
}

output "igw_id" {
  value = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
}
