# Online Boutique – GitOps Configuration Repository

Repo này chứa toàn bộ cấu hình GitOps cho hệ thống Google Online Boutique chạy trên AWS EKS, quản lý bởi ArgoCD.

## Cấu Trúc Thư Mục

```
online-boutique-config/
├── README.md
├── argocd/
│   ├── install/
│   │   └── values.yaml               # Helm values cho ArgoCD
│   └── apps/
│       ├── dev/
│       │   ├── online-boutique.yaml   # ArgoCD App: 11 microservices (dev)
│       │   ├── aws-lb-controller.yaml # ArgoCD App: AWS Load Balancer Controller
│       │   └── cluster-autoscaler.yaml# ArgoCD App: Cluster Autoscaler
│       └── staging/
│           └── online-boutique.yaml   # ArgoCD App: 11 microservices (staging)
├── base/
│   └── online-boutique/              # Kustomize base manifests (11 microservices)
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       └── *.yaml
└── overlays/
    ├── dev/                          # Dev overlay (auto-sync, ElastiCache Redis patch)
    │   ├── kustomization.yaml
    │   └── patches/
    │       └── cartservice-redis.yaml
    └── staging/                      # Staging overlay (manual sync)
        ├── kustomization.yaml
        └── patches/
            └── cartservice-redis.yaml
```

## Luồng Hoạt Động (GitOps Flow)

1. **CI:** Khi developer push code lên `online-boutique-app`, GitHub Actions CI sẽ build Docker image, quét bảo mật, push lên AWS ECR với tag `sha-<commit>`.
2. **Update Manifests:** CI composite action cập nhật tag mới vào file `overlays/dev/kustomization.yaml` của repo này.
3. **CD:** ArgoCD nhận biết thay đổi (drift detection) từ repo này và tự động đồng bộ (auto-sync trên môi trường Dev) đưa ứng dụng mới lên EKS cluster.
