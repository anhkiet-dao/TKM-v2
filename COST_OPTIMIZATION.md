# Báo Cáo Tối Ưu Chi Phí & Tài Chính Đám Mây (AWS FinOps)
**Dự án:** EduBridge Vietnam — AWS Multi-Region Network Architecture

Tài liệu này phân tích cơ cấu chi phí của kiến trúc hạ tầng mạng hiện tại và đề xuất các chiến lược tối ưu hóa (Cost Optimization) nhằm đảm bảo hiệu quả tài chính tốt nhất cho doanh nghiệp trong khi vẫn duy trì tính bảo mật và tính sẵn sàng cao (HA).

---

## 1. Phân Tích Cơ Cấu Chi Phí (Cost Drivers)

Trong kiến trúc Enterprise này, chi phí được chia thành 2 loại chính: **Phí duy trì cố định (Idle Cost)** và **Phí theo lưu lượng/sử dụng (Usage Cost)**. Dưới đây là các thành phần "ngốn" tiền nhất:

| Thành phần | Loại chi phí chính | Ước tính phí duy trì (Cơ bản) | Ghi chú |
| :--- | :--- | :--- | :--- |
| **AWS Network Firewall** | Phí Endpoint / giờ / AZ | ~$570 / tháng (2 AZs) | Rất đắt. Chiếm phần lớn chi phí network. |
| **Transit Gateway (TGW)** | Phí Attachment / giờ | ~$250 / tháng (7 attachments) | Phí cố định cao, chưa tính phí xử lý data ($0.02/GB). |
| **Aurora Global DB** | Phí Compute Instance | ~$380 / tháng (2 x r6g.large) | Đang chạy 2 node Primary, cộng thêm phí Replication cho DR. |
| **NAT Gateway** | Phí duy trì / giờ / AZ | ~$65 / tháng (2 AZs) | Nằm ở Centralized VPC Inspection. |
| **Client VPN** | Phí Endpoint / giờ | ~$72 / tháng | Chưa tính phí $0.05/giờ/user khi kết nối. |
| **S2S VPN** | Phí Connection / giờ | ~$108 / tháng (3 tunnels) | Kết nối về 3 chi nhánh FortiGate. |

---

## 2. Giải Đáp: Dùng Cloudflare thì có cần AWS Network Firewall không?

Trong đồ án mạng doanh nghiệp, ban giám khảo rất hay hỏi câu này để kiểm tra kiến thức về **Ingress** (chiều vào) và **Egress** (chiều ra). Câu trả lời ngắn gọn là: **Không thể thay thế hoàn toàn cho nhau.**

**1. Khác biệt về vai trò (Vị trí hoạt động):**
*   **Cloudflare (hoặc AWS WAF):** Là tường lửa lớp 7 (Layer 7 WAF) hoạt động ở "biên" (Edge). Nó bảo vệ **chiều VÀO (Ingress)**, chặn hacker, DDoS, SQL Injection trước khi traffic chạm tới máy chủ của bạn.
*   **AWS Network Firewall (ANFW):** Là tường lửa mạng (Layer 3-7) nằm sâu bên trong VPC. Nó bảo vệ **chiều RA (Egress)** và **Nội bộ (East-West)**. Ví dụ: Nếu một server của bạn bị nhiễm mã độc, ANFW sẽ chặn server đó tải thêm mã độc từ internet về, hoặc ngăn nó lây lan sang VPC khác. Cloudflare *không thể* thấy hay chặn được traffic đi từ trong AWS ra ngoài internet.

**2. So sánh Chi phí & Tối ưu:**

| Loại Firewall | Phương án AWS (Hiện tại) | Phương án Cloudflare | Lời khuyên Tối ưu (FinOps) |
| :--- | :--- | :--- | :--- |
| **Bảo vệ chiều VÀO (WAF / CDN)** | Dùng AWS CloudFront + AWS WAF.<br>Phí duy trì: ~$10/tháng + Phí request. | Dùng Cloudflare Pro ($20/tháng) hoặc Business ($200/tháng). Bỏ CloudFront. | **Nên dùng Cloudflare** nếu muốn tiết kiệm phí băng thông (Data Out) và chống DDoS tốt với chi phí cố định rẻ. AWS WAF tính tiền theo từng request rất dễ bị "đội giá". |
| **Bảo vệ chiều RA (Network Egress)** | Dùng AWS Network Firewall.<br>Phí duy trì: **~$570/tháng**. | *Cloudflare Zero Trust (Gateway)*: Cần setup phức tạp với VPN tunnel, thường dùng cho user hơn là server. | Rất đắt! Nếu doanh nghiệp không bị ép buộc bởi compliance (PCI-DSS), hãy **xóa bỏ AWS Network Firewall**. Chỉ cần cấu hình AWS Security Group thật chặt là đủ bảo mật cơ bản. |

*Tóm lại:* Nếu chuyển phần CDN/WAF sang Cloudflare, bạn sẽ tiết kiệm được khá nhiều tiền băng thông và phí AWS WAF. Tuy nhiên, việc giữ hay bỏ AWS Network Firewall phụ thuộc vào yêu cầu bảo mật chiều đi ra (Egress), chứ Cloudflare không thay thế được chức năng này.

---

## 3. Chiến Lược Tối Ưu Hóa (Optimization Strategies)

Để tối ưu hóa chi phí cho doanh nghiệp, chúng ta có thể áp dụng các chiến lược sau vào thiết kế kiến trúc:

### 2.1. Tối ưu Networking (Mạng lưới)

*   **Tối ưu Transit Gateway (TGW):**
    *   *Hiện tại:* Đang dùng TGW để nối 5 VPC (Singapore) và 2 VPC (Sydney). Điều này rất tốt cho quản lý tập trung và định tuyến qua Inspection VPC.
    *   *Tối ưu:* Giữ nguyên TGW vì đây là Best Practice cho Enterprise. Tuy nhiên, để tiết kiệm phí xử lý Data ($0.02/GB), có thể sử dụng **VPC Peering** trực tiếp giữa `VPC-PROD-APP` và `VPC-PROD-DATA` nếu lưu lượng giữa App và Database rất lớn (VPC Peering miễn phí phí xử lý data, chỉ tính phí data transfer nếu khác AZ).
*   **Tối ưu Network Firewall & NAT Gateway (Mô hình Egress Tập trung):**
    *   *Hiện tại:* Kiến trúc đang dùng mô hình **Centralized Egress** (VPC-INSPECTION) với NAT Gateway và Network Firewall. Đây là thiết kế **rất tốt** về mặt chi phí so với việc đặt NAT GW ở từng VPC (Distributed).
    *   *Tối ưu thêm:* Nếu doanh nghiệp eo hẹp ngân sách, có thể loại bỏ AWS Network Firewall và thay bằng các EC2 chạy phần mềm tường lửa mã nguồn mở (như pfSense, OPNsense, hoặc Suricata tự cài) kết hợp với Gateway Load Balancer. Tuy nhiên, AWS Network Firewall dạng Managed vẫn được ưu tiên vì giảm thiểu chi phí vận hành (Operational Overhead).
*   **Tối ưu VPN:**
    *   Sử dụng tính năng **Split-Tunneling** cho Client VPN (hiện đã được bật trong code Terraform). Điều này giúp các traffic lướt web thông thường của nhân viên không đi qua AWS, tiết kiệm đáng kể băng thông (Data Egress) ra Internet của AWS.

### 2.2. Tối ưu Compute (Tính toán)

*   **Sử dụng Chip ARM (AWS Graviton):**
    *   Đổi các dịch vụ có hỗ trợ (RDS Aurora, ElastiCache, Fargate) sang dùng kiến trúc ARM64 (Graviton2/Graviton3). Chip Graviton mang lại hiệu năng cao hơn 20% và chi phí **rẻ hơn 20%** so với chip x86/Intel. *(Trong `variables.tf`, biến `instance_class = "db.r6g.large"` chữ "g" chính là Graviton -> Bạn đã làm tốt phần này).*
*   **Tận dụng Compute Savings Plans / Reserved Instances:**
    *   Sau khi hệ thống ổn định, doanh nghiệp nên cam kết mua Compute Savings Plan (1 năm hoặc 3 năm) cho Fargate và Reserved Instances cho Aurora/Redis để giảm từ **30% đến 50%** chi phí.
*   **Tự động Mở/Tắt môi trường Non-Prod:**
    *   Sử dụng AWS Instance Scheduler để tự động tắt các môi trường Dev/Staging ngoài giờ làm việc (ví dụ: tắt từ 7h tối đến 7h sáng, nghỉ thứ 7 & CN), giúp giảm tới 70% chi phí môi trường Non-Prod.

### 2.3. Tối ưu Database & DR (Lưu trữ và Dự phòng)

*   **Aurora Serverless v2:**
    *   Thay vì dùng instance cố định (Provisioned như `r6g.large`), hãy chuyển sang **Aurora Serverless v2**. Nó sẽ tự động scale ACU (Aurora Capacity Unit) theo tải thực tế. Vào ban đêm khi ít người dùng, nó sẽ scale xuống mức tối thiểu, giúp tiết kiệm chi phí rất lớn so với việc bật instance to 24/7.
*   **Chiến lược Disaster Recovery (DR) tiết kiệm hơn:**
    *   *Hiện tại:* Kiến trúc đang dùng **Pilot Light** với Aurora Global Database (cần bật ít nhất 1 instance đọc ở Sydney 24/7).
    *   *Tối ưu:* Nếu doanh nghiệp chấp nhận RTO/RPO cao hơn một chút (ví dụ: mất dữ liệu 15 phút, thời gian phục hồi 4 tiếng), hãy dùng **Cross-Region Automated Backups**. Backup sẽ được tự động đồng bộ sang Sydney. Khi có sự cố (Disaster), ta mới dùng Terraform spin-up hệ thống ở Sydney từ bản backup. Cách này **loại bỏ hoàn toàn chi phí chạy instance ở Sydney** trong điều kiện bình thường.

---

## 3. Các Phương Án Kiến Trúc Cho Doanh Nghiệp

Để đưa vào đồ án, bạn có thể trình bày 3 mức (Tiers) kiến trúc để doanh nghiệp (Hội đồng) lựa chọn tùy theo ngân sách:

### 📦 Option 1: Maximum Security & HA (Kiến trúc hiện tại)
*   **Đặc điểm:** Dùng đầy đủ TGW, AWS Network Firewall, Aurora Global, Multi-Region Pilot Light.
*   **Chi phí:** Cao (Hàng ngàn USD/tháng).
*   **Dành cho:** Doanh nghiệp có yêu cầu tuân thủ bảo mật khắt khe (ISO 27001, PCI-DSS), ngân sách dồi dào, zero downtime.

### ⚖️ Option 2: Cost-Optimized Enterprise (Khuyên dùng)
*   **Đặc điểm:**
    *   Giữ TGW để quản lý mạng.
    *   Bỏ AWS Network Firewall, chỉ dùng Security Groups nghiêm ngặt + NAT Gateway tập trung.
    *   Đổi Aurora sang Serverless v2.
    *   Chuyển DR ở Sydney từ *Pilot Light* sang *Backup & Restore* (chỉ đồng bộ S3 Snapshot sang Sydney, không chạy sẵn Database và ECS ở Sydney).
*   **Chi phí:** Trung bình (Tiết kiệm ~60% so với Option 1).
*   **Dành cho:** Doanh nghiệp SME muốn cân bằng giữa chi phí và tính chuyên nghiệp.

### 🏃 Option 3: Startup / MVP
*   **Đặc điểm:**
    *   Bỏ TGW, dùng VPC Peering giữa VPC-APP và VPC-SHARED.
    *   Gộp chung các Subnet, chỉ dùng 1-2 VPC.
    *   Chỉ dùng ALB + Fargate Spot.
*   **Chi phí:** Rất thấp.
*   **Dành cho:** Chạy lab đồ án, startup giai đoạn đầu.
