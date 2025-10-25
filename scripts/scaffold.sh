#!/usr/bin/env bash
set -euo pipefail

# ----- SETTINGS (override via env) -----
REPO_URL="${REPO_URL:-https://github.com/nolet7/total-gitops.git}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
VAULT_API="${VAULT_API:-http://48.217.51.59:8200}"   # ESO needs Vault API base, not UI path

# ----- HELPERS -----
mk() { # create file only if missing
  local f="$1"; shift
  [ -f "$f" ] || { mkdir -p "$(dirname "$f")"; cat > "$f" <<<"$*"; }
}
mkh() { # create/overwrite (hard write)
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"; cat > "$f" <<<"$*"
}

# ----- DIRS -----
mkdir -p gitops/app-of-apps \
         gitops/projects \
         gitops/apps/projectflow/chart/templates \
         gitops/platform-tools/base/kyverno-policies \
         gitops/platform-tools/stores/externalsecrets \
         gitops/platform-tools/values/dev \
         gitops/platform-tools/values/prod

# ----- README -----
mkh README.md "# srespace-tools – GitOps Platform on GKE (External Vault via ESO)

Helm-only customization via Argo CD **multi-source Applications**:
- Source A: upstream Helm charts
- Source B: this repo values under \`gitops/platform-tools/values/dev|prod/\`

Secrets live in External Vault and sync into Kubernetes via External Secrets Operator (ESO).
"

# ----- APP-OF-APPS -----
mkh gitops/app-of-apps/kustomization.yaml "resources:
  - applications.yaml
"

mkh gitops/app-of-apps/applications.yaml "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-apps
  namespace: argocd
spec:
  project: platform-tools
  source:
    repoURL: ${REPO_URL}
    path: gitops/platform-tools/base
    targetRevision: ${BRANCH}
  destination:
    server: https://kubernetes.default.svc
    namespace: platform-tools
  syncPolicy:
    automated: { selfHeal: true, prune: true }
    syncOptions: [ CreateNamespace=true ]
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: projectflow
  namespace: argocd
spec:
  project: workloads
  sources:
    - repoURL: ${REPO_URL}
      targetRevision: ${BRANCH}
      ref: values
    - repoURL: ${REPO_URL}
      path: gitops/apps/projectflow/chart
      targetRevision: ${BRANCH}
      helm:
        valueFiles:
          - \$values/gitops/apps/projectflow/values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated: { selfHeal: true, prune: true }
"

# ----- ARGO CD PROJECTS -----
mkh gitops/projects/platform-tools-project.yaml "apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: platform-tools, namespace: argocd }
spec:
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  sourceRepos: [ '*' ]
  clusterResourceWhitelist: [ { group: '*', kind: '*' } ]
"

mkh gitops/projects/workloads-project.yaml "apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: workloads, namespace: argocd }
spec:
  destinations:
    - namespace: apps
      server: https://kubernetes.default.svc
  sourceRepos: [ '*' ]
  clusterResourceWhitelist: [ { group: '*', kind: '*' } ]
"

# ----- BASE KUSTOMIZATION (list all platform apps + policies + ESO) -----
mkh gitops/platform-tools/base/kustomization.yaml "resources:
  - argocd-app-dev.yaml
  - argocd-app-prod.yaml
  - external-secrets-app-dev.yaml
  - external-secrets-app-prod.yaml
  - traefik-app-dev.yaml
  - traefik-app-prod.yaml
  - linkerd-crds-app-dev.yaml
  - linkerd-crds-app-prod.yaml
  - linkerd-app-dev.yaml
  - linkerd-app-prod.yaml
  - kyverno-app-dev.yaml
  - kyverno-app-prod.yaml
  - metrics-server-app-dev.yaml
  - metrics-server-app-prod.yaml
  - kube-prometheus-stack-app-dev.yaml
  - kube-prometheus-stack-app-prod.yaml
  - loki-stack-app-dev.yaml
  - loki-stack-app-prod.yaml
  - kubecost-app-dev.yaml
  - kubecost-app-prod.yaml
  - goldilocks-app-dev.yaml
  - goldilocks-app-prod.yaml
  - redis-cluster-app-dev.yaml
  - redis-cluster-app-prod.yaml
  - reloader-app-dev.yaml
  - reloader-app-prod.yaml
  - kyverno-policies/require-requests-limits.yaml
  - kyverno-policies/disallow-latest-tag.yaml
  - kyverno-policies/verify-cosign-images.yaml
  - ../stores/clustersecretstore-vault.yaml
  - ../stores/externalsecrets/linkerd-issuer.yaml
  - ../stores/externalsecrets/projectflow-env.yaml
"

# ----- KYVERNO POLICIES -----
mkh gitops/platform-tools/base/kyverno-policies/require-requests-limits.yaml "apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-requests-limits }
spec:
  validationFailureAction: Audit
  background: true
  rules:
    - name: require-requests-limits
      match: { resources: { kinds: [Pod] } }
      validate:
        message: \"CPU/memory requests & limits are required.\"
        pattern:
          spec:
            containers:
              - resources:
                  requests: { cpu: \"?*\", memory: \"?*\" }
                  limits:   { cpu: \"?*\", memory: \"?*\" }
"

mkh gitops/platform-tools/base/kyverno-policies/disallow-latest-tag.yaml "apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: disallow-latest-tag }
spec:
  validationFailureAction: Audit
  background: true
  rules:
    - name: no-latest
      match: { resources: { kinds: [Pod] } }
      validate:
        message: \"Avoid :latest image tags.\"
        pattern:
          spec:
            containers:
              - image: \"!*:latest\"
"

mkh gitops/platform-tools/base/kyverno-policies/verify-cosign-images.yaml "apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: verify-cosign-images }
spec:
  validationFailureAction: Audit
  background: true
  rules:
    - name: verify-cosign
      match: { resources: { kinds: [Pod,Deployment,StatefulSet,DaemonSet,Job,CronJob] } }
      verifyImages:
        - image: \"*\"
          keyless: true
"

# ----- ESO: CLUSTERSECRETSTORE + EXTERNALSECRETS -----
mkh gitops/platform-tools/stores/clustersecretstore-vault.yaml "apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata: { name: vault }
spec:
  provider:
    vault:
      server: \"${VAULT_API}\"
      version: v2
      auth:
        kubernetes:
          mountPath: auth/kubernetes
          role: es-reader
"

mkh gitops/platform-tools/stores/externalsecrets/linkerd-issuer.yaml "apiVersion: external-secrets.io/v1beta1
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
"

mkh gitops/platform-tools/stores/externalsecrets/projectflow-env.yaml "apiVersion: external-secrets.io/v1beta1
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
"

# ----- VALUES (DEV/PROD) FOR ALL TOOLS -----
tools=(traefik linkerd kyverno metrics-server kube-prometheus-stack loki-stack kubecost goldilocks redis-cluster reloader external-secrets argocd)
for t in "${tools[@]}"; do
  mk "gitops/platform-tools/values/dev/${t}.yaml"  "# dev values override"
  mk "gitops/platform-tools/values/prod/${t}.yaml" "# prod values override"
done

# sensible defaults
mkh gitops/platform-tools/values/dev/traefik.yaml "logs: { general: { level: DEBUG } }
ports: { websecure: { tls: { enabled: true } } }
ingressRoute: { dashboard: { enabled: true } }
"
mkh gitops/platform-tools/values/prod/traefik.yaml "logs: { general: { level: ERROR } }
ports: { websecure: { tls: { enabled: true } } }
ingressRoute: { dashboard: { enabled: false } }
"
mkh gitops/platform-tools/values/dev/linkerd.yaml "identity: { externalCA: true }
proxy:
  resources:
    requests: { cpu: 20m, memory: 64Mi }
    limits:   { cpu: 100m, memory: 128Mi }
"
mkh gitops/platform-tools/values/prod/linkerd.yaml "identity: { externalCA: true }
proxy:
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 250m, memory: 256Mi }
"
mkh gitops/platform-tools/values/dev/kube-prometheus-stack.yaml "prometheus:
  prometheusSpec:
    scrapeInterval: 60s
"
mkh gitops/platform-tools/values/prod/kube-prometheus-stack.yaml "prometheus:
  prometheusSpec:
    scrapeInterval: 30s
"
mkh gitops/platform-tools/values/dev/loki-stack.yaml "loki: { retentionPeriod: 72h }
promtail: { enabled: true }
"
mkh gitops/platform-tools/values/prod/loki-stack.yaml "loki: { retentionPeriod: 168h }
promtail: { enabled: true }
"
mkh gitops/platform-tools/values/dev/redis-cluster.yaml "cluster: { nodes: 3 }
resources:
  requests: { cpu: 100m, memory: 256Mi }
  limits:   { cpu: 300m, memory: 512Mi }
"
mkh gitops/platform-tools/values/prod/redis-cluster.yaml "cluster: { nodes: 6 }
resources:
  requests: { cpu: 500m, memory: 2Gi }
  limits:   { cpu: 2, memory: 4Gi }
"

# ----- ARGO CD APPLICATIONS (multi-source dev/prod for each tool) -----
emit_app () {
  local name="$1" repo="$2" chart="$3" ver="$4"
  mk "gitops/platform-tools/base/${name}-app-dev.yaml" "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: ${name}-dev, namespace: argocd }
spec:
  project: platform-tools
  sources:
    - repoURL: ${repo}
      chart: ${chart}
      targetRevision: ${ver}
      helm: { valueFiles: [ \$values/gitops/platform-tools/values/dev/${name}.yaml ] }
    - repoURL: ${REPO_URL}
      targetRevision: ${BRANCH}
      ref: values
  destination: { server: https://kubernetes.default.svc, namespace: platform-tools }
  syncPolicy: { automated: { selfHeal: true, prune: true } }
"
  mk "gitops/platform-tools/base/${name}-app-prod.yaml" "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: ${name}-prod, namespace: argocd }
spec:
  project: platform-tools
  sources:
    - repoURL: ${repo}
      chart: ${chart}
      targetRevision: ${ver}
      helm: { valueFiles: [ \$values/gitops/platform-tools/values/prod/${name}.yaml ] }
    - repoURL: ${REPO_URL}
      targetRevision: ${BRANCH}
      ref: values
  destination: { server: https://kubernetes.default.svc, namespace: platform-tools }
  syncPolicy: { automated: { selfHeal: true, prune: true } }
"
}
emit_app argocd            "https://argo.github.io/argo-helm"                  "argo-cd"                  "6.9.3"
emit_app external-secrets  "https://charts.external-secrets.io"                "external-secrets"         "0.10.5"
emit_app traefik           "https://traefik.github.io/charts"                  "traefik"                  "34.3.0"
emit_app linkerd           "https://helm.linkerd.io/stable"                    "linkerd-control-plane"    "1.16.11"
emit_app kyverno           "https://kyverno.github.io/kyverno/"                "kyverno"                  "3.2.6"
emit_app metrics-server    "https://kubernetes-sigs.github.io/metrics-server/" "metrics-server"           "3.12.1"
emit_app kube-prometheus-stack "https://prometheus-community.github.io/helm-charts" "kube-prometheus-stack" "66.3.1"
emit_app loki-stack        "https://grafana.github.io/helm-charts"             "loki-stack"               "2.10.2"
emit_app kubecost          "https://kubecost.github.io/cost-analyzer/"         "cost-analyzer"            "2.3.5"
emit_app goldilocks        "https://charts.fairwinds.com/stable"               "goldilocks"               "8.0.0"
emit_app redis-cluster     "https://charts.bitnami.com/bitnami"                "redis-cluster"            "10.7.8"
emit_app reloader          "https://stakater.github.io/stakater-charts"        "reloader"                 "v1.0.116"

# Linkerd CRDs (separate chart)
for env in dev prod; do
  mk "gitops/platform-tools/base/linkerd-crds-app-${env}.yaml" "apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: linkerd-crds-${env}, namespace: argocd }
spec:
  project: platform-tools
  sources:
    - repoURL: https://helm.linkerd.io/stable
      chart: linkerd-crds
      targetRevision: 1.16.11
    - repoURL: ${REPO_URL}
      targetRevision: ${BRANCH}
      ref: values
  destination: { server: https://kubernetes.default.svc, namespace: linkerd }
  syncPolicy: { automated: { selfHeal: true, prune: true } }
"
done

# ----- PROJECTFLOW CHART + VALUES -----
mk gitops/apps/projectflow/chart/Chart.yaml "apiVersion: v2
name: projectflow
type: application
version: 0.1.0
appVersion: \"0.1.0\"
"
mk gitops/apps/projectflow/chart/values.yaml "image:
  repository: LOCATION-docker.pkg.dev/PROJECT/REPO/projectflow
  tag: \"dev-latest\"
  pullPolicy: IfNotPresent
ingress:
  enabled: true
  className: traefik
  hosts: [ projectflow.example.com ]
envFromSecret: projectflow-env
resources:
  requests: { cpu: 100m, memory: 256Mi }
  limits:   { cpu: 300m, memory: 512Mi }
hpa:
  enabled: false
"
mk gitops/apps/projectflow/values-dev.yaml "image: { tag: \"dev-<shortsha>\" }
ingress: { hosts: [ projectflow.dev.example.com ] }
hpa: { enabled: false }
"
mk gitops/apps/projectflow/values-prod.yaml "image: { tag: \"prod-<shortsha>\" }
ingress: { hosts: [ projectflow.example.com ] }
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 8
  targetCPUUtilizationPercentage: 70
resources:
  requests: { cpu: 300m, memory: 512Mi }
  limits:   { cpu: 1, memory: 1Gi }
"
mk gitops/apps/projectflow/chart/templates/deployment.yaml "apiVersion: apps/v1
kind: Deployment
metadata: { name: projectflow }
spec:
  replicas: 1
  selector: { matchLabels: { app: projectflow } }
  template:
    metadata:
      labels: { app: projectflow }
      annotations: { linkerd.io/inject: enabled }
    spec:
      containers:
        - name: app
          image: \"{{ .Values.image.repository }}:{{ .Values.image.tag }}\"
          imagePullPolicy: \"{{ .Values.image.pullPolicy }}\"
          envFrom: [ { secretRef: { name: {{ .Values.envFromSecret | quote }} } } ]
          ports: [ { containerPort: 8080, name: http } ]
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
"
mk gitops/apps/projectflow/chart/templates/service.yaml "apiVersion: v1
kind: Service
metadata: { name: projectflow }
spec:
  selector: { app: projectflow }
  ports: [ { port: 80, targetPort: 8080, name: http } ]
"
mk gitops/apps/projectflow/chart/templates/ingressroute.yaml "{{- if .Values.ingress.enabled }}
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata: { name: projectflow }
spec:
  entryPoints: [ websecure ]
  routes:
    - match: Host(\`{{ index .Values.ingress.hosts 0 }}\`)
      kind: Rule
      services: [ { name: projectflow, port: 80 } ]
  tls: {}
{{- end }}
"
mk gitops/apps/projectflow/chart/templates/hpa.yaml "{{- if .Values.hpa.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: projectflow }
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: projectflow
  minReplicas: {{ .Values.hpa.minReplicas }}
  maxReplicas: {{ .Values.hpa.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.targetCPUUtilizationPercentage }}
{{- end }}
"

echo "✅ Scaffold complete."
echo "Tip: export REPO_URL=..., VAULT_API=..., BRANCH=... to override defaults."
