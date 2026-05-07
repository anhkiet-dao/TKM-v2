###############################################################################
# Module: Network Firewall (VPC-INSPECTION)
# AWS Network Firewall (Suricata-based) for centralized egress inspection
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

variable "firewall_subnet_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Firewall Rule Group — Stateful (Suricata-compatible) ───────────────────
resource "aws_networkfirewall_rule_group" "stateful_suricata" {
  capacity = 1000
  name     = "${var.project_name}-suricata-rules"
  type     = "STATEFUL"

  rule_group {
    # Suricata-compatible rules
    rules_source {
      rules_string = <<-EOT
        # Block known malicious domains
        drop tls any any -> any any (tls.sni; content:"malware.example.com"; msg:"Block malware domain"; sid:1000001; rev:1;)
        
        # Allow DNS
        pass udp any any -> any 53 (msg:"Allow DNS UDP"; sid:1000010; rev:1;)
        pass tcp any any -> any 53 (msg:"Allow DNS TCP"; sid:1000011; rev:1;)
        
        # Allow HTTPS outbound
        pass tcp any any -> any 443 (msg:"Allow HTTPS outbound"; sid:1000020; rev:1;)
        
        # Allow HTTP outbound (for package updates)
        pass tcp any any -> any 80 (msg:"Allow HTTP outbound"; sid:1000021; rev:1;)
        
        # Allow NTP
        pass udp any any -> any 123 (msg:"Allow NTP"; sid:1000030; rev:1;)
        
        # Drop all other traffic
        drop ip any any -> any any (msg:"Drop all other traffic"; sid:1000099; rev:1;)
      EOT
    }

    stateful_rule_options {
      capacity = 1000
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-suricata-rules"
  })
}

# ─── Firewall Policy ────────────────────────────────────────────────────────
resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.project_name}-inspection-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.stateful_suricata.arn
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-inspection-policy"
  })
}

# ─── Network Firewall ───────────────────────────────────────────────────────
resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.project_name}-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = var.vpc_id

  dynamic "subnet_mapping" {
    for_each = var.firewall_subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-network-firewall"
  })
}

# ─── Firewall Logging ───────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "firewall_alert" {
  name              = "/aws/network-firewall/${var.project_name}/alert"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "firewall_flow" {
  name              = "/aws/network-firewall/${var.project_name}/flow"
  retention_in_days = 30
  tags              = var.tags
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alert.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_flow.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "firewall_id" {
  value = aws_networkfirewall_firewall.this.id
}

output "firewall_arn" {
  value = aws_networkfirewall_firewall.this.arn
}

output "firewall_status" {
  value = aws_networkfirewall_firewall.this.firewall_status
}

# Endpoint IDs needed for routing
output "firewall_endpoint_ids" {
  description = "Map of AZ to firewall endpoint ID for routing"
  value = {
    for ss in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    ss.availability_zone => ss.attachment[0].endpoint_id
  }
}
