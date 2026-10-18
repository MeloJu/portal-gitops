#!/usr/bin/env bash
# Constrói as três imagens a partir de um checkout local do portal-app e importa no k3d com a
# tag que o overlay local usa (sha-pending). Serve enquanto o pipeline de publicação do
# portal-app não entrega as imagens no GHCR.
#
#   ./scripts/load-local-images.sh /caminho/para/portal-app
set -euo pipefail

APP_DIR="${1:?uso: $0 <caminho-do-portal-app>}"
CLUSTER_NAME="${CLUSTER_NAME:-l2}"
TAG="${TAG:-sha-pending}"
REGISTRY="ghcr.io/meloju"

for svc in backend frontend tools-api; do
  image="${REGISTRY}/portal-app-${svc}:${TAG}"
  echo "==> ${image}"
  docker build -q -t "$image" "${APP_DIR}/${svc}"
  k3d image import -c "$CLUSTER_NAME" "$image"
done

echo "==> Reiniciando os Deployments para pegar as imagens"
kubectl -n l2 rollout restart deployment/l2-api deployment/frontend deployment/tools-api 2>/dev/null || true
