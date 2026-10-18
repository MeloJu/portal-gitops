#!/usr/bin/env bash
# Sela um Secret para o cluster ATUAL (o do contexto do kubectl) e imprime o SealedSecret no stdout.
# O resultado pode ir para o Git: só o controller daquele cluster consegue abri-lo.
#
#   scripts/seal-secret.sh <nome> <namespace> CHAVE [CHAVE=valor] [CHAVE=@arquivo] ... > sealed-secret.yaml
#
#   CHAVE          lê o valor de forma oculta (prompt): não vai para o histórico do shell
#   CHAVE=valor    valor na linha de comando (aparece no histórico e na lista de processos: evite para segredos reais)
#   CHAVE=@arq     valor vem do arquivo
#
# Exemplo (oracle):
#   kubectl config use-context <contexto-oracle>
#   scripts/seal-secret.sh l2-secrets l2 JWT_SECRET DB_PASSWORD POSTGRES_PASSWORD \
#     > apps/l2/overlays/oracle/sealed-secret.yaml
#
# Atenção: o SealedSecret fica amarrado ao nome e ao namespace (escopo "strict"). Para mudar
# qualquer um dos dois é preciso selar de novo.
set -euo pipefail

if [ "$#" -lt 3 ]; then
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 1
fi

for tool in kubectl kubeseal; do
  command -v "$tool" >/dev/null || { echo "Falta '$tool' no PATH." >&2; exit 1; }
done

NAME="$1"; NAMESPACE="$2"; shift 2
args=()
for item in "$@"; do
  case "$item" in
    *=@*) args+=("--from-file=${item%%=@*}=${item#*=@}") ;;
    *=*)  args+=("--from-literal=$item") ;;
    *)
      read -r -s -p "Valor de ${item}: " value </dev/tty; echo >&2
      args+=("--from-literal=${item}=${value}")
      ;;
  esac
done

# --dry-run: o Secret em claro nunca é criado no cluster nem gravado em disco.
kubectl create secret generic "$NAME" --namespace "$NAMESPACE" "${args[@]}" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
      --format yaml
