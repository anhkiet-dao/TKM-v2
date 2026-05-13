###############################################################################
# Module: VPN
# Client VPN + Site-to-Site VPN to on-premises FortiGate branches
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

variable "subnet_ids" {
  description = "Subnets for Client VPN association"
  type        = list(string)
}

variable "client_vpn_cidr" {
  description = "CIDR for Client VPN address pool"
  type        = string
  default     = "172.16.0.0/22"
}

variable "tgw_id" {
  description = "Transit Gateway ID for S2S VPN"
  type        = string
}

variable "on_prem_sites" {
  description = "On-premises sites for S2S VPN"
  type = map(object({
    name      = string
    cidr      = string
    bgp_asn   = number
    public_ip = string
    users     = number
    device    = string
    bandwidth = string
    isp       = string
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Certificate Authority for Client VPN ───────────────────────────────────
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "vpn.example.com"
    organization = "EduBridge Vietnam"
  }

  validity_period_hours = 87600   # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

resource "aws_acm_certificate" "vpn_server" {
  private_key      = tls_private_key.ca.private_key_pem
  certificate_body = tls_self_signed_cert.ca.cert_pem

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpn-server-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Client VPN Endpoint ────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/client-vpn/${var.project_name}"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connection-log"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "${var.project_name} Client VPN - Split Tunnel"
  server_certificate_arn = aws_acm_certificate.vpn_server.arn
  client_cidr_block      = var.client_vpn_cidr
  split_tunnel           = true   # Split tunnel ON (as per diagram)
  transport_protocol     = "udp"
  vpn_port               = 443

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_server.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  dns_servers = ["10.30.10.10", "10.30.10.11"]   # Shared VPC DNS resolvers

  tags = merge(var.tags, {
    Name = "${var.project_name}-client-vpn"
  })
}

# Associate Client VPN with subnets
resource "aws_ec2_client_vpn_network_association" "this" {
  count                  = length(var.subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.subnet_ids[count.index]
}

# Authorize all VPC CIDRs
resource "aws_ec2_client_vpn_authorization_rule" "all_vpcs" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = "10.0.0.0/8"
  authorize_all_groups   = true
  description            = "Authorize access to all VPCs"
}

# ─── Site-to-Site VPN (per branch office) ───────────────────────────────────
# Customer Gateways (FortiGate devices)
resource "aws_customer_gateway" "branches" {
  for_each = var.on_prem_sites

  bgp_asn    = each.value.bgp_asn
  ip_address = each.value.public_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name      = "${var.project_name}-cgw-${each.key}"
    Site      = each.value.name
    Device    = each.value.device
    ISP       = each.value.isp
    Bandwidth = each.value.bandwidth
    Users     = tostring(each.value.users)
  })
}

# VPN Connections (attached to TGW)
resource "aws_vpn_connection" "branches" {
  for_each = var.on_prem_sites

  customer_gateway_id = aws_customer_gateway.branches[each.key].id
  transit_gateway_id  = var.tgw_id
  type                = "ipsec.1"

  # Dual tunnels for HA
  tunnel1_inside_cidr = "169.254.${10 + index(keys(var.on_prem_sites), each.key) * 2}.0/30"
  tunnel2_inside_cidr = "169.254.${11 + index(keys(var.on_prem_sites), each.key) * 2}.0/30"

  # IKEv2 with AES-256-GCM
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase2_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase2_encryption_algorithms = ["AES256-GCM-16"]

  tags = merge(var.tags, {
    Name = "${var.project_name}-s2s-vpn-${each.key}"
    Site = each.value.name
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────
output "client_vpn_endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.this.id
}

output "client_vpn_dns_name" {
  value = aws_ec2_client_vpn_endpoint.this.dns_name
}

output "s2s_vpn_ids" {
  value = { for k, v in aws_vpn_connection.branches : k => v.id }
}

output "customer_gateway_ids" {
  value = { for k, v in aws_customer_gateway.branches : k => v.id }
}

output "vpn_tunnel_configs" {
  description = "VPN tunnel configurations for FortiGate setup"
  sensitive   = true
  value = {
    for k, v in aws_vpn_connection.branches : k => {
      tunnel1_address    = v.tunnel1_address
      tunnel1_preshared_key = v.tunnel1_preshared_key
      tunnel1_inside_cidr   = v.tunnel1_inside_cidr
      tunnel2_address    = v.tunnel2_address
      tunnel2_preshared_key = v.tunnel2_preshared_key
      tunnel2_inside_cidr   = v.tunnel2_inside_cidr
    }
  }
}
