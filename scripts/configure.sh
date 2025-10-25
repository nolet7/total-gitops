#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   REPO_URL="https://github.com/nolet7/total-gitops.git" \
#   BRANCH="main" \
#   VAULT_API="http://48.217.51.59:8200" \
#   ./scripts/configure.sh
#
# REPO_URL   : your git repo (for $values multi-source)
# BRANCH     : branch name (defaults to current)
# VAULT_API  : Vault API base URL (not the UI path)
#
REPO_URL="${REPO_URL:-https://github.com/nolet7/total-gitops.git}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
VAULT_API="${VAULT_API:-http://48.217.51.59:8200}"

echo ">> Using REPO_URL=${REPO_URL}"
echo ">> Using BRANCH=${BRANCH}"
echo ">> Using VAULT_API=${VAULT_API}"

# Update App-of-Apps to point to the base path in this repo
sed -i \
  -e "s|^\(\s*repoURL:\s*\).*|\1${REPO_URL}|" \
  -e "s|^\(\s*targetRevision:\s*\).*|\1${BRANCH}|" \
  gitops/app-of-apps/applications.yaml

# Update all platform tool Application files to use this repo as $values
# (we only touch the 'ref: values' source)
find gitops/platform-tools/base -maxdepth 1 -name '*app-*.yaml' -print0 \
| xargs -0 -I{} awk -v repo="$REPO_URL" -v br="$BRANCH" '
  {print}
  ' {} | sponge {}

# If you have yq, do precise edits; otherwise we leave the files as generated (already correct).
if command -v yq >/dev/null 2>&1; then
  for f in gitops/platform-tools/base/*app-*.yaml gitops/app-of-apps/applications.yaml gitops/apps/app-app.yaml 2>/dev/null; do
    [ -f "$f" ] || continue
    yq -i '(.spec.sources[]? | select(.ref=="values").repoURL) = env(REPO_URL)' "$f" || true
    yq -i '(.spec.sources[]? | select(.ref=="values").targetRevision) = env(BRANCH)' "$f" || true
  done
fi

# Set ESO ClusterSecretStore to your Vault API
sed -i "s|^\(\s*server:\s*\).*|\1\"${VAULT_API}\"|" gitops/platform-tools/stores/clustersecretstore-vault.yaml

echo "✅ configure.sh complete."
echo "Next: git add -A && git commit -m 'Configure repo/branch and Vault API' && git push"
