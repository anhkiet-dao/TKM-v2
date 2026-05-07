###############################################################################
# Module: CDN (CloudFront + WAF)
# CloudFront Distribution with WAFv2 Web ACL
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

variable "alb_dns_name" {
  description = "ALB DNS name as CloudFront origin"
  type        = string
}

variable "s3_assets_domain" {
  description = "S3 assets bucket regional domain name"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM Certificate ARN in us-east-1 for CloudFront"
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "Rate limit per 5 minutes per IP"
  type        = number
  default     = 2000
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── WAFv2 Web ACL (must be in us-east-1 for CloudFront) ───────────────────
resource "aws_wafv2_web_acl" "cloudfront" {
  name        = "${var.project_name}-cloudfront-waf"
  description = "WAF for CloudFront - EduBridge Vietnam"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: Rate limiting
  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed Rules - Common Rule Set
  rule {
    name     = "aws-managed-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Rules - SQL Injection
  rule {
    name     = "aws-managed-sqli"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: AWS Managed Rules - Known Bad Inputs
  rule {
    name     = "aws-managed-bad-inputs"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Geo-restriction (optional — block known bad regions)
  rule {
    name     = "geo-block"
    priority = 5

    action {
      block {}
    }

    statement {
      geo_match_statement {
        country_codes = ["KP", "IR", "CU", "SY"]   # Sanctioned countries
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-geo-block"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-cloudfront-waf"
  })
}

# ─── CloudFront Origin Access Control (for S3) ─────────────────────────────
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.project_name}-s3-oac"
  description                       = "OAC for S3 assets bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─── CloudFront Distribution ────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "EduBridge Vietnam CDN"
  default_root_object = "index.html"
  price_class         = "PriceClass_200"   # Asia, Europe, North America
  web_acl_id          = aws_wafv2_web_acl.cloudfront.arn

  aliases = var.acm_certificate_arn != "" ? [var.domain_name, "www.${var.domain_name}"] : []

  # Origin 1: ALB (API / Dynamic content)
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }
  }

  # Origin 2: S3 (Static assets)
  origin {
    domain_name              = var.s3_assets_domain
    origin_id                = "s3-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Default behavior → ALB
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb-origin"

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"   # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"   # AllViewer

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Static assets → S3
  ordered_cache_behavior {
    path_pattern     = "/assets/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-assets"

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"   # CachingOptimized

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # Media files → S3
  ordered_cache_behavior {
    path_pattern     = "/media/*"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-assets"

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-cloudfront"
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.cloudfront.arn
}

output "waf_web_acl_id" {
  value = aws_wafv2_web_acl.cloudfront.id
}
