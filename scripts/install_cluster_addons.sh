#!/usr/bin/env bash
# Installe metrics-server sur le cluster : nécessaire pour que le
# HorizontalPodAutoscaler (k8s/base/hpa.yaml) puisse lire l'utilisation CPU
# réelle des pods. Ce n'est pas un composant applicatif : c'est un "add-on"
# d'infrastructure du cluster, installé une seule fois, séparément du
# déploiement de l'application elle-même.
set -euo pipefail

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update metrics-server

helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set args={--kubelet-insecure-tls} \
  --wait --timeout 3m

echo "metrics-server installé. Vérification (peut prendre 1-2 min avant d'afficher des métriques) :"
kubectl top nodes || echo "(pas encore prêt, réessayer dans une minute avec: kubectl top nodes)"
