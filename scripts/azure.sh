#!/usr/bin/env bash
# Atalhos para olhar o cluster da VM Azure sem abrir nenhuma porta na internet.
#
#   ./scripts/azure.sh status    # Applications do ArgoCD e pods da aplicação
#   ./scripts/azure.sh kubectl   # túnel aberto: use o kubectl em outro terminal (imprime o export)
#   ./scripts/azure.sh grafana   # Grafana em http://localhost:3000
#   ./scripts/azure.sh argocd    # ArgoCD em https://localhost:8444
#   ./scripts/azure.sh senhas    # senhas do Grafana e do ArgoCD
#   ./scripts/azure.sh ssh       # shell na VM
#
# O Grafana e o ArgoCD não têm Ingress na nuvem: o acesso é um port-forward feito DENTRO da VM e
# trazido para o seu computador por um túnel SSH. Fechou o terminal, fechou o acesso.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib-azure.sh"

cmd="${1:-status}"
azure_prepare

# kubectl dentro da VM (não precisa de túnel de API).
vm_kubectl() { ssh_vm "sudo k3s kubectl $*"; }

# <porta-local> <namespace> <service> <porta-do-service>: o port-forward roda na VM, e o ssh -L
# traz a porta para cá. Fica em primeiro plano até Ctrl+C.
forward() {
  local local_port="$1" ns="$2" svc="$3" svc_port="$4"
  echo "Abrindo ${svc} em localhost:${local_port} (Ctrl+C para fechar)"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -L "${local_port}:127.0.0.1:${local_port}" "${SSH_USER}@${FQDN}" \
    "sudo k3s kubectl -n ${ns} port-forward --address 127.0.0.1 svc/${svc} ${local_port}:${svc_port}"
}

case "$cmd" in
  status)
    echo "== Applications do ArgoCD"
    vm_kubectl -n argocd get applications
    echo; echo "== Pods da aplicação (namespace l2)"
    vm_kubectl -n l2 get pods,hpa
    echo; echo "== Certificado TLS"
    vm_kubectl -n l2 get certificate
    ;;
  kubectl)
    open_api_tunnel
    fetch_kubeconfig
    wait_api
    echo
    echo "Túnel aberto. Em OUTRO terminal (Git Bash), na raiz do repositório:"
    echo "  export KUBECONFIG=\"${KUBECONFIG_AZURE}\""
    echo "  kubectl get nodes"
    echo "Ctrl+C aqui fecha o túnel."
    wait "$TUNNEL_PID"
    ;;
  grafana) forward 3000 observability kps-grafana 80 ;;
  argocd)  forward 8444 argocd argocd-server 443 ;;
  senhas)
    echo -n "Grafana (admin): "
    vm_kubectl -n observability get secret grafana-admin -o "jsonpath='{.data.admin-password}'" | tr -d "'" | base64 -d; echo
    echo -n "ArgoCD  (admin): "
    vm_kubectl -n argocd get secret argocd-initial-admin-secret -o "jsonpath='{.data.password}'" | tr -d "'" | base64 -d; echo
    ;;
  ssh) ssh_vm ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
