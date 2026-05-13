###############################################################################
# Module: Security
# GuardDuty, Security Hub, CloudWatch, S3 Log Buckets, VPC Flow Log storage
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "enable_guardduty" {
  type    = bool
  default = true
}

variable "enable_security_hub" {
  type    = bool
  default = true
}

variable "s3_log_bucket_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── S3 Bucket for Centralized Logs ─────────────────────────────────────────
resource "aws_s3_bucket" "logs" {
  bucket = "${var.s3_log_bucket_name}-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name    = "${var.project_name}-security-logs"
    Purpose = "Flow Logs + Audit"
  })
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"
    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# ─── S3 Bucket for Assets (with CRR to Sydney) ─────────────────────────────
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name    = "${var.project_name}-assets"
    Purpose = "Static Assets with CRR"
  })
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"   # Required for CRR
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── GuardDuty ──────────────────────────────────────────────────────────────
resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-guardduty"
  })
}

# ─── Security Hub ───────────────────────────────────────────────────────────
resource "aws_securityhub_account" "this" {
  count                    = var.enable_security_hub ? 1 : 0
  enable_default_standards = true
  auto_enable_controls     = true
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "aws_best_practices" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.this]
}

# ─── CloudWatch Dashboard ───────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "security" {
  dashboard_name = "${var.project_name}-security-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "GuardDuty Findings"
          metrics = var.enable_guardduty ? [
            ["AWS/GuardDuty", "FindingsCount", "DetectorId", aws_guardduty_detector.this[0].id]
          ] : []

          # "${aws_guardduty_detector.this[0].id}"

          stat = "Sum"
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          period  = 3600
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Security Hub Findings"
          metrics = [
            ["AWS/SecurityHub", "FindingsCount"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          period  = 3600
          stat    = "Sum"
        }
      }
    ]
  })
}

# ─── SNS Topic for Security Alerts ──────────────────────────────────────────
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_name}-security-alerts"
  tags = var.tags
}

# GuardDuty findings → CloudWatch Events → SNS
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.project_name}-guardduty-findings"
  description = "Capture GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail_type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]   # HIGH and CRITICAL
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

# ─── Data Sources ────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "log_bucket_arn" {
  value = aws_s3_bucket.logs.arn
}

output "log_bucket_name" {
  value = aws_s3_bucket.logs.bucket
}

output "assets_bucket_arn" {
  value = aws_s3_bucket.assets.arn
}

output "assets_bucket_name" {
  value = aws_s3_bucket.assets.bucket
}

output "assets_bucket_regional_domain" {
  value = aws_s3_bucket.assets.bucket_regional_domain_name
}

output "guardduty_detector_id" {
  value = var.enable_guardduty ? aws_guardduty_detector.this[0].id : null
}

output "security_alerts_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}
