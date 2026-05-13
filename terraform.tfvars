###############################################################################
# EduBridge Vietnam — terraform.tfvars
# Cấu hình mặc định cho môi trường Production
###############################################################################

environment  = "prod"
project_name = "edubridge"
domain_name  = "edubridge.vn"

# ─── VPC CIDRs — Singapore (Primary) ────────────────────────────────────────
vpc_cidrs = {
  prod_app   = "10.10.0.0/16"
  prod_data  = "10.20.0.0/16"
  shared     = "10.30.0.0/16"
  inspection = "10.40.0.0/16"
  security   = "10.50.0.0/16"
}

# ─── VPC CIDRs — Sydney (DR Pilot Light) ────────────────────────────────────
vpc_cidrs_dr = {
  dr_app  = "10.110.0.0/16"
  dr_data = "10.120.0.0/16"
}

# ─── Client VPN ─────────────────────────────────────────────────────────────
client_vpn_cidr = "172.16.0.0/22"

# ─── Transit Gateway ASNs ───────────────────────────────────────────────────
tgw_asn_singapore = 64512
tgw_asn_sydney    = 64513

# ─── On-Premises Sites (S2S VPN) ────────────────────────────────────────────
# ⚠️ THAY THẾ public_ip bằng IP thực tế của FortiGate WAN interface
on_prem_sites = {
  hq_hcm = {
    name      = "HQ-HCM-Q10"
    cidr      = "192.168.10.0/24"
    bgp_asn   = 65010
    public_ip = "203.0.113.10"           # ← Thay bằng IP WAN thực tế
    users     = 35
    device    = "FortiGate-60F"
    bandwidth = "200Mbps"
    isp       = "FPT-DualWAN"
  }
  br_hn = {
    name      = "BR-HN-HoangMai"
    cidr      = "192.168.20.0/24"
    bgp_asn   = 65020
    public_ip = "203.0.113.20"           # ← Thay bằng IP WAN thực tế
    users     = 5
    device    = "FortiGate-40F"
    bandwidth = "100Mbps"
    isp       = "Viettel"
  }
  br_dn = {
    name      = "BR-DN-HaiChau"
    cidr      = "192.168.30.0/24"
    bgp_asn   = 65030
    public_ip = "203.0.113.30"           # ← Thay bằng IP WAN thực tế
    users     = 5
    device    = "FortiGate-40F"
    bandwidth = "100Mbps"
    isp       = "VNPT"
  }
}

# ─── Availability Zones ─────────────────────────────────────────────────────
azs_singapore = ["ap-southeast-1a", "ap-southeast-1b"]
azs_sydney    = ["ap-southeast-2a", "ap-southeast-2b"]

# ─── ECS Fargate Config ─────────────────────────────────────────────────────
ecs_app_config = {
  cpu            = 512
  memory         = 1024
  desired_count  = 2
  container_port = 8080
  image          = "ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/edubridge-app:latest"
}

# ─── Aurora PostgreSQL ───────────────────────────────────────────────────────
# aurora_config = {
#   engine_version  = "15.4"
#   instance_class  = "db.serverless"
#   instance_count  = 2
#   database_name   = "edubridge"
#   master_username = "edubridge_admin"
#   min_capacity    = 0.5
#   max_capacity    = 4.0
# }

# ─── RDS PostgreSQL ─────────────────────────────────────────────────────────
rds_config = {
  engine_version     = "15"
  instance_class     = "db.t3.micro"
  database_name      = "edubridge"
  master_username    = "postgres"
  allocated_storage  = 20
}

# ─── ElastiCache Redis ──────────────────────────────────────────────────────
redis_config = {
  node_type       = "cache.r6g.large"
  num_cache_nodes = 2
  engine_version  = "7.0"
}

# ─── Security / Monitoring ──────────────────────────────────────────────────
enable_guardduty        = true
enable_security_hub     = true
flow_log_retention_days = 90
s3_log_bucket_name      = "edubridge-security-logs"

# ─── WAF ─────────────────────────────────────────────────────────────────────
waf_rate_limit      = 2000
acm_certificate_arn = ""   # Sẽ được tạo tự động hoặc nhập thủ công

# ─── Additional Tags ────────────────────────────────────────────────────────
additional_tags = {
  CostCenter  = "IT-Infrastructure"
  Owner       = "Platform-Team"
  Compliance  = "ISO27001"
}
