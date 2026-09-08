#!/usr/bin/env bash
# Construit l'image, la pousse sur ECR, et déploie sur le cluster EKS via
# Kustomize. C'est exactement la séquence que le job `deploy:dev` du pipeline
# GitLab CI automatiserait — jouée ici manuellement pour la démonstration
# en direct, sans dépendre d'un vrai pipeline GitLab hébergé.
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${1:-dev}"
TAG="manual-$(date +%Y%m%d%H%M%S)"

echo "==> Récupération des informations d'infrastructure (Terraform outputs)"
cd terraform/environments/dev
CLUSTER_NAME=$(terraform output -raw cluster_name)
ECR_REPO=$(terraform output -raw ecr_repository_url)
cd - >/dev/null

echo "    Cluster : $CLUSTER_NAME"
echo "    ECR     : $ECR_REPO"

echo "==> Connexion à ECR"
aws ecr get-login-password --region eu-west-3 | docker login --username AWS --password-stdin "${ECR_REPO%%/*}"

echo "==> Build et push de l'image ($TAG)"
# --platform linux/amd64 explicite : les nœuds EKS sont en x86_64, alors qu'un
# Mac Apple Silicon construit des images arm64 par défaut. Sans ce flag, le
# pod démarre sur le cluster avec l'erreur "exec format error" (mismatch
# d'architecture CPU) — une image qui tourne très bien en local sur ce Mac
# planterait silencieusement une fois déployée sur un vrai nœud EKS standard.
# En CI (runners GitLab généralement en amd64), ce flag est inoffensif.
docker buildx build --platform linux/amd64 \
  -t "$ECR_REPO:$TAG" --build-arg APP_VERSION="$TAG" \
  --push app/

echo "==> Connexion kubectl au cluster"
aws eks update-kubeconfig --region eu-west-3 --name "$CLUSTER_NAME"

echo "==> Déploiement sur l'overlay '$ENV'"
cd "k8s/overlays/$ENV"
kustomize edit set image "PLACEHOLDER_IMAGE=$ECR_REPO:$TAG"
kubectl apply -k .
cd - >/dev/null

echo "==> Attente du rollout"
kubectl rollout status deployment/demo-service -n devsecops-demo --timeout=180s

echo "==> Terminé. Image déployée : $ECR_REPO:$TAG"
