# Online Boutique – GitOps Configuration Repository

Repository này quản lý toàn bộ cấu hình GitOps cho hệ sinh thái microservices Google Online Boutique chạy trên AWS EKS, được đồng bộ và vận hành tự động bởi ArgoCD.

Nhánh `main` công khai của repository **tuyệt đối không chứa bất kỳ giá trị định danh tài khoản hoặc thông tin nhạy cảm nào** (Account-agnostic). Toàn bộ cấu hình theo môi trường được gom gọn vào file `env.properties` duy nhất cho từng overlay, và ArgoCD Application manifests được render linh hoạt lúc bootstrap cluster.

---

## 1. Cấu Trúc Thư Mục

```text
online-boutique-config/
├── README.md
├── argocd/
│   ├── install/
│   │   └── values.yaml               # Helm values cài đặt ArgoCD server
│   └── apps/
│       ├── dev/                      # ArgoCD Application templates môi trường dev (${VAR})
│       │   ├── aws-lb-controller.yaml
│       │   ├── cluster-autoscaler.yaml
│       │   ├── istio-config.yaml
│       │   ├── kube-prometheus-stack.yaml
│       │   ├── kyverno-policies.yaml
│       │   ├── kyverno.yaml
│       │   ├── loki.yaml
│       │   ├── monitoring-stack.yaml
│       │   ├── online-boutique.yaml
│       │   ├── otel-collector.yaml
│       │   └── tempo.yaml
│       └── staging/                  # ArgoCD Application templates môi trường staging
│           └── online-boutique.yaml
├── base/
│   ├── istio/                        # Cấu hình Istio Service Mesh
│   ├── kyverno/                      # Kyverno ClusterPolicies (bảo mật, ký ảnh Cosign)
│   ├── monitoring/                   # Cấu hình Prometheus, Alertmanager, Grafana Dashboards
│   └── online-boutique/              # 11 Microservices với image gốc REGISTRY/online-boutique/<svc>:latest
├── overlays/
│   ├── dev/
│   │   ├── env.properties            # Cấu hình duy nhất cho môi trường dev
│   │   └── kustomization.yaml        # Kustomize replacements, configMapGenerator & image tags
│   └── staging/
│       ├── env.properties            # Cấu hình duy nhất cho môi trường staging
│       └── kustomization.yaml
└── scripts/
    ├── bootstrap-argocd.sh           # Script bootstrap cụm bằng Bash (hỗ trợ --dry-run)
    └── bootstrap-argocd.ps1          # Script bootstrap cụm bằng PowerShell (hỗ trợ -DryRun)
```

---

## 2. Quy Trình Quản Lý Cấu Hình: `env.properties` & Nhánh `deploy/<env>`

### Cơ Chế Tách Biệt Dữ Liệu Nhạy Cảm
1. **Trên nhánh `main` công khai:**
   - Các file `overlays/<env>/env.properties` chỉ chứa các giá trị placeholder:
     ```properties
     ECR_REGISTRY=<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com
     REDIS_ADDR=<REDIS_ENDPOINT>:6379
     ```
   - Trong `base/online-boutique/*.yaml`, hình ảnh container sử dụng prefix trung lập: `REGISTRY/online-boutique/<svc>:latest`.

2. **Trên nhánh triển khai `deploy/<env>` (ví dụ `deploy/dev`, `deploy/staging`):**
   - Cluster thật sẽ trỏ ArgoCD vào nhánh `deploy/<env>`.
   - Developer/DevOps chỉ cần cập nhật các giá trị thực tế vào duy nhất file `overlays/<env>/env.properties`:
     ```properties
     ECR_REGISTRY=your-account-id.dkr.ecr.us-east-1.amazonaws.com
     REDIS_ADDR=your-redis-cluster-node:6379
     ```

3. **Cách Kustomize Hoạt Động:**
   - `configMapGenerator` tạo configmap nội bộ mang tên `env-config` từ `env.properties`, gắn annotation `config.kubernetes.io/local-config: "true"` để **không xuất hiện trong đầu ra manifest build thực tế**.
   - Mục `replacements` tự động:
     - Thay thế phân đoạn đầu tiên của đường dẫn image container (`REGISTRY`) bằng giá trị `ECR_REGISTRY`.
     - Cập nhật biến môi trường `REDIS_ADDR` cho container `server` trong `cartservice`.
   - Danh sách `images` trong `kustomization.yaml` định danh image dưới dạng `REGISTRY/online-boutique/<svc>`, đảm bảo tương thích tuyệt đối với bộ lọc CI (`*/$SERVICE`).

---

## 3. Khởi Tạo Cụm & ArgoCD (Bootstrap Workflow)

Các manifest trong `argocd/apps/<env>/*.yaml` sử dụng định dạng biến `${VAR}` shell-style:
- `${GITHUB_ORG}`: Tên GitHub Organization hoặc User sở hữu repository.
- `${AWS_ACCOUNT_ID}`: AWS Account ID 12 chữ số.
- `${AWS_REGION}`: AWS Region triển khai (ví dụ: `us-east-1`).
- `${EKS_CLUSTER_NAME}`: Tên cluster EKS (mặc định: `online-boutique-<env>`).
- `${CONFIG_REVISION}`: Nhánh Git mà ArgoCD theo dõi (mặc định: `deploy/<env>`).

Các file này không bị ghi đè vào Git mà được render tại chỗ và apply trực tiếp thông qua bootstrap script.

### Chạy Script Bootstrap

#### Sử Dụng Bash (`scripts/bootstrap-argocd.sh`)
```bash
# Thiết lập các biến môi trường bắt buộc
export GITHUB_ORG="my-github-org"
export AWS_ACCOUNT_ID="your-aws-account-id"
export AWS_REGION="us-east-1"

# Tùy chọn: đặt mật khẩu admin Grafana (nếu không đặt, script sẽ hỏi bảo mật trên terminal)
export GRAFANA_ADMIN_PASSWORD="MySecurePassword123!"

# Chế độ xem trước render (Dry-Run)
./scripts/bootstrap-argocd.sh dev --dry-run

# Áp dụng trực tiếp vào Kubernetes cluster
./scripts/bootstrap-argocd.sh dev
```

#### Sử Dụng PowerShell (`scripts/bootstrap-argocd.ps1`)
```powershell
$env:GITHUB_ORG = "my-github-org"
$env:AWS_ACCOUNT_ID = "your-aws-account-id"
$env:AWS_REGION = "us-east-1"
$env:GRAFANA_ADMIN_PASSWORD = "MySecurePassword123!"

# Chế độ xem trước render (Dry-Run)
.\scripts\bootstrap-argocd.ps1 -Env dev -DryRun

# Áp dụng trực tiếp vào Kubernetes cluster
.\scripts\bootstrap-argocd.ps1 -Env dev
```

---

## 4. Quản Lý Mật Khẩu Grafana (Secret Management)

- Mật khẩu quản trị Grafana **không được lưu trữ trong Git**.
- File giá trị `kube-prometheus-stack` sử dụng cấu hình:
  ```yaml
  grafana:
    enabled: true
    admin:
      existingSecret: grafana-admin
      userKey: admin-user
      passwordKey: admin-password
  ```
- Script `bootstrap-argocd` tự động khởi tạo namespace `monitoring` và Kubernetes Secret `grafana-admin` một cách idempotent (`--dry-run=client -o yaml | kubectl apply -f -`) trước khi nạp ứng dụng ArgoCD.

---

## 5. Tích Hợp CI/CD Pipeline (Image Tagging)

1. Khi pipeline CI trong repository ứng dụng `online-boutique-app` hoàn thành kiểm thử và build ảnh container mới lên AWS ECR:
   - Action composite `update-manifests` sẽ cập nhật `newTag: sha-<commit>` vào file `overlays/<env>/kustomization.yaml`.
   - Lệnh cập nhật sử dụng cú pháp `yq`:
     ```bash
     yq e '(.images[] | select(.name == "*/'$SERVICE'") | .newTag) = "'$TAG'"' -i overlays/dev/kustomization.yaml
     ```
   - Cú pháp glob `*/$SERVICE` khớp hoàn hảo với `REGISTRY/online-boutique/$SERVICE`.
2. Action sẽ commit và push thay đổi vào nhánh được cấu hình trong biến môi trường GitHub Repository Variable: `CONFIG_REPO_BRANCH` (mặc định trỏ tới `deploy/dev` hoặc `deploy/<env>`).
3. ArgoCD lắng nghe thay đổi trên nhánh `deploy/<env>` và tự động đồng bộ (Auto-sync) phiên bản mới nhất lên EKS cluster.
