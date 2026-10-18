#!/usr/bin/env bash
# Funções compartilhadas pelos scripts do ambiente Azure (bootstrap-azure.sh e azure.sh).
# Não é executável: é lido com `source`.
#
# A porta 6443 da VM NÃO está aberta no firewall (NSG). Toda administração passa por um túnel SSH:
#   localhost:6443  --ssh-->  VM:127.0.0.1:6443 (API do K3s)
#
# Variáveis (todas opcionais):
#   FQDN        nome DNS da VM (padrão: `terraform output -raw fqdn`)
#   SSH_KEY     chave privada (padrão: ~/.ssh/lumi_azure)
#   SSH_USER    usuário da VM (padrão: lumi)
#   LOCAL_PORT  porta local do túnel (padrão: 6443)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/lumi_azure}"
SSH_USER="${SSH_USER:-lumi}"
LOCAL_PORT="${LOCAL_PORT:-6443}"
# O nome `kubeconfig*` já está no .gitignore. Fica fora do ~/.kube/config de propósito:
# assim um `kubectl` esquecido nunca aponta para a nuvem sem você pedir.
KUBECONFIG_AZURE="${KUBECONFIG_AZURE:-${REPO_ROOT}/kubeconfig-azure.yaml}"
TUNNEL_PID=""

azure_prepare() {
  for tool in ssh kubectl; do
    command -v "$tool" >/dev/null || { echo "Falta '$tool' no PATH." >&2; exit 1; }
  done
  if [ -z "${FQDN:-}" ]; then
    command -v terraform >/dev/null || { echo "Defina FQDN=<nome-da-vm> ou instale o terraform." >&2; exit 1; }
    FQDN="$(terraform -chdir="${REPO_ROOT}/terraform" output -raw fqdn)"
  fi
  [ -f "$SSH_KEY" ] || { echo "Chave SSH não encontrada: ${SSH_KEY} (use SSH_KEY=...)" >&2; exit 1; }
}

ssh_vm() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 \
    -o ServerAliveInterval=30 "${SSH_USER}@${FQDN}" "$@"
}

# Abre o túnel da API do Kubernetes em segundo plano e o fecha quando o script termina.
open_api_tunnel() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 -N -L "${LOCAL_PORT}:127.0.0.1:6443" "${SSH_USER}@${FQDN}" &
  TUNNEL_PID=$!
  trap close_api_tunnel EXIT
}

close_api_tunnel() {
  [ -n "$TUNNEL_PID" ] && kill "$TUNNEL_PID" 2>/dev/null || true
}

# Baixa o kubeconfig do K3s (legível só pelo root da VM) e o aponta para o túnel.
fetch_kubeconfig() {
  (umask 077; ssh_vm 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$KUBECONFIG_AZURE")
  # O K3s chama tudo de "default": renomeia, para o contexto não ser confundido com outro.
  sed -i -e 's/: default$/: l2-azure/' \
         -e "s#server: https://127.0.0.1:6443#server: https://127.0.0.1:${LOCAL_PORT}#" "$KUBECONFIG_AZURE"
  export KUBECONFIG="$KUBECONFIG_AZURE"
}

wait_api() {
  for _ in $(seq 1 30); do
    kubectl get --raw /readyz >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "A API do cluster não respondeu pelo túnel (localhost:${LOCAL_PORT})." >&2
  echo "Confira: a VM está ligada? (az vm start -g l2-rg -n l2-vm) O seu IP mudou? (ssh_allowed_cidr)" >&2
  return 1
}
