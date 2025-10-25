#!/usr/bin/env bash
set -euo pipefail

# Optional: set a specific Argo CD version (manifests) or use 'stable'
ARGO_URL="${ARGO_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
NS="${NS:-argocd}"

echo ">> Creating namespace: ${NS}"
kubectl create namespace "${NS}" 2>/dev/null || true

echo ">> Installing Argo CD from ${ARGO_URL}"
kubectl apply -n "${NS}" -f "${ARGO_URL}"

echo ">> Waiting for Argo CD deployments to become ready..."
kubectl rollout status -n "${NS}" deploy/argocd-repo-server --timeout=5m
kubectl rollout status -n "${NS}" deploy/argocd-application-controller --timeout=5m
kubectl rollout status -n "${NS}" deploy/argocd-server --timeout=5m
kubectl rollout status -n "${NS}" deploy/argocd-dex-server --timeout=5m

echo ">> Applying AppProjects"
kubectl apply -f gitops/projects/platform-tools-project.yaml
kubectl apply -f gitops/projects/workloads-project.yaml

echo ">> Registering App-of-Apps (platform + projectflow)"
kubectl apply -f gitops/app-of-apps/

echo "✅ bootstrap-argocd.sh complete."
echo "Tip: to get initial admin password:"
echo "  kubectl -n ${NS} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
