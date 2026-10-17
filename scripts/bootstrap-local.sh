#!/usr/bin/env bash
# Sobe o ambiente local inteiro: cluster k3d, ArgoCD, Secret da aplicação e app-of-apps.
#
#   ./scripts/bootstrap-local.sh
#
# Idempotente: reaproveita o cluster e não troca o Secret se ele já existe.
# Pré-requisitos: docker, k3d, kubectl.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-l2}"
NAMESPACE="l2"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tool in docker k3d kubectl; do
  command -v "$tool" >/dev/null || { echo "Falta '$tool' no PATH." >&2; exit 1; }
done

if k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "==> Cluster '${CLUSTER_NAME}' já existe, reaproveitando"
  k3d cluster start "$CLUSTER_NAME" >/dev/null 2>&1 || true
else
  echo "==> Criando cluster k3d '${CLUSTER_NAME}' (Traefik e metrics-server já vêm no K3s)"
  # 80/443 no host -> Traefik. O Ingress responde em http://l2.localhost.
  k3d cluster create "$CLUSTER_NAME" \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --wait
fi
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null

# No Docker Desktop (Windows/macOS) o k3d grava o kubeconfig com host.docker.internal, que pode
# resolver para o IP da LAN e ficar inacessível (firewall). A porta da API é publicada no
# loopback, e o certificado do K3s já inclui 127.0.0.1, então apontamos para lá.
api_server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
case "$api_server" in
  *host.docker.internal*)
    kubectl config set-cluster "k3d-${CLUSTER_NAME}" \
      --server="https://127.0.0.1:${api_server##*:}" >/dev/null
    ;;
esac

echo "==> Instalando o ArgoCD (versão fixada em bootstrap/argocd)"
kubectl apply --server-side --force-conflicts -k "${REPO_ROOT}/bootstrap/argocd"
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Secret da aplicação (fora do Git)"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if kubectl -n "$NAMESPACE" get secret l2-secrets >/dev/null 2>&1; then
  # Não rotacionar: a senha do banco só é aplicada quando o volume do Postgres está vazio.
  echo "    l2-secrets já existe, mantendo"
else
  rand() { head -c "$1" /dev/urandom | base64 | tr -d '=+/\n'; }
  kubectl -n "$NAMESPACE" create secret generic l2-secrets \
    --from-literal=POSTGRES_PASSWORD="$(rand 24)" \
    --from-literal=DB_PASSWORD="$(rand 24)" \
    --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
fi

echo "==> App-of-apps"
kubectl apply -f "${REPO_ROOT}/bootstrap/root-local.yaml"

cat <<MSG

Pronto. O ArgoCD vai sincronizar a branch 'develop' sozinho.

  Acompanhar:   kubectl -n argocd get applications
  UI do Argo:   kubectl -n argocd port-forward svc/argocd-server 8443:443
                senha: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  A aplicação:  http://l2.localhost

As imagens ainda são o placeholder 'sha-pending' até o pipeline do portal-app publicar.
Para testar já: ./scripts/load-local-images.sh <caminho-do-portal-app>
MSG
