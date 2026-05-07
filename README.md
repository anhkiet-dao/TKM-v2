# EduBridge Vietnam — AWS Multi-Region Network Architecture

Infrastructure-as-Code (Terraform) triển khai kiến trúc AWS multi-region cho EduBridge Vietnam.

## Kiến Trúc

| Region | VPC | CIDR | Mục Đích |
|--------|-----|------|----------|
| Singapore (Primary) | VPC-PROD-APP | 10.10.0.0/16 | ALB + ECS Fargate |
| Singapore | VPC-PROD-DATA | 10.20.0.0/16 | Aurora PG + ElastiCache Redis |
| Singapore | VPC-SHARED | 10.30.0.0/16 | AD, R53 Resolver, SSM, Jenkins |
| Singapore | VPC-INSPECTION | 10.40.0.0/16 | Network Firewall (Suricata), NAT GW |
| Singapore | VPC-SECURITY | 10.50.0.0/16 | GuardDuty, Security Hub, Flow Logs |
| Sydney (DR) | VPC-DR-APP | 10.110.0.0/16 | ECS (Pilot Light, count=0) |
| Sydney (DR) | VPC-DR-DATA | 10.120.0.0/16 | Aurora Global Reader (lag <1s) |

## Networking

- **TGW-SG** (ASN 64512) — Singapore Transit Gateway
- **TGW-SY** (ASN 64513) — Sydney Transit Gateway
- **TGW Inter-Region Peering** — $0.02/GB, AWS-managed encryption
- **Client VPN** — 172.16.0.0/22, split-tunnel ON, TLS + MFA (TOTP)
- **S2S VPN** — 3 branches (HCM, Hà Nội, Đà Nẵng) via FortiGate

## 💰 Tối Ưu Chi Phí (FinOps)

Dự án này đi kèm với một bản phân tích chi tiết về **Tài chính Đám mây (FinOps)**, giúp doanh nghiệp hiểu rõ cơ cấu chi phí và các chiến lược tối ưu hóa (như dùng ARM Graviton, Serverless v2, thay đổi chiến lược DR). 
👉 Xem chi tiết tại: [COST_OPTIMIZATION.md](./COST_OPTIMIZATION.md)

## Triển Khai

### Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured với đúng credentials
- S3 bucket + DynamoDB table cho remote state

### Các bước

```bash
# 1. Khởi tạo
terraform init

# 2. Cập nhật terraform.tfvars với IP thực tế của FortiGate
# 3. Plan
terraform plan -out=tfplan

# 4. Apply
terraform apply tfplan
```

## Cấu Trúc

```
├── main.tf                  # Orchestration chính
├── variables.tf             # Biến đầu vào
├── outputs.tf               # Outputs
├── providers.tf             # AWS Providers (SG, SY, US-E1)
├── terraform.tfvars         # Giá trị mặc định
└── modules/
    ├── vpc/                 # VPC + Subnets + Flow Logs
    ├── tgw/                 # Transit Gateway + Attachments
    ├── network_firewall/    # AWS Network Firewall (Suricata)
    ├── compute/             # ECS Fargate + ALB + Auto Scaling
    ├── database/            # Aurora Global + ElastiCache Redis
    ├── vpn/                 # Client VPN + S2S VPN (FortiGate)
    ├── cdn/                 # CloudFront + WAFv2
    ├── dns/                 # Route 53 (Public + Private)
    ├── security/            # GuardDuty, Security Hub, S3 Logs
    ├── shared/              # AD, R53 Resolver, SSM Endpoints
    └── ipam/                # VPC IPAM (CIDR Pool Management)
```

## LƯU Ý

1. Thay thế `REPLACE_WITH_REAL_IP` trong `terraform.tfvars` bằng IP WAN thực tế
2. Thay thế `ACCOUNT_ID` trong ECR image URI
3. ACM Certificate cần được tạo trước (us-east-1 cho CloudFront)
4. Remote state S3 bucket cần được tạo trước khi `terraform init`
