#!/usr/bin/env bash
# Instala o ArgoCD na VM Azure (K3s criado pelo Terraform) e aplica o app-of-apps.
#
#   ./scripts/bootstrap-azure.sh
#
# Idempotente. Pré-requisitos: terraform apply feito, ssh e kubectl. O kubectl fala com o cluster por
# um túnel SSH (a porta 6443 não é exposta), usando um kubeconfig próprio: o seu ~/.kube/config
# não é tocado, então nada aqui pode cair por engano no cluster local.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-azure.sh"

azure_prepare
echo "==> VM: ${FQDN}"

echo "==> Esperando o K3s terminar de instalar (cloud-init)"
ssh_vm 'sudo cloud-init status --wait >/dev/null; sudo k3s kubectl get nodes' >/dev/null

echo "==> Túnel SSH para a API do Kubernetes (localhost:${LOCAL_PORT})"
open_api_tunnel
fetch_kubeconfig
wait_api
kubectl get nodes

echo "==> Instalando o ArgoCD (versão fixada em bootstrap/argocd)"
kubectl apply --server-side --force-conflicts -k "${REPO_ROOT}/bootstrap/argocd"
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Senha do Grafana (fora do Git)"
kubectl get namespace observability >/dev/null 2>&1 || kubectl create namespace observability >/dev/null
if kubectl -n observability get secret grafana-admin >/dev/null 2>&1; then
  echo "    grafana-admin já existe, mantendo"
else
  kubectl -n observability create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(head -c 18 /dev/urandom | base64 | tr -d '=+/\n')"
fi

echo "==> App-of-apps"
kubectl apply -f "${REPO_ROOT}/bootstrap/root-azure.yaml"

cat <<MSG

Pronto. O ArgoCD vai sincronizar a branch 'develop' sozinho (a plataforma sobe primeiro).

  O Secret da aplicação (l2-secrets) NÃO é criado aqui: vem de um SealedSecret commitado em
  apps/l2/overlays/azure (docs/azure.md, passo "Segredos"). Até lá a API/Postgres ficam em
  CreateContainerConfigError, e é esperado.

  Para olhar o cluster (outro terminal):  ./scripts/azure.sh status
  Grafana:                                ./scripts/azure.sh grafana
  ArgoCD:                                 ./scripts/azure.sh argocd
MSG
