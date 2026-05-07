###############################################################################
# Module: Shared Services
# AD, Route 53 Resolver (Inbound + Outbound), SSM, Jenkins
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "vpc_cidr" {
  type = string
}

variable "on_prem_cidrs" {
  description = "On-premises CIDR blocks for DNS resolution"
  type        = list(string)
  default     = ["192.168.10.0/24", "192.168.20.0/24", "192.168.30.0/24"]
}

variable "on_prem_dns_ips" {
  description = "On-premises DNS server IPs (FortiGate/AD DNS)"
  type        = list(string)
  default     = ["192.168.10.1"]
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Security Group for Shared Services ─────────────────────────────────────
resource "aws_security_group" "shared" {
  name_prefix = "${var.project_name}-shared-"
  vpc_id      = var.vpc_id
  description = "Security group for Shared Services (AD, Resolver, SSM, Jenkins)"

  # DNS
  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # LDAP / AD
  ingress {
    description = "LDAP"
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "LDAPS"
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Kerberos
  ingress {
    description = "Kerberos"
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  # Jenkins
  ingress {
    description = "Jenkins Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
  }

  # SSM
  ingress {
    description = "HTTPS (SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-shared-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Route 53 Resolver — Inbound Endpoint ──────────────────────────────────
# Allows on-premises networks to resolve AWS private hosted zone names
resource "aws_route53_resolver_endpoint" "inbound" {
  name      = "${var.project_name}-resolver-inbound"
  direction = "INBOUND"

  security_group_ids = [aws_security_group.shared.id]

  dynamic "ip_address" {
    for_each = var.private_subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-resolver-inbound"
  })
}

# ─── Route 53 Resolver — Outbound Endpoint ─────────────────────────────────
# Allows AWS to forward DNS queries to on-premises DNS servers
resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "${var.project_name}-resolver-outbound"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.shared.id]

  dynamic "ip_address" {
    for_each = var.private_subnet_ids
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-resolver-outbound"
  })
}

# ─── Resolver Rules — Forward on-prem domains ──────────────────────────────
resource "aws_route53_resolver_rule" "on_prem_forward" {
  domain_name          = "corp.edubridge.local"
  name                 = "${var.project_name}-on-prem-forward"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = var.on_prem_dns_ips
    content {
      ip   = target_ip.value
      port = 53
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-on-prem-dns-rule"
  })
}

resource "aws_route53_resolver_rule_association" "on_prem" {
  resolver_rule_id = aws_route53_resolver_rule.on_prem_forward.id
  vpc_id           = var.vpc_id
}

# ─── SSM VPC Endpoints ──────────────────────────────────────────────────────
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.shared.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.shared.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-ssmmessages-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.shared.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-ec2messages-endpoint"
  })
}

data "aws_region" "current" {}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "resolver_inbound_ips" {
  value = aws_route53_resolver_endpoint.inbound.ip_address
}

output "resolver_outbound_id" {
  value = aws_route53_resolver_endpoint.outbound.id
}

output "shared_security_group_id" {
  value = aws_security_group.shared.id
}
