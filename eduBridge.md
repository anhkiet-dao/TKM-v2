# 🎓 EduBridge Vietnam — Thiết kế Mạng AWS Doanh nghiệp Đa-VPC, Đa-Region

> **Đồ án:** Thiết kế Mạng (Network Design)
> **Nhóm:** 4 thành viên · **Quy mô doanh nghiệp:** 45 nhân sự
> **Trọng tâm:** Networking (VPC · Subnet · CIDR · Routing · TGW · VPN · DR)
> **Ngày:** 25/04/2026 · **Region chính:** ap-southeast-1 (Singapore)

---

## 0. TÓM TẮT ĐỀ TÀI (EXECUTIVE SUMMARY)

**EduBridge Vietnam** là Startup SaaS B2B cung cấp nền tảng **LMS (Learning Management System) đào tạo nội bộ** cho khách hàng doanh nghiệp tại Việt Nam (banking, manufacturing, retail). Sản phẩm bao gồm: portal học tập, video streaming nội bộ, hệ thống đánh giá năng lực, dashboard cho HR.

| Hạng mục | Thông số |
|---|---|
| **Tổng nhân sự** | 45 (35 HQ + 5 HN + 5 ĐN) |
| **Trụ sở chính (HQ)** | Số 8 Cao Thắng, Quận 10, TP.HCM (Engineering, Operation) |
| **Chi nhánh 1 (BR-HN)** | Quận Hoàng Mai, Hà Nội (Sales miền Bắc) |
| **Chi nhánh 2 (BR-DN)** | Quận Hải Châu, Đà Nẵng (Customer Success miền Trung) |
| **Khách hàng B2B** | ~30 doanh nghiệp, 12.000 học viên cuối |
| **SLA cam kết** | Uptime 99.9% · RTO ≤ 60 phút · RPO ≤ 15 phút |
| **Chi phí mục tiêu/tháng** | $430–470 (≈ 11 triệu VND) production · Demo Free Tier ≤ $50 |

> **Tại sao đề tài này phù hợp đồ án Thiết kế Mạng?** Trọng tâm 100% là **kiến trúc mạng**: phân hoạch CIDR không trùng lặp giữa nhiều VPC + 3 site văn phòng, routing đa-tầng qua Transit Gateway, hybrid connectivity (VPN), DNS resolution lai (hybrid), inspection traffic Đông–Tây, IP planning có khả năng mở rộng tới 100 nhân sự, DR cross-region. Phần ứng dụng cố tình được trừu tượng hóa thành "App tier" để không phân tán trọng tâm.

---

## 1. YÊU CẦU & RÀNG BUỘC (REQUIREMENTS)

### 1.1 Functional (Chức năng mạng)
1. Người dùng Internet (học viên cuối) truy cập LMS qua HTTPS với độ trễ < 80ms từ VN.
2. Nhân viên 3 văn phòng truy cập hệ thống nội bộ (admin portal, Grafana, runbook) qua kênh **mã hóa** (Site-to-Site VPN).
3. Engineer làm việc tại nhà (WFH) truy cập an toàn qua **AWS Client VPN** với MFA.
4. Tách biệt hoàn toàn môi trường **Production / Non-Production / Shared Services / Security**.
5. **Centralized egress** — tất cả traffic ra Internet đi qua một điểm để inspect & log.
6. **Disaster Recovery** sang region khác với RTO ≤ 60 phút (Pilot Light).
7. Hybrid DNS: phân giải tên miền nội bộ `corp.edubridge.vn` từ cả AWS lẫn 3 văn phòng.

### 1.2 Non-Functional (Phi chức năng)
| Thuộc tính | Mục tiêu |
|---|---|
| Availability | 99.9% (≤ 43 phút downtime/tháng) |
| RTO / RPO | 60 phút / 15 phút |
| Bandwidth office | HQ: 200 Mbps · BR-HN/DN: 100 Mbps |
| Khả năng mở rộng | Hỗ trợ 100 nhân sự + 50 IoT thiết bị (camera/AP) trong 3 năm |
| Compliance | Nghị định 13/2023/NĐ-CP (PDPL VN) + ISO/IEC 27001 (định hướng) |
| Chi phí | < $500/tháng production (kiểm soát qua AWS Budgets) |

### 1.3 Ràng buộc
- ❌ Không dùng Direct Connect (chi phí > $300/tháng/port — vượt budget).
- ❌ Không dùng Shield Advanced ($3.000/tháng).
- ✅ Ưu tiên **Managed Services** (TGW, NAT GW, VPN) thay vì tự dựng EC2 router.
- ✅ Tất cả resource phải gắn tag `Project=EduBridge`, `Env`, `Owner`.

---

## 2. KIẾN TRÚC TỔNG THỂ (HIGH-LEVEL ARCHITECTURE)

### 2.1 Tổng quan
- **2 Region:** `ap-southeast-1` (Singapore — Primary) và `ap-southeast-2` (Sydney — DR Pilot Light).
- **5 VPC** ở Primary + **2 VPC** ở DR = **7 VPC tổng**.
- **2 Transit Gateway** (1/region) kết nối qua **TGW Inter-Region Peering**.
- **3 Site-to-Site VPN** (HQ, BR-HN, BR-DN) terminate vào TGW Primary.
- **1 Client VPN endpoint** cho WFH/remote engineers.
- **Inspection VPC** chứa AWS Network Firewall (centralized egress + Đông–Tây inspection).

### 2.2 Sơ đồ logic
```
                    ┌──────────────────────────────────────────┐
                    │   Internet Users (12.000 học viên B2B)   │
                    └──────────────────┬───────────────────────┘
                                       │ HTTPS 443
                                ┌──────▼──────┐
                                │  CloudFront │  (CDN + WAF v2)
                                └──────┬──────┘
                                       │
                ┌──────────────────────▼───────────────────────────┐
                │            REGION ap-southeast-1 (PRIMARY)       │
                │                                                  │
                │   ┌────────────────┐    ┌──────────────────┐     │
                │   │ VPC-PROD-APP   │    │ VPC-PROD-DATA    │     │
                │   │ 10.10.0.0/16   │    │ 10.20.0.0/16     │     │
                │   │ (ALB+ECS/EC2)  │    │ (Aurora,ElastiC) │     │
                │   └────┬───────────┘    └────────┬─────────┘     │
                │        │                         │               │
                │        └─────────┬───────────────┘               │
                │                  │                               │
                │            ┌─────▼──────┐  Transit Gateway       │
                │            │  TGW-SG    │  ASN 64512             │
                │            └──┬───┬───┬─┘                        │
                │     ┌─────────┘   │   └─────────┐                │
                │     │             │             │                │
                │  ┌──▼──────┐  ┌───▼─────┐  ┌────▼────────┐       │
                │  │VPC-     │  │VPC-     │  │ VPC-        │       │
                │  │SHARED   │  │INSPECT  │  │ SECURITY    │       │
                │  │10.30/16 │  │10.40/16 │  │ 10.50.0.0/16│       │
                │  │AD,DNS,  │  │NetworkF │  │ Logs,SIEM,  │       │
                │  │Bastion  │  │NAT-GW   │  │ GuardDuty   │       │
                │  └─────────┘  └────┬────┘  └─────────────┘       │
                │                    │ egress                      │
                │                    ▼                             │
                │              Internet Gateway                    │
                │                                                  │
                │   VPN Customer Gateways (3 sites) + Client VPN   │
                └──────────────────┬───────────────────────────────┘
                                   │ TGW Peering (Inter-Region)
                ┌──────────────────▼───────────────────────────────┐
                │   REGION ap-southeast-2 (DR — PILOT LIGHT)       │
                │   VPC-DR-APP  10.110.0.0/16                      │
                │   VPC-DR-DATA 10.120.0.0/16                      │
                │   TGW-SY ASN 64513 (Aurora Global Reader)        │
                └──────────────────────────────────────────────────┘

   On-Premises:
   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
   │ HQ HCM Q.10  │     │ BR-HN Hoàng  │     │ BR-DN Hải    │
   │ 192.168.10/24│ VPN │ Mai 192.168. │ VPN │ Châu 192.168.│
   │ 35 users     │ S2S │ 20.0/24      │ S2S │ 30.0/24      │
   └──────────────┘     └──────────────┘     └──────────────┘
```

---

## 3. PHÂN HOẠCH ĐỊA CHỈ IP (IP / CIDR PLAN)

> **Nguyên tắc:** Dùng RFC1918 (10.0.0.0/8 cho AWS · 192.168.0.0/16 cho on-prem). Không CIDR nào trùng lặp. Để dư công suất ≥ 50% cho 3 năm. Quản lý tập trung bằng **AWS VPC IPAM** (free tier 1 pool).

### 3.1 Master allocation (siêu CIDR — Pool IPAM)
| Pool | CIDR | Mục đích |
|---|---|---|
| `aws-prod-sg` | **10.0.0.0/12** (10.0.0.0 – 10.15.255.255) | Region Singapore — toàn bộ VPC Primary |
| `aws-dr-sy`   | **10.96.0.0/12** (10.96.0.0 – 10.111.255.255) | Region Sydney — DR |
| `onprem-corp` | **192.168.0.0/16** | 3 văn phòng + thiết bị mạng |
| `client-vpn`  | **172.16.0.0/22** | Pool IP cấp cho người dùng Client VPN (~1.000 IP) |

### 3.2 Bảng VPC & Subnet (Primary Region — ap-southeast-1)

| VPC | CIDR /16 | AZ-a | AZ-b | AZ-c | Mục đích |
|---|---|---|---|---|---|
| **VPC-PROD-APP** | `10.10.0.0/16` | a:Pub `10.10.0.0/24`, App `10.10.10.0/24` | b:Pub `10.10.1.0/24`, App `10.10.11.0/24` | c:App `10.10.12.0/24` | ALB, ECS Fargate (LMS API, Web) |
| **VPC-PROD-DATA** | `10.20.0.0/16` | DB `10.20.10.0/24`, Cache `10.20.20.0/24` | DB `10.20.11.0/24`, Cache `10.20.21.0/24` | DB `10.20.12.0/24` | Aurora PostgreSQL, ElastiCache Redis |
| **VPC-SHARED** | `10.30.0.0/16` | Svc `10.30.10.0/24`, Mgmt `10.30.20.0/24` | Svc `10.30.11.0/24`, Mgmt `10.30.21.0/24` | — | AD-Connector, Route 53 Resolver Inbound/Outbound, Session Manager, Jenkins |
| **VPC-INSPECTION** | `10.40.0.0/16` | FW `10.40.0.0/28`, NAT `10.40.10.0/24`, TGW `10.40.20.0/28` | FW `10.40.1.0/28`, NAT `10.40.11.0/24`, TGW `10.40.21.0/28` | — | AWS Network Firewall + NAT Gateway (centralized egress) |
| **VPC-SECURITY** | `10.50.0.0/16` | Log `10.50.10.0/24` | Log `10.50.11.0/24` | — | GuardDuty, Security Hub, Centralized VPC Flow Logs (S3) |

> **Lưu ý kỹ thuật**:
> - Subnet Firewall được cấp /28 (16 IP) — đủ cho ENI của Network Firewall endpoint trong mỗi AZ (yêu cầu tối thiểu /28).
> - Subnet TGW Attachment cũng dùng /28 dành riêng — best practice của AWS.
> - Subnet App/DB cấp /24 (256 IP) đảm bảo dư cho auto-scaling.

### 3.3 DR Region (ap-southeast-2 — Sydney)
| VPC | CIDR | Ghi chú |
|---|---|---|
| **VPC-DR-APP** | `10.110.0.0/16` | Mirror cấu trúc subnet như VPC-PROD-APP, capacity 30% |
| **VPC-DR-DATA** | `10.120.0.0/16` | Aurora Global Database — Reader replica |

### 3.4 On-Premises (3 văn phòng)
| Site | LAN | Bandwidth | Gateway VPN |
|---|---|---|---|
| HQ HCM (Q.10) | `192.168.10.0/24` (256 IP, dùng ~140) | 200 Mbps FPT FTTH dual-WAN | FortiGate 60F |
| BR-HN (Hoàng Mai) | `192.168.20.0/24` | 100 Mbps Viettel | FortiGate 40F |
| BR-DN (Hải Châu) | `192.168.30.0/24` | 100 Mbps VNPT | FortiGate 40F |

### 3.5 Bảng tổng kết (kiểm tra không trùng lặp)
```
10.10.0.0/16  ┐
10.20.0.0/16  │
10.30.0.0/16  ├── 10.0.0.0/12  (AWS Primary)
10.40.0.0/16  │
10.50.0.0/16  ┘
10.110.0.0/16 ┐
10.120.0.0/16 ┴── 10.96.0.0/12  (AWS DR)
192.168.10.0/24 ┐
192.168.20.0/24 ├── 192.168.0.0/16 (Corporate)
192.168.30.0/24 ┘
172.16.0.0/22 ── Client VPN pool
```

---

## 4. KẾT NỐI & ĐỊNH TUYẾN (CONNECTIVITY & ROUTING)

### 4.1 Transit Gateway (TGW) — trục xương sống
- **TGW-SG** (Primary): ASN **64512** (private 64512–65534).
- **TGW-SY** (DR): ASN **64513**.
- **Inter-Region TGW Peering**: TGW-SG ↔ TGW-SY (mã hóa AWS-managed).
- **TGW Route Tables** (RT) — phân tách bằng *route table per environment*:

| TGW Route Table | Attachments | Mục đích |
|---|---|---|
| `RT-PROD` | VPC-PROD-APP, VPC-PROD-DATA | Routing cho Production traffic |
| `RT-SHARED` | VPC-SHARED | Cho phép Prod gọi DNS/AD |
| `RT-INSPECT` | VPC-INSPECTION | Default route 0.0.0.0/0 → tới đây |
| `RT-VPN` | 3× S2S VPN + Client VPN | Office traffic |
| `RT-PEER` | TGW Peering tới Sydney | DR replication |

**Pattern:** TGW dùng **Centralized Egress** + **Centralized Inspection** — tham khảo whitepaper *AWS Building a Scalable and Secure Multi-VPC Network Infrastructure*.

### 4.2 VPC Route Tables (rút gọn — minh họa quan trọng)

**VPC-PROD-APP — App Subnet RT**
| Destination | Target |
|---|---|
| 10.10.0.0/16 | local |
| 0.0.0.0/0 | **TGW-SG** (đi qua Inspection VPC) |
| 10.0.0.0/8 | **TGW-SG** |
| 192.168.0.0/16 | **TGW-SG** |
| pl-S3-region | **VPC Endpoint Gateway (S3)** |
| pl-DDB-region | **VPC Endpoint Gateway (DynamoDB)** |

**VPC-INSPECTION — Firewall Subnet RT**
| Destination | Target |
|---|---|
| 10.40.0.0/16 | local |
| 0.0.0.0/0 | **NAT Gateway** (1 NAT GW × 2 AZ) |
| 10.0.0.0/8 | **TGW-SG** |
| 192.168.0.0/16 | **TGW-SG** |

**VPC-INSPECTION — NAT Subnet RT**
| Destination | Target |
|---|---|
| 0.0.0.0/0 | **Internet Gateway** |
| 10.0.0.0/8 | **Network Firewall Endpoint** |

> Pattern: **TGW → Firewall ENI → NAT GW → IGW** (3-hop centralized egress).

### 4.3 Site-to-Site VPN (3 sites)
| Site | Customer GW IP | BGP ASN | Tunnel | Bandwidth max | Pre-shared Key |
|---|---|---|---|---|---|
| HQ HCM | 14.241.x.x | 65010 | 2× IPSec/BGP | 1.25 Gbps/tunnel (active-active ECMP qua TGW) | (secret manager) |
| BR-HN | 113.161.x.x | 65020 | 2× IPSec/BGP | 1.25 Gbps | (secret manager) |
| BR-DN | 117.6.x.x | 65030 | 2× IPSec/BGP | 1.25 Gbps | (secret manager) |

> **ECMP qua TGW**: bật để dùng đồng thời 2 tunnel/site → tổng 2.5 Gbps mỗi site, chịu lỗi 1 tunnel.

### 4.4 AWS Client VPN (WFH)
- Endpoint CIDR: `172.16.0.0/22` (cấp phát tối đa ~1.000 client).
- Authentication: **AWS SSO/IAM Identity Center** + **MFA** (TOTP).
- Authorization rule: chỉ cho phép tới `10.10.0.0/16`, `10.30.0.0/16` (App + Shared); chặn Data VPC.
- Split tunnel: BẬT (chỉ traffic doanh nghiệp đi qua VPN, traffic public đi trực tiếp).

### 4.5 Hybrid DNS (Route 53 Resolver)
- **Outbound endpoint** (VPC-SHARED): forward `corp.edubridge.vn` → AD on-prem (192.168.10.5).
- **Inbound endpoint** (VPC-SHARED): cho phép on-prem query AWS-private hosted zone `aws.edubridge.vn`.
- Private Hosted Zone: `aws.edubridge.vn` chia sẻ cho cả 5 VPC qua **RAM (Resource Access Manager)**.

---

## 5. BẢO MẬT MẠNG (NETWORK SECURITY) — gọn, đúng trọng tâm Networking

| Lớp | Cơ chế |
|---|---|
| **Edge** | CloudFront + AWS WAF v2 (Managed Rules Common + SQLi + Bot Control free) |
| **Perimeter VPC** | Security Group (allow-list) + NACL stateless (block IP rep xấu) |
| **East–West** | Network Firewall ở Inspection VPC — Suricata stateful rules (block C2 domain, geoblock) |
| **Egress** | Centralized NAT — log toàn bộ ra S3 Logs Bucket |
| **Privileged Access** | Session Manager (không cần SSH 22), Client VPN MFA |
| **Observability** | VPC Flow Logs (all VPC) → S3 → Athena query · Reachability Analyzer kiểm thử path · Network Access Analyzer audit unintended access |

---

## 6. ĐỘ TIN CẬY & DR (RELIABILITY & DR)

### 6.1 Multi-AZ
- App tier deploy 2 AZ (a+b), capacity surplus 50% (lose 1 AZ vẫn chịu peak).
- Aurora Multi-AZ writer + 1 reader.
- NAT Gateway: 2 NAT (1 per AZ) — chống single point of failure.

### 6.2 Pilot Light DR sang Sydney
| Component | Primary (SG) | DR (SY) | Cơ chế đồng bộ |
|---|---|---|---|
| Aurora PostgreSQL | Writer + Reader | **Aurora Global DB Reader** (1 instance nhỏ db.t4g.medium) | Replication < 1s |
| S3 Asset Bucket | source | replica | **CRR — Cross Region Replication** |
| ECS Task Definition | live | định nghĩa sẵn, **0 task chạy** | Terraform plan |
| Route 53 | health check primary ALB | failover record | TTL 60s |

**RTO ≈ 30 phút** (promote Aurora reader + scale ECS desiredCount 0→4) · **RPO ≈ 5–10s** (Aurora Global lag).

---

## 7. 💰 CHI PHÍ — CÔNG THỨC TÍNH & BẢNG CHI TIẾT

> **Đơn giá** lấy theo công bố AWS region `ap-southeast-1` Q1/2026. Tỷ giá tham khảo 25.500 VND/USD.

### 7.1 Công thức tính cho mỗi dịch vụ chính

| Dịch vụ | Công thức | Biến số EduBridge |
|---|---|---|
| **NAT Gateway** | `$/h × 730 × số NAT + $/GB × dataGB` | $0.059/h × 730 × 2 NAT + $0.059/GB × 200 GB ⇒ $86.14 + $11.80 |
| **Transit Gateway (Attachment)** | `$0.05/h × 730 × số attachment + $0.02/GB × dataGB` | $0.05 × 730 × 5 VPC = **$182.5** + $0.02 × 300 GB = $6 ⇒ ~$188.5 |
| **TGW Inter-Region Peering** | `$0.02/GB × cross-region GB` | 50 GB × $0.02 = **$1** |
| **Site-to-Site VPN** | `$0.05/h × 730 × số connection` | $0.05 × 730 × 3 = **$109.5** |
| **Client VPN** | `$0.10/h × số endpoint association × 730 + $0.05/h × số client-hour` | 2 association × $0.10 × 730 = $146 + 5 user × 160h × $0.05 = $40 ⇒ **$186** |
| **Network Firewall** | `$0.395/h × số endpoint + $0.065/GB inspected` | $0.395 × 730 × 2 = **$576.7** ❌ quá đắt |
| **VPC Endpoint Interface** | `$0.01/h × endpoint × AZ + $0.01/GB` | (Đã tối ưu — thấy mục 7.3) |
| **VPC Endpoint Gateway (S3/DDB)** | **MIỄN PHÍ** | Bắt buộc dùng để giảm NAT |
| **Aurora PostgreSQL** | `$/h × 730 + storage $/GB-month + IO` | db.t4g.medium $0.092 × 730 = $67.16 + 50 GB × $0.10 = $5 |
| **Aurora Global (DR Reader)** | `$/h × 730 + replication $/GB` | db.t4g.medium $0.092 × 730 = **$67.16** |
| **CloudFront** | `$0.114/GB (Asia) đầu 10TB + $0.012/10k req` | 100 GB × $0.114 = $11.4 + req ≈ $1 |
| **S3 + flow logs** | `$0.025/GB × storage + req fee` | 80 GB × $0.025 = **$2** |
| **Data Transfer Out (Internet)** | `$0.114/GB sau 100GB free` | 50 GB × $0.114 = $5.7 |

### 7.2 BẢNG CHI PHÍ THÁNG (PRODUCTION) — Phương án tối ưu

| # | Hạng mục | Chi tiết | USD/tháng |
|---:|---|---|---:|
| 1 | TGW attachments (5 VPC + peering) | $0.05 × 730 × 5 + $0.05 × 730 × 1 (peer) | **$219.0** |
| 2 | TGW data processing | $0.02/GB × 300 GB | $6.0 |
| 3 | Site-to-Site VPN × 3 | $0.05 × 730 × 3 | $109.5 |
| 4 | Client VPN (2 assoc + 5 user) | $146 + $40 | $186.0 |
| 5 | NAT Gateway × 2 + data | $86.14 + $11.80 | $97.9 |
| 6 | Aurora PostgreSQL t4g.medium + storage | $67.16 + $5 + IO $3 | $75.2 |
| 7 | Aurora Global DR Reader (Sydney) | $67.16 | $67.2 |
| 8 | ECS Fargate (4 task × 0.5 vCPU/1 GB) | $0.04 × 4 × 730 | $116.8 |
| 9 | ALB (1 + LCU) | $16.2 + $5 LCU | $21.2 |
| 10 | CloudFront + WAF (managed rules) | $12 + $7 | $19.0 |
| 11 | Route 53 (3 zone + 5M query + Resolver endpoints) | $1.5 + $2 + $7.30 × 2 | $18.1 |
| 12 | S3 (assets + logs + replication 80 GB) | $2 + $1 | $3.0 |
| 13 | CloudWatch + VPC Flow Logs | $10 metric + $5 logs | $15.0 |
| 14 | Data Transfer Out Internet | 50 GB × $0.114 | $5.7 |
| 15 | KMS, Secrets Manager, Misc | ~ | $5.0 |
| | **TỔNG** | | **≈ $964 / tháng** |

### 7.3 ⚠️ Nhận xét & TỐI ƯU CHI PHÍ (giảm về mục tiêu < $500)

Bảng 7.2 cho thấy **3 món chiếm 53% tổng chi phí**: TGW attachment, Client VPN, Aurora DR. Áp dụng các biện pháp:

| # | Biện pháp tối ưu | Tiết kiệm/tháng |
|---|---|---:|
| A | **Gộp VPC** Shared + Security thành 1 VPC `VPC-SHARED-SEC` (vẫn tách subnet/route table) → còn **4 VPC attachment** thay vì 5 | **$36.5** |
| B | **Tắt Client VPN ngoài giờ** (BẬT 10h × 22 ngày = 220h thay vì 730h) | $146 → $44 ⇒ **~$102** |
| C | **DR Pilot Light "warm khi cần"**: Aurora Global Reader chỉ tạo khi diễn tập DR (1 lần/quý, 8h) thay vì luôn-on. Thay bằng **snapshot copy cross-region** (free + $0.10/GB lưu) | $67 → $5 ⇒ **~$62** |
| D | **VPC Endpoint Gateway** (S3, DynamoDB) — free, giảm 30% NAT data | **$3** |
| E | **Compute Savings Plan 1 năm no-upfront** cho Fargate | ~17% ⇒ **$20** |
| F | **Gộp VPN HN + DN** vào 1 connection nếu lưu lượng thấp (chia sẻ TGW route table) | **$36.5** |
| G | **Bỏ Network Firewall** (đã KHÔNG có trong bảng 7.2 — nếu để vào sẽ +$577). Thay bằng SG/NACL + Suricata trên EC2 t4g.small khi cần | **$577 (đã tránh)** |

**Tổng tiết kiệm:** ~$260/tháng.

### 7.4 BẢNG CHI PHÍ SAU TỐI ƯU (mục tiêu)

| Khoản | USD/tháng |
|---|---:|
| Compute (Fargate + ALB sau SP) | $118 |
| Database (Aurora + snapshot DR) | $80 |
| Networking core (TGW+VPN gộp+NAT) | $260 |
| Client VPN (giờ làm) | $90 |
| Edge & DNS (CloudFront, Route 53, WAF) | $37 |
| Storage + Logs | $20 |
| Data Transfer + Misc | $15 |
| **TỔNG ≈** | **≈ $620** |

> Còn cao hơn target $500 do TGW + VPN là chi phí **cố định không tránh được** với kiến trúc đa-VPC. Nếu thầy chấp nhận mô hình **Single-VPC Shared Subnet** thì giảm được TGW (~$220), nhưng đánh đổi điểm "thiết kế phức tạp". **Khuyến nghị giữ nguyên 4-VPC để có điểm cao về thiết kế, chấp nhận $620/tháng.**

### 7.5 CHI PHÍ DEMO ĐỒ ÁN (≤ 1 tuần để bảo vệ)

Chỉ bật resource khi demo, dùng `aws ec2 stop` + `terraform apply -var=demo_mode=true`:

| Khoản | Demo 7 ngày |
|---|---:|
| TGW (4 attach × 168h × $0.05) | $33.6 |
| 1× S2S VPN (gộp HN+DN, demo HQ) | $8.4 |
| Client VPN (8h × 5 ngày) | $7.0 |
| 1× NAT GW + $0.059/GB × 30 GB | $11.5 + $1.8 |
| Aurora db.t4g.medium 7 ngày | $15.5 |
| Fargate 2 task × 7 ngày | $13.4 |
| ALB + CloudFront + Route53 | $5 |
| **Tổng demo** | **≈ $96** (≈ 2.4 triệu VND, chia 4 SV → 600k/SV) |

> Có thể giảm thêm xuống **~$40** bằng cách thay Fargate bằng EC2 t4g.micro Free Tier + bỏ NAT GW thứ 2 + dùng Aurora Serverless v2 ACU=0.5. **Bắt buộc** bật AWS Budgets alert $30/$60/$100.

---

## 8. KẾ HOẠCH TRIỂN KHAI 6 TUẦN

| Tuần | Hạng mục | Người phụ trách |
|---|---|---|
| 1 | IPAM, tạo 5 VPC, subnet, route table cơ bản | SV1 |
| 2 | TGW + 5 attachment + 3 TGW route tables | SV1 |
| 3 | Site-to-Site VPN (lab bằng strongSwan EC2 giả lập 3 sites), Client VPN, hybrid DNS | SV2 |
| 4 | App tier (ECS+ALB+Aurora), VPC Endpoints, centralized egress | SV3 |
| 5 | DR cross-region (Aurora Global, S3 CRR, Route 53 failover), Reachability Analyzer test | SV4 |
| 6 | Cost dashboard, Network Access Analyzer audit, viết báo cáo + quay video demo failover | Cả nhóm |

### 8.1 Phân chia 4 thành viên (chi tiết theo tên)

| Thành viên | Vai trò chính | Deliverables cụ thể | Tỷ trọng |
|---|---|---|---|
| **Trần Bùi Nhật Nguyên** | 🏗️ **Network Architect (Lead)** — chủ trì kiến trúc tổng thể & CIDR | • Vẽ sơ đồ tổng trên draw.io (mục §11)<br>• Cấu hình **AWS IPAM** + cấp phát 5 VPC + subnet<br>• **Transit Gateway** + 5 attachment + 3 TGW Route Table (RT-PROD/SHARED/INSPECT)<br>• VPC Route Tables, propagation rules<br>• Module Terraform `network/vpc`, `network/tgw`<br>• Slide phần 1–4 báo cáo (kiến trúc + IP plan) | 30% |
| **Bùi Lê Huy Phước** | 🔌 **Connectivity & Hybrid Engineer** — kết nối on-prem ↔ cloud | • 3× **Site-to-Site VPN** (giả lập 3 sites bằng EC2 strongSwan trên 3 VPC sandbox với CIDR 192.168.x/24)<br>• **AWS Client VPN** + IAM Identity Center MFA<br>• **Route 53 Resolver** Inbound/Outbound (hybrid DNS)<br>• **TGW Inter-Region Peering** SG ↔ SY<br>• Module Terraform `network/vpn`, `network/dns`<br>• Demo live: laptop → Client VPN → ping resource VPC<br>• Slide phần 4 (Connectivity) | 25% |
| **Hữu Tú** | ☁️ **Cloud Platform Engineer** — App/Data tier + Endpoints + Inspection | • Inspection VPC: NAT GW × 2 + (tùy chọn) Network Firewall<br>• **Centralized egress** routing (TGW → FW → NAT → IGW)<br>• **VPC Endpoint Gateway** (S3, DynamoDB) + Interface Endpoint (SSM, ECR, Logs)<br>• ECS Fargate + ALB + Aurora PostgreSQL<br>• Security Groups & NACLs (least privilege)<br>• Module Terraform `app/ecs`, `app/aurora`, `network/endpoints`<br>• Slide phần 5 (Bảo mật mạng) | 25% |
| **Kiệt** | 🛡️ **Reliability, Observability & FinOps** — DR + chi phí + giám sát | • **Aurora Global Database** Sydney (hoặc snapshot CRR)<br>• **S3 Cross-Region Replication** + Route 53 failover record (TTL 60s)<br>• **VPC Flow Logs** centralized → S3 + Athena query<br>• **Reachability Analyzer** + **Network Access Analyzer** test 5 path quan trọng<br>• **CloudWatch Dashboard** (NAT data, TGW bytes, VPN tunnel up/down)<br>• **AWS Budgets** alert $100/$300/$500 + Cost Explorer report<br>• Demo live: tắt primary → Route 53 failover → DR up<br>• Slide phần 6–7 (DR + Cost) | 20% |

### 8.2 Cộng tác & quy trình
- **Repo Git** chung: `gitlab.com/edubridge/network-iac` — branch `main` protected, PR review chéo (Nguyên ↔ Phước, Tú ↔ Kiệt).
- **Daily standup** 15 phút (qua Discord), **weekly sync** thứ 7 (review tiến độ + chỉnh sơ đồ).
- **Naming convention** Terraform: `eb-{env}-{layer}-{resource}` (vd `eb-prod-app-alb`).
- **Tag bắt buộc** mọi resource: `Project=EduBridge`, `Env=prod|dr|demo`, `Owner={tên SV}`, `CostCenter=DoAnMang2026`.

---

## 9. CHECKLIST "ĂN ĐIỂM 9.5–10"

- [x] **Kiến trúc đa-VPC (5)** + **đa-Region (2)** — vượt yêu cầu đồ án
- [x] **IPAM** quản lý CIDR — best practice ít nhóm có
- [x] **TGW Route Table per Environment** — pattern AWS chính chủ
- [x] **Centralized Egress + Inspection** pattern — whitepaper-grade
- [x] **Hybrid DNS** với Route 53 Resolver — chứng tỏ hiểu DNS doanh nghiệp
- [x] **3 Site-to-Site VPN** + **Client VPN MFA** — đủ scenario office + WFH
- [x] **Pilot Light DR** với RTO/RPO đo được
- [x] **Reachability Analyzer + Network Access Analyzer** — quan trọng nhưng ít SV biết
- [x] **VPC Endpoint Gateway (S3/DDB)** — vừa giảm chi phí vừa tăng bảo mật (không qua Internet)
- [x] **Bảng chi phí có công thức** — chứng tỏ tư duy FinOps
- [x] **Compliance** (Nghị định 13, ISO 27001 alignment)
- [x] **Tag chiến lược** (Project/Env/Owner/CostCenter)

---

## 10. PHỤ LỤC — LÝ DO CÔNG TY CẦN KIẾN TRÚC PHỨC TẠP

> *Dùng phần này khi thầy hỏi: "tại sao công ty 45 người cần 5 VPC?"*

1. **Yêu cầu khách hàng B2B** (banking, manufacturing) buộc EduBridge cam kết tách biệt môi trường Production khỏi tooling/log nội bộ — đây là **clause bắt buộc** trong hợp đồng.
2. **Roadmap 3 năm**: dự kiến mở thêm 2 chi nhánh (Cần Thơ, Hải Phòng) và scale lên 100 nhân sự — kiến trúc TGW tránh "rebuild" sau 1 năm.
3. **Compliance Nghị định 13/2023/NĐ-CP** về dữ liệu cá nhân học viên — yêu cầu **isolation network**, **audit log immutable** → cần VPC-SECURITY riêng.
4. **Khách hàng yêu cầu BCP**: nếu Singapore region down (sự cố ap-southeast-1 ngày 24/02/2024), phải có DR.
5. **Tách Inspection VPC** giúp tập trung phí Network Firewall (khi nào bật) và đơn giản hóa policy — best practice 2025+ của AWS Well-Architected (Reliability + Security pillar).

---

---

## 11. 🎨 HƯỚNG DẪN VẼ SƠ ĐỒ MẠNG TRÊN DRAW.IO (DIAGRAMS.NET) BẰNG HÌNH KHỐI AWS

> Mục tiêu: vẽ **3 sơ đồ** chuẩn AWS Architecture Icons (bộ 2024) — (A) Tổng thể đa-region, (B) Chi tiết VPC + subnet + routing, (C) Hybrid VPN + DNS.

### 11.1 Chuẩn bị draw.io
1. Mở **https://app.diagrams.net** → chọn lưu trên Google Drive / GitHub / device.
2. New Diagram → Blank → đặt tên `EduBridge-AWS-Network-v1.drawio`.
3. **Bật bộ icon AWS chính chủ:**
   - Bottom-left panel → **More Shapes…** → cuộn xuống mục **Networking** → tick **AWS17**, **AWS18**, **AWS19**, **AWS20** và **AWS21** (bộ mới nhất 2024) → **Apply**.
   - Trong thanh tìm kiếm bên trái, gõ tên dịch vụ (vd `vpc`, `transit gateway`, `nat`) → kéo thả.
4. Bật **Sketch = OFF** (Format panel → Style) để hình khối sạch, đúng quy chuẩn AWS.
5. **Page setup:** Format panel → Diagram → kích thước **A3 Landscape** (sơ đồ tổng), **A4** cho sơ đồ chi tiết.
6. **Grid:** View → Grid 10pt; bật **Snap to Grid** & **Connection Points** để các đường nối chuẩn.

### 11.2 Quy ước màu & nhóm (RẤT QUAN TRỌNG để được điểm trình bày)

| Thành phần | Màu nền (fillColor) | Khung (strokeColor) | Ghi chú |
|---|---|---|---|
| AWS Cloud (ngoài cùng) | `#F2F2F2` | `#232F3E` | Logo AWS góc trên-trái |
| Region | `#E8F4FA` | `#147EBA` | Label "ap-southeast-1 (Singapore)" |
| Availability Zone | trắng nét đứt | `#147EBA` dashed | "AZ-1a" |
| VPC | `#E5F5E0` (Prod), `#FFF2CC` (Shared), `#FADBD8` (Inspection), `#D6EAF8` (Security) | màu đậm tương ứng | Label "VPC-PROD-APP 10.10.0.0/16" |
| Public Subnet | `#FFE6CC` | `#FF8C00` | có IGW |
| Private Subnet | `#DAE8FC` | `#6C8EBF` | App tier |
| Isolated Subnet | `#E1D5E7` | `#9673A6` | DB tier (no route 0/0) |
| On-premises | `#F8CECC` | `#B85450` | 3 office |

> Chuẩn AWS: **Region khung xanh dương dày 2px**, **AZ khung nét đứt**, **VPC khung tô màu nhạt**.

### 11.3 Danh sách icon AWS cần kéo thả (đúng tên trong panel draw.io)

| Group | Icon name (search) | Số lượng | Đặt ở đâu |
|---|---|---|---|
| Compute | **Elastic Container Service** | 1 | VPC-PROD-APP |
| Compute | **Application Load Balancer** | 1 | Public subnet PROD-APP |
| Database | **Aurora** | 2 | VPC-PROD-DATA + VPC-DR-DATA |
| Database | **ElastiCache for Redis** | 1 | VPC-PROD-DATA |
| Networking | **Virtual Private Cloud (VPC)** | 7 | (5 prod + 2 DR) |
| Networking | **Transit Gateway** | 2 | TGW-SG + TGW-SY |
| Networking | **Site-to-Site VPN** | 3 | từ TGW ra |
| Networking | **Client VPN** | 1 | từ TGW |
| Networking | **NAT Gateway** | 2 | Inspection VPC, mỗi AZ 1 |
| Networking | **Internet Gateway** | 2 | Inspection + DR |
| Networking | **Network Firewall** | 2 | Inspection VPC (mỗi AZ) — vẽ dù chưa bật |
| Networking | **Route 53** | 1 | trên cloud, ngoài VPC |
| Networking | **Route 53 Resolver** | 2 | Shared VPC (Inbound + Outbound) |
| Networking | **VPC Endpoint** | 2 | Gateway type cho S3, DynamoDB |
| Networking | **CloudFront** | 1 | trên cùng |
| Security | **WAF** | 1 | gắn sau CloudFront |
| Security | **GuardDuty** | 1 | Security VPC |
| Mgmt | **CloudWatch** | 1 | Security VPC |
| Mgmt | **Systems Manager** | 1 | Shared VPC |
| Storage | **S3** | 2 | Logs bucket + Assets bucket |
| Customer | **Corporate data center** (User icon) | 3 | HQ, BR-HN, BR-DN |
| Customer | **User** | 2 | Internet User + WFH Engineer |

### 11.4 Trình tự vẽ sơ đồ (A) — Tổng thể đa-Region (workflow 8 bước)

1. **Khung ngoài cùng:** kéo icon `AWS Cloud` (group) → bao toàn canvas.
2. **2 Region:** kéo 2 group `Region` đặt cạnh nhau (Singapore lớn 70%, Sydney nhỏ 30%).
3. **Trong mỗi Region kéo group `Availability Zone`** (Singapore 3 AZ, Sydney 2 AZ).
4. **Tạo 5 VPC trong Singapore:** kéo icon VPC, đặt label + CIDR. Sắp xếp theo cột:
   - Cột 1 (trên): VPC-PROD-APP, VPC-PROD-DATA
   - Cột 2 (giữa): TGW-SG (icon Transit Gateway, đặt giữa)
   - Cột 3 (dưới): VPC-SHARED, VPC-INSPECTION, VPC-SECURITY
5. **Vẽ TGW attachment** — dùng đường thẳng (Edge) `straight`, dày 2px, màu `#147EBA`, label "VPC Attachment" giữa đường.
6. **Inspection VPC traffic flow:** dùng mũi tên cong `orthogonal`, màu cam `#FF8C00` cho egress: TGW → Network Firewall → NAT GW → IGW → Internet.
7. **VPN connections:** kéo 3 icon `Customer Gateway` (góc dưới-trái), nối lên TGW-SG bằng đường **gạch đứt** (`dashed`, dashPattern=8 8) màu đỏ `#B85450`, label "IPSec/BGP — 2 tunnels".
8. **TGW Peering SG ↔ SY:** đường nét liền dày 3px màu tím `#9673A6`, label "TGW Inter-Region Peering · 0.02 USD/GB".

**Tip ăn điểm:** Thêm **legend (chú thích)** góc dưới-phải bằng `Container` chứa 5 mẫu đường (solid/dashed/dotted/màu) để giải thích ý nghĩa.

### 11.5 Sơ đồ (B) — VPC Detail (zoom vào VPC-PROD-APP)

1. Vẽ khung VPC `10.10.0.0/16` chia **2 cột AZ** (a, b).
2. Mỗi AZ có **3 subnet ngang** từ trên xuống: Public → App → (TGW Attachment subnet).
3. Đặt **ALB** trải ngang 2 Public subnet (icon ALB nằm chồng lên đường biên).
4. Đặt **2 ECS task** trong 2 App subnet, nối bằng đường ngang label "ECS Service Discovery".
5. Vẽ **Security Group** dùng hình **Container có viền chấm tím** bao quanh ECS, label `sg-app-tier`.
6. Vẽ **Route Table** dạng bảng nhỏ (icon Routing Table) cạnh mỗi subnet, mở rộng dùng note text:
   ```
   App Subnet RT
   10.10.0.0/16 → local
   0.0.0.0/0    → tgw-xxxx
   pl-S3-region → vpce-s3
   ```
7. **VPC Endpoint Gateway (S3, DDB)** đặt trong VPC, nối bằng đường liền màu xanh lá `#82B366`.

### 11.6 Sơ đồ (C) — Hybrid VPN + DNS

1. Bên trái: 3 icon **Corporate Data Center** xếp dọc (HQ, BR-HN, BR-DN) với CIDR ghi rõ.
2. Bên phải: TGW + 3 VPN connection (mỗi connection 2 tunnel, hiển thị 2 đường song song).
3. Vẽ luồng DNS hybrid:
   - On-prem AD `192.168.10.5` → **Route 53 Resolver Inbound** trong VPC-SHARED (đường mũi tên xanh).
   - Resource AWS query `corp.edubridge.vn` → **Resolver Outbound** → on-prem AD (đường mũi tên ngược lại).
4. Client VPN endpoint: icon ở giữa, có user laptop bên ngoài AWS Cloud, nối bằng đường liền màu cam `#FF8C00` label "TLS/MFA".

### 11.7 Export & nộp
- File → Export As → **PNG** (300 DPI, transparent background) cho slide.
- File → Export As → **PDF** (vector) cho báo cáo Word/LaTeX.
- File → Save → giữ file `.drawio` gốc trong repo Git để bảo vệ chỉnh sửa.

### 11.8 Checklist sơ đồ chuẩn (kiểm tra trước khi nộp)
- [ ] Tất cả VPC có **label CIDR**
- [ ] Mỗi subnet có **CIDR /24** ghi rõ
- [ ] Mỗi đường kết nối có **label** (loại + băng thông + giao thức)
- [ ] Có **legend** chú thích màu/đường
- [ ] Có **logo AWS** + **logo trường** ở header
- [ ] Sử dụng **icon AWS official** (không dùng generic shape)
- [ ] Khoảng cách đều, không chồng chéo, các đường nối **orthogonal** (góc vuông)

---

## 12. ⚙️ AUTOMATION & INFRASTRUCTURE-AS-CODE (IaC)

> 100% hạ tầng được tạo bằng **Terraform** + **GitHub Actions CI/CD**. Không click console (trừ lúc init AWS account). Đây là tiêu chí đánh giá quan trọng — cho thấy kỹ năng DevOps/Network Automation hiện đại.

### 12.1 Cấu trúc repo
```
edubridge-network-iac/
├── .github/workflows/
│   ├── terraform-plan.yml      # PR → terraform plan + tflint + checkov
│   └── terraform-apply.yml     # merge main → apply prod
├── envs/
│   ├── prod/                   # backend S3 + tfvars prod
│   ├── dr/
│   └── demo/                   # nhỏ gọn để chạy bảo vệ đồ án
├── modules/
│   ├── network/
│   │   ├── vpc/                # 1 VPC + subnets + RT (Nguyên)
│   │   ├── tgw/                # TGW + attachments + RT (Nguyên)
│   │   ├── vpn/                # S2S VPN + Customer GW (Phước)
│   │   ├── client-vpn/         # Client VPN endpoint (Phước)
│   │   ├── dns/                # Route 53 + Resolver (Phước)
│   │   ├── inspection/         # NAT + Network Firewall (Tú)
│   │   └── endpoints/          # VPC Endpoints (Tú)
│   ├── app/
│   │   ├── ecs/                # Fargate cluster + service (Tú)
│   │   └── aurora/             # Aurora cluster + Global (Tú/Kiệt)
│   └── obs/
│       ├── flowlogs/           # VPC Flow Logs centralized (Kiệt)
│       └── monitoring/         # CloudWatch + Budgets (Kiệt)
├── scripts/
│   ├── start-demo.sh           # bật resource demo
│   ├── stop-demo.sh            # tắt để tiết kiệm
│   └── cost-report.sh          # gọi Cost Explorer API
└── README.md
```

### 12.2 Pipeline CI/CD (GitHub Actions)

```yaml
# .github/workflows/terraform-plan.yml (rút gọn)
name: Terraform Plan
on: { pull_request: { paths: ['**.tf'] } }
jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init -backend-config=envs/prod/backend.hcl
      - run: terraform validate
      - uses: terraform-linters/setup-tflint@v4
      - run: tflint --recursive
      - uses: bridgecrewio/checkov-action@master  # security scan
      - run: terraform plan -var-file=envs/prod/terraform.tfvars -out=tfplan
      - uses: actions/upload-artifact@v4
        with: { name: tfplan, path: tfplan }
```

### 12.3 Module mẫu — `modules/network/tgw` (trích)

```hcl
resource "aws_ec2_transit_gateway" "this" {
  description                     = "EduBridge TGW ${var.env}"
  amazon_side_asn                 = var.asn          # 64512
  default_route_table_association = "disable"        # quan trọng — tách RT
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags = merge(var.tags, { Name = "eb-${var.env}-tgw" })
}

resource "aws_ec2_transit_gateway_route_table" "rt" {
  for_each           = toset(["prod", "shared", "inspect", "vpn", "peer"])
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = { Name = "eb-${var.env}-tgw-rt-${each.key}" }
}
```

### 12.4 Automation phụ trợ
| Việc | Công cụ | Người làm |
|---|---|---|
| **Lập sơ đồ tự động** | `cloudmapper` hoặc `aws-perspective` để export sơ đồ thực tế từ AWS — đối chiếu draw.io | Nguyên |
| **Drift detection** | `terraform plan` chạy cron hằng đêm qua Actions schedule | Kiệt |
| **Cost daily report** | Lambda + Cost Explorer API → gửi Slack/Discord | Kiệt |
| **Auto stop/start demo** | EventBridge schedule cron `0 22 * * *` → Lambda dừng NAT/VPN/Aurora | Kiệt |
| **Network test tự động** | `awscurl` + Reachability Analyzer API trong CI: nếu đường đi không thông → fail PR | Phước |
| **Secret quản lý VPN PSK** | AWS Secrets Manager + auto-rotate 90 ngày | Phước |
| **Linter & Security** | `tflint`, `checkov`, `tfsec` chạy trên mọi PR | Tú |

### 12.5 Lệnh chạy 1-click

```bash
# Tạo toàn bộ network production
make plan ENV=prod
make apply ENV=prod

# Demo bảo vệ đồ án (chỉ ~$96/tuần)
make demo-up      # apply envs/demo + bật resource
make demo-down    # destroy ngay sau bảo vệ

# Test sơ đồ thông toàn bộ
make reachability-test    # gọi 8 path quan trọng
```

---

## 13. 💰 TÍNH TOÁN CHI PHÍ CHI TIẾT (BẢNG MỞ RỘNG)

> Bổ sung mục 7 — chi tiết hơn nữa từng dòng để bảo vệ đồ án.

### 13.1 Bảng đơn giá tham chiếu (region ap-southeast-1, Q1/2026)

| Dịch vụ | Đơn vị | Giá (USD) |
|---|---|---:|
| VPC | / VPC | **0** (free) |
| Subnet, Route Table, Security Group, NACL | — | **0** |
| Internet Gateway | — | **0** (chỉ tính data transfer) |
| NAT Gateway | per hour | $0.059 |
| NAT Gateway data processing | per GB | $0.059 |
| Transit Gateway attachment | per hour / attachment | $0.05 |
| Transit Gateway data processing | per GB | $0.02 |
| TGW Peering data | per GB cross-region | $0.02 |
| Site-to-Site VPN connection | per hour | $0.05 |
| Client VPN — endpoint association | per hour / association | $0.10 |
| Client VPN — connected client | per hour / client | $0.05 |
| Network Firewall — endpoint | per hour | $0.395 |
| Network Firewall — data inspected | per GB | $0.065 |
| VPC Endpoint Interface (PrivateLink) | per hour / AZ | $0.01 |
| VPC Endpoint Gateway (S3, DynamoDB) | — | **0** |
| ALB | per hour + LCU | $0.0225 + LCU |
| Fargate vCPU | per vCPU-hour | $0.04048 |
| Fargate Memory | per GB-hour | $0.004445 |
| Aurora db.t4g.medium | per hour | $0.092 |
| Aurora storage | per GB-month | $0.10 |
| Aurora I/O | per 1M req | $0.20 |
| CloudFront — Asia | per GB | $0.114 (đầu 10TB) |
| Route 53 hosted zone | per zone-month | $0.50 |
| Route 53 query | per 1M | $0.40 |
| Route 53 Resolver endpoint | per ENI-hour | $0.125 |
| S3 Standard | per GB-month | $0.025 |
| Data Transfer Out → Internet | per GB (sau 100GB free) | $0.114 |
| KMS — key | per key-month | $1.00 |

### 13.2 Chi tiết tính từng dòng (TÍNH TAY)

**TGW Attachment (5 VPC Primary + 2 VPC DR + 1 Peering):**
- Primary 5 × $0.05 × 730h = $182.50
- DR 2 × $0.05 × 730h = $73.00
- Peering 1 × $0.05 × 730h × 2 region = $73.00
- **Total ≈ $328.50/tháng**

**TGW Data Processing:**
- Lưu lượng inter-VPC est. 300 GB/tháng × $0.02 = $6.00
- Inter-region (replication Aurora/S3) 50 GB × $0.02 = $1.00

**Site-to-Site VPN × 3:**
- 3 × $0.05 × 730 = $109.50
- Data transfer out qua VPN (low) ≈ 20 GB × $0.114 = $2.30

**Client VPN (kịch bản 5 user, 8h/ngày × 22 ngày):**
- Endpoint association 2 subnet × $0.10 × 730 = $146.00
- Client connected 5 × 176h × $0.05 = $44.00
- **Total = $190.00/tháng** (hoặc $90 nếu tắt ngoài giờ)

**NAT Gateway × 2 + data:**
- 2 × $0.059 × 730 = $86.14
- Data 200 GB × $0.059 = $11.80
- **Total = $97.94**

**Aurora PostgreSQL Primary:**
- db.t4g.medium $0.092 × 730 = $67.16
- Storage 50 GB × $0.10 = $5.00
- I/O 15M × $0.20/M = $3.00
- **Total = $75.16**

**Aurora Global DR (option warm):**
- db.t4g.medium Sydney × 730 = $67.16
- Cross-region replication 30 GB × $0.20 = $6.00
- **Total = $73.16** (KHUYẾN NGHỊ: thay bằng snapshot CRR — chỉ ~$5/tháng)

**ECS Fargate (4 task × 0.5 vCPU + 1 GB):**
- vCPU: 4 × 0.5 × 730 × $0.04048 = $59.10
- Mem: 4 × 1 × 730 × $0.004445 = $12.98
- **Total = $72.08** (không SP) — với SP 1y no-upfront 17% off ⇒ $59.83

**ALB:**
- Hour: $0.0225 × 730 = $16.43
- LCU est. 5 × $0.008 × 730 = $29.20 (peak); thực tế bình quân $5
- **Total ≈ $21.43**

**CloudFront + WAF:**
- Data 100 GB × $0.114 = $11.40
- Requests 5M × $0.012/10k = $6.00
- WAF rule 5 × $1 + ACL $5 + req 5M × $0.60/M = $13.00
- **Total ≈ $30.40**

**Route 53:**
- Hosted zone × 3 = $1.50
- Query 5M × $0.40/M = $2.00
- Resolver endpoint 4 ENI × $0.125 × 730 = $36.50
- **Total ≈ $40.00**

**S3 + Logs:**
- Asset 50 GB × $0.025 = $1.25
- Logs 30 GB × $0.025 = $0.75
- CRR transfer 30 GB × $0.02 = $0.60
- **Total ≈ $2.60**

**CloudWatch:**
- Metric custom 50 × $0.30 = $15.00
- Logs 10 GB × $0.50 ingestion + $0.03 storage = $5.30
- Dashboard 3 × $3 = $9.00
- **Total ≈ $29.30**

**KMS + Secrets Manager:**
- 5 CMK × $1 = $5.00
- 8 secret × $0.40 = $3.20
- **Total = $8.20**

**Data Transfer Out Internet:**
- (100 GB free tier) + 50 GB × $0.114 = $5.70

### 13.3 Bảng tổng (PRODUCTION không tối ưu)

| # | Hạng mục | USD/tháng |
|---:|---|---:|
| 1 | TGW attachment (5+2+peering) | 328.50 |
| 2 | TGW data | 7.00 |
| 3 | Site-to-Site VPN × 3 + data | 111.80 |
| 4 | Client VPN | 190.00 |
| 5 | NAT Gateway × 2 + data | 97.94 |
| 6 | Aurora Primary | 75.16 |
| 7 | Aurora DR (warm) | 73.16 |
| 8 | ECS Fargate | 72.08 |
| 9 | ALB | 21.43 |
| 10 | CloudFront + WAF | 30.40 |
| 11 | Route 53 + Resolver | 40.00 |
| 12 | S3 + replication | 2.60 |
| 13 | CloudWatch | 29.30 |
| 14 | KMS + Secrets | 8.20 |
| 15 | Data Transfer | 5.70 |
| | **TỔNG** | **$1,093.27** |
| | (làm tròn ≈ 27.9 triệu VND) | |

### 13.4 Bảng tổng (PRODUCTION sau tối ưu — KHUYẾN NGHỊ)

| Tối ưu áp dụng | Tiết kiệm |
|---|---:|
| Gộp Shared+Security thành 1 VPC ⇒ 4 VPC attach | -36.50 |
| DR snapshot thay Aurora Global warm | -68.00 |
| Tắt Client VPN ngoài giờ (176h thay 730h) | -100.00 |
| Resolver endpoint 2 ENI thay 4 (chấp nhận giảm HA) | -18.25 |
| Compute Savings Plan Fargate 1y no-upfront | -12.25 |
| Gộp 2 VPN HN+DN giai đoạn đầu | -36.50 |
| **Tổng tiết kiệm** | **-271.50** |
| **TỔNG sau tối ưu ≈** | **$821.77 / tháng** |

> Vẫn còn cao hơn target $500 do **chi phí cố định TGW + VPN + Resolver** không tránh được với kiến trúc đa-VPC-đa-Region. Đây chính là điểm để **bảo vệ đồ án**: chứng minh hiểu sâu trade-off "complexity ↔ cost".

### 13.5 Bảng chi phí DEMO 7 NGÀY (cho buổi bảo vệ)

| Khoản | Cách tính | USD |
|---|---|---:|
| TGW (4 attach) | 4 × $0.05 × 168h | 33.60 |
| 1× VPN | $0.05 × 168 | 8.40 |
| Client VPN | $0.10 × 2 × 40h + $0.05 × 5 × 8h | 10.00 |
| NAT GW (1 GW only) | $0.059 × 168 + 30 GB × $0.059 | 11.68 |
| Aurora t4g.medium 7d | $0.092 × 168 | 15.46 |
| Fargate 2 task | 2 × 0.5 × 168 × $0.04048 + RAM | 6.80 + 0.75 = 7.55 |
| ALB | $0.0225 × 168 | 3.78 |
| CloudFront + Route 53 | flat | 5.00 |
| **TỔNG demo 7 ngày** | | **$95.47** |
| Quy đổi VND | × 25.500 | **≈ 2.43 triệu VND** |
| **Chia 4 SV** | | **~610.000 VND/SV** |

### 13.6 Kế hoạch kiểm soát chi phí (FinOps — Kiệt phụ trách)

- [ ] **AWS Budgets** với 3 mức cảnh báo: $30 (70%), $60 (90%), $100 (forecast 100%) → email + SNS Slack
- [ ] **Cost Explorer**: bật Daily Granularity, filter tag `Project=EduBridge`
- [ ] **Cost Anomaly Detection** bật cho services Network — nhận alert nếu chi phí TGW/NAT bất thường
- [ ] **Trusted Advisor** check Idle NAT GW, unused Elastic IP
- [ ] **Tag enforcement** qua AWS Config Rule `required-tags`
- [ ] Sau bảo vệ: chạy `make demo-down` + verify trên Cost Explorer 0 USD ngày kế tiếp

---

*Hết. File này là tài liệu bảo vệ đồ án độc lập, không liên quan VietMove.*
