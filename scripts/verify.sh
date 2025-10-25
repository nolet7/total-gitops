#!/usr/bin/env bash
set -euo pipefail
if command -v tree >/dev/null 2>&1; then
  tree -a gitops | sed 's/[^-][^ ]/|/g' || tree gitops
else
  echo "tree not installed. On Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y tree"
  find gitops -print
fi
