# srespace-tools – GitOps Platform on GKE (External Vault via ESO)

Helm-only customization via Argo CD **multi-source Applications**:
- Source A: upstream Helm charts
- Source B: this repo values under `gitops/platform-tools/values/dev|prod/`

Secrets live in External Vault and sync into Kubernetes via External Secrets Operator (ESO).

