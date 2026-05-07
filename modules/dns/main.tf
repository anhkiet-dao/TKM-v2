###############################################################################
# Module: DNS (Route 53)
# Public Hosted Zone + Private Hosted Zones + Health Checks
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "cloudfront_domain_name" {
  type    = string
  default = ""
}

variable "cloudfront_zone_id" {
  description = "CloudFront Hosted Zone ID (always Z2FDTNDATAQYW2)"
  type        = string
  default     = "Z2FDTNDATAQYW2"
}

variable "alb_dns_name" {
  type    = string
  default = ""
}

variable "alb_zone_id" {
  type    = string
  default = ""
}

variable "vpc_ids" {
  description = "VPC IDs to associate with private hosted zone"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Public Hosted Zone ─────────────────────────────────────────────────────
resource "aws_route53_zone" "public" {
  name    = var.domain_name
  comment = "EduBridge Vietnam - Public DNS"

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-zone"
  })
}

# ─── Private Hosted Zone ────────────────────────────────────────────────────
resource "aws_route53_zone" "private" {
  name    = "internal.${var.domain_name}"
  comment = "EduBridge Vietnam - Private DNS (RAM Shared)"

  dynamic "vpc" {
    for_each = var.vpc_ids
    content {
      vpc_id = vpc.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-zone"
  })
}

# ─── DNS Records ────────────────────────────────────────────────────────────

# Root domain → CloudFront
resource "aws_route53_record" "root" {
  count   = var.cloudfront_domain_name != "" ? 1 : 0
  zone_id = aws_route53_zone.public.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# www → CloudFront
resource "aws_route53_record" "www" {
  count   = var.cloudfront_domain_name != "" ? 1 : 0
  zone_id = aws_route53_zone.public.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# API → ALB (direct, bypassing CloudFront for WebSocket etc.)
resource "aws_route53_record" "api" {
  count   = var.alb_dns_name != "" ? 1 : 0
  zone_id = aws_route53_zone.public.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ─── Private DNS Records ────────────────────────────────────────────────────
resource "aws_route53_record" "db_writer" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "db-writer.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["placeholder.cluster-xxxx.ap-southeast-1.rds.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

resource "aws_route53_record" "redis" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "redis.internal.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60
  records = ["placeholder.cache.amazonaws.com"]

  lifecycle {
    ignore_changes = [records]
  }
}

# ─── Health Checks ──────────────────────────────────────────────────────────
resource "aws_route53_health_check" "primary_alb" {
  count = var.alb_dns_name != "" ? 1 : 0

  fqdn              = var.alb_dns_name
  port               = 443
  type               = "HTTPS"
  resource_path      = "/health"
  failure_threshold  = 3
  request_interval   = 30
  measure_latency    = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-primary-alb-health"
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "public_zone_id" {
  value = aws_route53_zone.public.zone_id
}

output "public_zone_name_servers" {
  value = aws_route53_zone.public.name_servers
}

output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "health_check_id" {
  value = length(aws_route53_health_check.primary_alb) > 0 ? aws_route53_health_check.primary_alb[0].id : null
}
