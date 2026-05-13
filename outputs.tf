###############################################################################
# EduBridge Vietnam — Outputs
###############################################################################

# ─── VPC IDs ─────────────────────────────────────────────────────────────────
output "vpc_ids" {
  description = "All VPC IDs"
  value = {
    prod_app   = module.vpc_prod_app.vpc_id
    prod_data  = module.vpc_prod_data.vpc_id
    shared     = module.vpc_shared.vpc_id
    inspection = module.vpc_inspection.vpc_id
    security   = module.vpc_security.vpc_id
    dr_app     = module.vpc_dr_app.vpc_id
    dr_data    = module.vpc_dr_data.vpc_id
  }
}

# ─── Transit Gateway ────────────────────────────────────────────────────────
output "tgw_sg_id" {
  value = module.tgw_sg.tgw_id
}

output "tgw_sy_id" {
  value = module.tgw_sy.tgw_id
}

# ─── Compute ────────────────────────────────────────────────────────────────
output "primary_alb_dns" {
  value = module.compute_primary.alb_dns_name
}

output "primary_ecs_cluster" {
  value = module.compute_primary.cluster_name
}

# ─── Database ───────────────────────────────────────────────────────────────
# output "aurora_primary_endpoint" {
#   value     = module.database_primary.aurora_cluster_endpoint
#   sensitive = false
# }
output "db_endpoint" {
  value = module.database_primary.db_endpoint
}

output "redis_endpoint" {
  value = module.database_primary.redis_endpoint
}

# ─── CDN ─────────────────────────────────────────────────────────────────────
output "cloudfront_domain" {
  value = module.cdn.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  value = module.cdn.cloudfront_distribution_id
}

# ─── DNS ─────────────────────────────────────────────────────────────────────
output "route53_name_servers" {
  value = module.dns.public_zone_name_servers
}

# ─── VPN ─────────────────────────────────────────────────────────────────────
output "client_vpn_endpoint" {
  value = module.vpn.client_vpn_dns_name
}

output "s2s_vpn_ids" {
  value = module.vpn.s2s_vpn_ids
}

output "vpn_tunnel_configs" {
  value     = module.vpn.vpn_tunnel_configs
  sensitive = true
}

# ─── Security ───────────────────────────────────────────────────────────────
output "security_log_bucket" {
  value = module.security.log_bucket_name
}

output "guardduty_detector_id" {
  value = module.security.guardduty_detector_id
}
