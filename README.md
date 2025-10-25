# srespace-tools – GitOps Platform on **GKE** (External Vault via ESO)

A production‑grade, **script‑free** GitOps platform for **Google Kubernetes Engine (GKE)**. Everything is declared as Kubernetes/Argo CD manifests so you manage it entirely through Git. **All secrets** originate in an **external HashiCorp Vault** and are synced into Kubernetes via **External Secrets Operator (ESO)**. Ingress is handled by **Traefik**. Service‑to‑service encryption is provided by **Linkerd**.

> ✅ **Best practice**: Every platform tool is customized **only via Helm values files**. We avoid ad‑hoc Kustomize patches that tweak chart internals. Argo CD uses **multi‑source Applications** so charts come from upstream repos while values come from this repo.

---

## Applications (platform components)

* **Argo CD** – GitOps controller that continuously reconciles cluster state from Git.
* **External Secrets (ESO)** – Reads secret material from external Vault and writes Kubernetes Secrets.
* **Traefik** – Ingress controller that exposes HTTP(S) services via a GKE Load Balancer.
* **Linkerd** – Service mesh with zero‑trust mTLS, metrics, and diagnostics.
* **Kyverno** – Policy enforcement (validation/mutation) and supply‑chain controls.
* **Metrics Server** – Resource metrics API feeding HPAs.
* **Prometheus Stack** – kube‑prometheus‑stack: Prometheus + Alertmanager + Grafana.
* **Loki (with Promtail)** – Centralized logging; Grafana datasource.
* **Kubecost** – Cost monitoring and allocation.
* **Goldilocks** – Resource recommendations (uses VPA under the hood).
* **Redis Cluster** – HA, sharded Redis for caching/queues.
* **Reloader** – Auto‑restart on Secret/ConfigMap changes.

---

## Repository layout (script‑free, with file‑by‑file comments)

```text
srespace-tools/
├─ README.md                        # You are here: full documentation, generation guides, best practices
├─ gitops/
│  ├─ app-of-apps/
│  │  ├─ kustomization.yaml         # Kustomize entry for Argo CD “App of Apps”
│  │  └─ applications.yaml          # Two Argo CD Applications: platform-apps-dev & platform-apps-prod
│  ├─ platform-tools/
│  │  ├─ base/
│  │  │  ├─ kustomization.yaml      # Lists all platform Argo CD Applications (common to all envs)
│  │  │  ├─ argocd-app.yaml         # Argo CD (self-managed) – chart from upstream, values from this repo
│  │  │  ├─ external-secrets-app.yaml # ESO Helm chart Application (installs CRDs & controllers)
│  │  │  ├─ traefik-app.yaml        # Traefik Helm chart Application (Ingress)
│  │  │  ├─ linkerd-app.yaml        # Linkerd CRDs + control plane Applications
│  │  │  ├─ kyverno-app.yaml        # Kyverno Helm chart Application (engine only)
│  │  │  ├─ kyverno-policies/       # Kyverno policy YAMLs (not Helm)
│  │  │  │  ├─ require-requests-limits.yaml   # Enforce requests/limits on Pods
│  │  │  │  ├─ disallow-latest-tag.yaml       # Disallow :latest image tag
│  │  │  │  └─ verify-cosign-images.yaml      # Verify signed images (Cosign keyless)
│  │  │  ├─ metrics-server-app.yaml # Metrics Server Helm chart Application
│  │  │  ├─ kube-prometheus-stack-app.yaml # Prometheus + Grafana + Alertmanager
│  │  │  ├─ loki-stack-app.yaml     # Loki + Promtail
│  │  │  ├─ kubecost-app.yaml       # Kubecost cost analyzer
│  │  │  ├─ goldilocks-app.yaml     # Goldilocks recommender
│  │  │  ├─ redis-cluster-app.yaml  # Bitnami Redis Cluster
│  │  │  └─ reloader-app.yaml       # Reloader controller
│  │  ├─ values/                    # ✅ All customization lives here (per tool, per environment)
│  │  │  ├─ dev/
│  │  │  │  ├─ traefik.yaml
│  │  │  │  ├─ linkerd.yaml
│  │  │  │  ├─ kyverno.yaml
│  │  │  │  ├─ metrics-server.yaml
│  │  │  │  ├─ kube-prometheus-stack.yaml
│  │  │  │  ├─ loki-stack.yaml
│  │  │  │  ├─ kubecost.yaml
│  │  │  │  ├─ goldilocks.yaml
│  │  │  │  ├─ redis-cluster.yaml
│  │  │  │  └─ reloader.yaml
│  │  │  └─ prod/
│  │  │     ├─ traefik.yaml
│  │  │     ├─ linkerd.yaml
│  │  │     ├─ kyverno.yaml
│  │  │     ├─ metrics-server.yaml
│  │  │     ├─ kube-prometheus-stack.yaml
│  │  │     ├─ loki-stack.yaml
│  │  │     ├─ kubecost.yaml
│  │  │     ├─ goldilocks.yaml
│  │  │     ├─ redis-cluster.yaml
│  │  │     └─ reloader.yaml
│  │  └─ stores/
│  │     ├─ clustersecretstore-vault.yaml # ESO ClusterSecretStore → external Vault
│  │     └─ externalsecrets/
│  │        ├─ linkerd-issuer.yaml        # ESO ExternalSecret → Linkerd issuer TLS
│  │        └─ projectflow-env.yaml       # ESO ExternalSecret → ProjectFlow env vars
│  ├─ apps/
│  │  ├─ projectflow/               # Sample workload (your app)
│  │  │  ├─ chart/                  # Helm chart for ProjectFlow
│  │  │  ├─ values-dev.yaml         # DEV Helm values
│  │  │  └─ values-prod.yaml        # PROD Helm values
│  │  └─ app-app.yaml               # Argo CD Application for ProjectFlow (points to chart + values)
│  └─ projects/
│     ├─ platform-tools-project.yaml # Argo CD project grouping platform apps
│     └─ workloads-project.yaml      # Argo CD project for workloads (apps namespace)
└─ .github/workflows/
   ├─ ci-build-secure.yml            # CI: build → SBOM → scan → sign → provenance (YAML only)
   └─ cd-bump-and-sync.yml           # CD: bump Helm values + policy check + Argo CD sync (YAML only)
```

---

## App‑of‑Apps (Argo CD)

**gitops/app-of-apps/applications.yaml** (independent dev & prod controllers)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-apps-dev
  namespace: argocd
spec:
  project: platform-tools
  source:
    repoURL: https://github.com/YOURORG/srespace-tools.git
    path: gitops/platform-tools/base
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: platform-tools
  syncPolicy:
    automated: { selfHeal: true, prune: true }
    syncOptions: [ CreateNamespace=true ]
  sources: []  # not used at this level
  # Dev/Prod values are selected in each tool’s Application below using multi-source and $values/
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-apps-prod
  namespace: argocd
spec:
  project: platform-tools
  source:
    repoURL: https://github.com/YOURORG/srespace-tools.git
    path: gitops/platform-tools/base
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: platform-tools
  syncPolicy:
    automated: { selfHeal: true, prune: true }
    syncOptions: [ CreateNamespace=true ]
```

> We keep **one base** list of Applications and make each Application itself **multi‑source**: source A = upstream Helm chart, source B = this repo with the env‑specific values files. This is the recommended Argo CD pattern for clean Helm customization.

---

## How we customize each tool (Helm values files + multi‑source)

**Argo CD Application pattern (example: Traefik)** – `gitops/platform-tools/base/traefik-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: traefik
  namespace: argocd
spec:
  project: platform-tools
  sources:
    # 1) Upstream chart
    - repoURL: https://traefik.github.io/charts
      chart: traefik
      targetRevision: 34.3.0
      helm:
        valueFiles:
          - $values/gitops/platform-tools/values/dev/traefik.yaml    # ← switch to prod values by Argo CD label/param
    # 2) Values repo (this repo)
    - repoURL: https://github.com/YOURORG/srespace-tools.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: platform-tools
  syncPolicy:
    automated: { selfHeal: true, prune: true }
```

> To deploy **prod**, duplicate this file as `traefik-app-prod.yaml` or parametrize via **Argo CD ApplicationSet** to pick the correct values file (`$values/.../prod/traefik.yaml`). Below we show both **dev** and **prod** files for clarity.

**Traefik (prod)** – `gitops/platform-tools/base/traefik-app-prod.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: traefik-prod, namespace: argocd }
spec:
  project: platform-tools
  sources:
    - repoURL: https://traefik.github.io/charts
      chart: traefik
      targetRevision: 34.3.0
      helm:
        valueFiles:
          - $values/gitops/platform-tools/values/prod/traefik.yaml
    - repoURL: https://github.com/YOURORG/srespace-tools.git
      targetRevision: main
      ref: values
  destination: { server: https://kubernetes.default.svc, namespace: platform-tools }
  syncPolicy: { automated: { selfHeal: true, prune: true } }
```

> We apply the **same pattern** for Linkerd, Kyverno, Metrics Server, kube‑prometheus‑stack, Loki, Kubecost, Goldilocks, Redis, and Reloader – each has a **dev** and **prod** Application file pointing to the **same upstream chart** but a **different values file** under `values/dev|prod/`.

---

## Example Helm values (dev vs prod)

**Traefik**

* `values/dev/traefik.yaml`

```yaml
logs:
  general: { level: DEBUG }
ports:
  websecure: { tls: { enabled: true } }
ingressRoute:
  dashboard: { enabled: true }
```

* `values/prod/traefik.yaml`

```yaml
logs:
  general: { level: ERROR }
ports:
  websecure: { tls: { enabled: true } }
ingressRoute:
  dashboard: { enabled: false }
```

**Redis Cluster**

* `values/dev/redis-cluster.yaml`

```yaml
cluster: { nodes: 3 }
resources:
  requests: { cpu: 100m, memory: 256Mi }
  limits:   { cpu: 300m, memory: 512Mi }
```

* `values/prod/redis-cluster.yaml`

```yaml
cluster: { nodes: 6 }
resources:
  requests: { cpu: 500m, memory: 2Gi }
  limits:   { cpu: 2, memory: 4Gi }
```

**kube‑prometheus‑stack**

* `values/dev/kube-prometheus-stack.yaml`

```yaml
prometheus:
  prometheusSpec:
    scrapeInterval: 60s
```

* `values/prod/kube-prometheus-stack.yaml`

```yaml
prometheus:
  prometheusSpec:
    scrapeInterval: 30s
```

**Loki**

* `values/dev/loki-stack.yaml`

```yaml
loki:
  retentionPeriod: 72h
```

* `values/prod/loki-stack.yaml`

```yaml
loki:
  retentionPeriod: 168h
```

**Linkerd**

* `values/dev/linkerd.yaml`

```yaml
identity:
  externalCA: true
proxy:
  resources:
    requests: { cpu: 20m, memory: 64Mi }
    limits:   { cpu: 100m, memory: 128Mi }
```

* `values/prod/linkerd.yaml`

```yaml
identity:
  externalCA: true
proxy:
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 250m, memory: 256Mi }
```

**Kyverno** (engine chart values – policies remain separate YAMLs)

* `values/dev/kyverno.yaml`

```yaml
deploy:
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 200m, memory: 256Mi }
```

* `values/prod/kyverno.yaml`

```yaml
deploy:
  resources:
    requests: { cpu: 200m, memory: 256Mi }
    limits:   { cpu: 500m, memory: 512Mi }
```

*(Similar minimal examples exist for Metrics Server, Kubecost, Goldilocks, Reloader.)*

---

## External Secrets (Vault) – files

**ClusterSecretStore** – `gitops/platform-tools/stores/clustersecretstore-vault.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata: { name: vault }
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      version: v2
      auth:
        kubernetes:
          mountPath: auth/kubernetes
          role: es-reader
```

**ProjectFlow env** – `gitops/platform-tools/stores/externalsecrets/projectflow-env.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: projectflow-env, namespace: apps }
spec:
  refreshInterval: 15m
  secretStoreRef: { name: vault, kind: ClusterSecretStore }
  target: { name: projectflow-env, creationPolicy: Owner }
  data:
    - secretKey: DATABASE_URL
      remoteRef: { key: secret/Dev-secret/projectflow, property: DATABASE_URL }
    - secretKey: JWT_SECRET
      remoteRef: { key: secret/Dev-secret/projectflow, property: JWT_SECRET }
    - secretKey: REDIS_URL
      remoteRef: { key: secret/Dev-secret/projectflow, property: REDIS_URL }
```

> For prod, create `stores/externalsecrets/projectflow-env-prod.yaml` pointing at `secret/Prod-secret/projectflow`.

**Linkerd issuer** – `gitops/platform-tools/stores/externalsecrets/linkerd-issuer.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: linkerd-identity-issuer, namespace: linkerd }
spec:
  refreshInterval: 12h
  secretStoreRef: { name: vault, kind: ClusterSecretStore }
  target:
    name: linkerd-identity-issuer
    creationPolicy: Owner
    template: { type: kubernetes.io/tls }
  data:
    - secretKey: tls.crt
      remoteRef: { key: pki_int/issue/linkerd, property: certificate }
    - secretKey: tls.key
      remoteRef: { key: pki_int/issue/linkerd, property: private_key }
    - secretKey: ca.crt
      remoteRef: { key: pki_int/issue/linkerd, property: issuing_ca }
```

---

## ProjectFlow app (your workload)

* `gitops/apps/projectflow/chart/` – Helm chart (Deployment/Service/IngressRoute/HPA), reads env via `envFromSecret`.
* `values-dev.yaml` & `values-prod.yaml` – customized per env.
* `gitops/apps/app-app.yaml` – Argo CD Application; CI bumps `.image.tag`.

**values-dev.yaml (excerpt)**

```yaml
image:
  repository: LOCATION-docker.pkg.dev/PROJECT/REPO/projectflow
  tag: "dev-<shortsha>"
  pullPolicy: IfNotPresent

ingress:
  enabled: true
  className: traefik
  hosts: [ projectflow.dev.example.com ]

envFromSecret: projectflow-env
```

**values-prod.yaml (excerpt)**

```yaml
image:
  repository: LOCATION-docker.pkg.dev/PROJECT/REPO/projectflow
  tag: "prod-<shortsha>"
  pullPolicy: IfNotPresent

ingress:
  enabled: true
  className: traefik
  hosts: [ projectflow.example.com ]

envFromSecret: projectflow-env
```

Integration flow: Traefik routes traffic; Linkerd injects mTLS; ESO provides secrets; Reloader restarts on rotations; Prometheus/Loki observe; Kyverno enforces; Kubecost tracks costs; Goldilocks recommends tuning.

---

## How to generate and store secrets/certs in Vault

* **Strong password**: `openssl rand -base64 32`
* **JWT secret (HS256)**: `openssl rand -hex 64`
* **Store in Vault (KV v2)**:

  ```bash
  vault kv put secret/Dev-secret/projectflow DATABASE_URL="..." JWT_SECRET="..." REDIS_URL="redis://..."
  vault kv put secret/Prod-secret/projectflow DATABASE_URL="..." JWT_SECRET="..." REDIS_URL="redis://..."
  ```
* **Alertmanager receivers**:

  ```bash
  vault kv put secret/Dev-secret/observability PD_KEY="<routing-key>" MM_HOOK="<hook>"
  vault kv put secret/Prod-secret/observability PD_KEY="<routing-key>" MM_HOOK="<hook>"
  ```
* **Argo CD admin hash**:

  ```bash
  argocd account bcrypt --password '<admin-password>' | \
    xargs -I{} vault kv put secret/Dev-secret/argocd ADMIN_PASSWORD_HASH="{}"
  ```
* **Linkerd issuer via Vault PKI**:

  ```bash
  vault secrets enable -path=pki_int pki
  vault write pki_int/roles/linkerd \
    allowed_domains="linkerd.cluster.local" allow_subdomains=true \
    key_type="rsa" key_bits=2048 max_ttl="24h"
  # ESO will call pki_int/issue/linkerd; no manual cert write needed
  ```
* **Vault Kubernetes auth**:

  ```bash
  vault auth enable kubernetes || true
  vault write auth/kubernetes/config kubernetes_host="https://$KUBE_API" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local"
  cat > es-reader.hcl <<'EOF'
  path "secret/Dev-secret/*"  { capabilities=["read","list"] }
  path "secret/Prod-secret/*" { capabilities=["read","list"] }
  path "pki_int/issue/linkerd" { capabilities=["update"] }
  EOF
  vault policy write es-reader es-reader.hcl
  vault write auth/kubernetes/role/es-reader \
    bound_service_account_names="external-secrets,external-secrets-sa,default" \
    bound_service_account_namespaces="security,apps,argocd,observability" \
    policies="es-reader" ttl=1h
  ```

---

## DevSecOps posture (unchanged)

* **gitleaks**, **Conftest/OPA**, **Syft SBOM**, **Trivy/Grype**, **Cosign keyless**, **Kyverno** verification (Audit in dev / Enforce in prod).

---

## Next steps

1. Put your real **Vault URL & role** in `stores/clustersecretstore-vault.yaml`.
2. Set real hostnames in `values/dev|prod/traefik.yaml`.
3. Fill Artifact Registry path in ProjectFlow values; wire CI to bump the image tag.
4. (Optional) Use **ApplicationSet** to generate dev/prod Applications from a single template selecting the appropriate `$values/...` file.
