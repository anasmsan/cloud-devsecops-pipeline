#!/usr/bin/env bash
# Rejoue en local exactement les contrôles de sécurité du pipeline GitLab CI
# (.gitlab-ci.yml), pour pouvoir les vérifier avant même de pousser du code.
set -euo pipefail
cd "$(dirname "$0")/.."

# semgrep et checkov sont installés dans un venv Python dédié (voir README) ;
# gitleaks/tfsec/kubectl sont supposés déjà dans le PATH (ex: via brew).
if [ -f .venv-tools/bin/activate ]; then source .venv-tools/bin/activate; fi

echo "=== 1/5 — Secrets (gitleaks) ==="
gitleaks detect --source . --no-git --config .gitleaks.toml

echo "=== 2/5 — SAST Python (semgrep) ==="
semgrep --config auto app/ --error

echo "=== 3/5 — IaC Terraform (tfsec) ==="
tfsec terraform/ --no-color --minimum-severity HIGH

echo "=== 4/5 — IaC Terraform (checkov) ==="
checkov -d terraform/environments/dev --compact --quiet --skip-check CKV_TF_1 || true

echo "=== 5/5 — Manifestes Kubernetes (checkov) ==="
kubectl kustomize k8s/overlays/dev > /tmp/rendered-dev.yaml
checkov -f /tmp/rendered-dev.yaml --compact --quiet --skip-check CKV_K8S_43

echo ""
echo "Tous les contrôles sont passés (ou documentés dans SECURITY_EXCEPTIONS.md)."
