#!/usr/bin/env bash
# Promove para o Azure as imagens que o bump automático já pôs no overlay `local`.
#
#   ./scripts/promover-imagens-azure.sh           # copia o bloco `images:` do local para o azure
#   ./scripts/promover-imagens-azure.sh --check   # só confere (sai com 1 se estiverem diferentes)
#
# Por quê: o pipeline do portal-app edita só apps/l2/overlays/local (a `develop`, onde o cluster local
# testa a versão). O Azure é a "produção" e segue a `main`: a versão nova chega lá quando um PR de
# release (develop -> main) carrega esta cópia. Assim o Azure nunca roda uma imagem que não passou
# antes pelo local.
#
# Fluxo: bump entra na develop -> validar no local -> rodar este script -> PR -> release para a main.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${ROOT}/apps/l2/overlays/local/kustomization.yaml"
AZURE="${ROOT}/apps/l2/overlays/azure/kustomization.yaml"

# O bloco `images:` vai da linha "images:" até a próxima chave de primeiro nível.
block() { awk '/^images:/{p=1} p&&/^[a-zA-Z]/&&!/^images:/{p=0} p' "$1"; }

[ -n "$(block "$LOCAL")" ] || { echo "Bloco images: não encontrado em ${LOCAL}" >&2; exit 1; }

if [ "$(block "$LOCAL")" = "$(block "$AZURE")" ]; then
  echo "O Azure já usa as mesmas imagens do local."
  exit 0
fi

if [ "${1:-}" = "--check" ]; then
  echo "O Azure usa imagens diferentes das do local:" >&2
  diff <(block "$AZURE") <(block "$LOCAL") >&2 || true
  exit 1
fi

tmp="$(mktemp)"
awk -v newblock="$(block "$LOCAL")" '
  /^images:/ { print newblock; skip=1; next }
  skip && /^[a-zA-Z]/ { skip=0 }
  !skip { print }
' "$AZURE" > "$tmp"
cat "$tmp" > "$AZURE"
rm -f "$tmp"

echo "Imagens do Azure atualizadas a partir do local:"
git -C "$ROOT" diff --stat -- "$AZURE"
