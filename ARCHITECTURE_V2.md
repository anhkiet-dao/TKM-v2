# So Sánh Kiến Trúc: Original vs Cost-Optimized (Option 2)

Tài liệu này cung cấp cái nhìn tổng quan về sự khác biệt giữa kiến trúc gốc (dựa trên sơ đồ ban đầu) và kiến trúc đã được tối ưu hóa chi phí (Option 2) mà chúng ta vừa cập nhật trong Terraform.

## 1. Bảng So Sánh Chi Tiết

| Thành Phần | Sơ đồ ban đầu (Option 1) | Sơ đồ tối ưu (Option 2) | Tác động (Impact) |
| :--- | :--- | :--- | :--- |
| **Bảo mật mạng (Egress)** | Sử dụng **AWS Network Firewall** tại VPC-INSPECTION. | **Loại bỏ**. Phụ thuộc vào cấu hình chặt chẽ của Security Groups (SG) và NACL. | 💰 **Tiết kiệm ~$570/tháng**. Traffic đi ra ngoài sẽ đi thẳng qua NAT Gateway. |
| **Compute Database** | Dùng Provisioned Instance (`db.r6g.large`). Bật 24/7 với chi phí cố định. | Dùng **Aurora Serverless v2** (Scale từ 0.5 - 4.0 ACU). | 💰 **Tiết kiệm tới 60-70%**. Hệ thống tự động "ngủ đông" (hạ công suất) vào ban đêm và cuối tuần. |
| **Chiến lược DR (Sydney)** | **Pilot Light**: Chạy ngầm 1 Aurora Global Reader và cấu hình sẵn ECS (DesiredCount=0). | **Backup & Restore**: Dọn dẹp hoàn toàn tài nguyên ở Sydney. Chỉ giữ lại VPC rỗng và Transit Gateway. | 💰 **Tiết kiệm ~$200/tháng**. Sẽ tự động sao lưu dữ liệu (Automated Backups) sang Sydney. Khi có sự cố mới dùng code Terraform dựng lên. |
| **VPC-INSPECTION** | Subnet rắc rối: ALB/App -> TGW -> Firewall Subnet -> NAT Subnet. | Đơn giản hóa: ALB/App -> TGW -> NAT Subnet. | ⚡ Giảm độ trễ mạng, giảm chi phí xử lý data (data processing fee) của Firewall. Vẫn duy trì kiến trúc Centralized Egress. |

---

## 2. Sơ Đồ Kiến Trúc Mới (Option 2)

Dưới đây là sơ đồ kiến trúc mới, thể hiện sự đơn giản hóa, tập trung vào hiệu quả nhưng vẫn giữ được các nguyên tắc cốt lõi của Enterprise Networking.

```mermaid
graph TD
    classDef vpc fill:#f9f9f9,stroke:#333,stroke-width:2px,stroke-dasharray: 5 5;
    classDef tgw fill:#d8b4e2,stroke:#8e44ad,stroke-width:3px;
    classDef aws fill:#ff9900,stroke:#d35400,stroke-width:2px,color:#fff;
    classDef empty fill:#ecf0f1,stroke:#bdc3c7,stroke-width:2px,stroke-dasharray: 5 5,color:#7f8c8d;

    Internet((Internet Users)) --> CF[CloudFront + WAF]
    CF --> ALB

    subgraph "Region: ap-southeast-1 (Singapore - Primary)"
        
        subgraph "VPC-PROD-APP (10.10.x.x)"
            ALB[ALB] --> ECS[ECS Fargate]
        end

        subgraph "VPC-PROD-DATA (10.20.x.x)"
            DB[(Aurora Serverless v2)]
            Redis[(ElastiCache Redis)]
        end

        subgraph "VPC-INSPECTION (10.40.x.x)"
            NAT[NAT Gateway]
        end

        subgraph "VPC-SHARED (10.30.x.x)"
            AD[Active Directory / R53 Resolver]
            Jenkins[SSM / Jenkins]
        end

        TGW((TGW-SG<br>ASN: 64512)):::tgw
    end

    %% Internal Routing
    ECS -.->|VPC Attach| TGW
    TGW -.->|DB Traffic| DB
    TGW -.->|Cache Traffic| Redis
    
    ECS -->|Direct Local Route| DB
    
    TGW -.->|Centralized Egress| NAT
    NAT --> IGW_Out((Internet Outbound))
    
    TGW -.->|Shared Services| AD
    TGW -.->|Shared Services| Jenkins

    %% VPN Connections
    VPN_Users((WFH Engineers)) -->|TLS VPN| CVPN[Client VPN Endpoint]
    CVPN --> TGW

    Branch((Branch Offices)) -->|IPsec BGP| S2SVPN[Site-to-Site VPN]
    S2SVPN --> TGW

    %% DR Region
    subgraph "Region: ap-southeast-2 (Sydney - DR)"
        TGW_SY((TGW-SY<br>ASN: 64513)):::tgw
        
        subgraph "VPC-DR-APP (Empty)"
            note1[Sẵn sàng cho Compute Restore]:::empty
        end
        
        subgraph "VPC-DR-DATA (Empty)"
            note2[Cross-Region Backups]:::empty
        end
    end

    %% Cross Region
    TGW <-->|Inter-Region Peering| TGW_SY
    DB -.->|Automated Snapshots| note2

    %% Styling apply
    class ALB,ECS,DB,Redis,NAT,AD,Jenkins,CVPN,S2SVPN,CF aws;
    class "VPC-PROD-APP (10.10.x.x)","VPC-PROD-DATA (10.20.x.x)","VPC-INSPECTION (10.40.x.x)","VPC-SHARED (10.30.x.x)" vpc;
```

### 📋 Chú giải sơ đồ:
1.  **VPC-DR-APP & VPC-DR-DATA (Sydney):** Hiện tại đang là "VPC rỗng", chỉ đóng vai trò nhận các bản backup định kỳ. Chúng ta không mất tiền duy trì instance ở đây.
2.  **Aurora Serverless v2:** Logo Database đã được cập nhật thành loại Serverless, không còn bị khóa chết cấu hình 24/7.
3.  **VPC-INSPECTION:** AWS Network Firewall đã biến mất. Traffic từ các VPC đi ra ngoài Internet (Egress) sẽ chui qua Transit Gateway, đẩy thẳng ra NAT Gateway tại VPC này. Giữ được sự quản lý mạng lưới IP Public nhưng loại bỏ được phí Firewall.
