#!/usr/bin/env bash
# Backup e restauração da chave privada do Sealed Secrets do cluster atual.
#
#   scripts/sealed-secrets-key.sh backup  <arquivo>
#   scripts/sealed-secrets-key.sh restore <arquivo>
#
# Sem essa chave, recriar o cluster (ou o controller) torna TODOS os SealedSecret do Git
# ilegíveis. O arquivo gerado é a chave PRIVADA: guarde num cofre/gerenciador de senhas e NUNCA
# no Git (o .gitignore já bloqueia os nomes usuais).
set -euo pipefail

action="${1:-}"; file="${2:-}"
[ -n "$action" ] && [ -n "$file" ] || { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }

case "$action" in
  backup)
    [ ! -e "$file" ] || { echo "'$file' já existe; não vou sobrescrever." >&2; exit 1; }
    umask 077
    kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > "$file"
    echo "Chave salva em $file (permissão 600). Guarde fora do Git."
    ;;
  restore)
    kubectl apply -f "$file"
    # O controller só carrega as chaves ao iniciar.
    kubectl -n kube-system delete pod -l app.kubernetes.io/name=sealed-secrets
    echo "Chave restaurada; o controller está reiniciando."
    ;;
  *) echo "ação desconhecida: $action" >&2; exit 1 ;;
esac
