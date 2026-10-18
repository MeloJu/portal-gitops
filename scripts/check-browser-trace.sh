#!/usr/bin/env bash
# Prova de ponta a ponta do trace "navegador -> Traefik -> l2-api -> Postgres" (tasks O8/X4).
#
#   ./scripts/check-browser-trace.sh
#
# Abre o app num Chromium headless de verdade (imagem do Playwright, na rede do k3d), cadastra um usuário,
# espera 2 s como uma pessoa e abre o dashboard. As chamadas saem pelo fetch instrumentado do próprio app.
# Falha se alguma chamada sair sem traceparent, ou se o trace da primeira (página que a pessoa deixou) ou da
# última chamada não tiver os três serviços.
# Pré-requisitos: cluster local de pé (bootstrap-local.sh), docker e kubectl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-l2}"
docker() { MSYS_NO_PATHCONV=1 command docker "$@"; }

# O Chromium resolve *.localhost sempre para o próprio loopback; o teste mapeia l2.localhost para o
# balanceador do k3d, alcançado direto pela rede do cluster.
LB="$(docker inspect "k3d-${CLUSTER_NAME}-serverlb" --format "{{(index .NetworkSettings.Networks \"k3d-${CLUSTER_NAME}\").IPAddress}}")"
dir="${REPO_ROOT}/tests/browser"
command -v cygpath >/dev/null && dir="$(cygpath -w "$dir")"

echo "==> Chromium headless contra http://l2.localhost (balanceador ${LB})"
out="$(docker run --rm --network "k3d-${CLUSTER_NAME}" -e HOSTIP="$LB" -v "${dir}:/work" -w /work \
  mcr.microsoft.com/playwright:v1.49.1-noble \
  sh -c '[ -d node_modules/playwright ] || npm i -s --no-save playwright@1.49.1 >/dev/null 2>&1; timeout 120 node trace.mjs' | tail -1)"

total="$(echo "$out" | grep -o '"path"' | wc -l)"
com="$(echo "$out" | grep -o '"tp":"00-' | wc -l)"
echo "    chamadas à API com traceparent: ${com} de ${total}"
if [ "$com" -eq 0 ] || [ "$com" -ne "$total" ]; then
  echo "FALHOU: nem toda chamada levou traceparent" >&2
  exit 1
fi
first="$(echo "$out" | grep -o '"tp":"00-[0-9a-f]*' | head -1 | cut -d- -f2)"
last="$(echo "$out" | grep -o '"tp":"00-[0-9a-f]*' | tail -1 | cut -d- -f2)"

kubectl -n observability port-forward svc/tempo 13200:3200 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 12

# A primeira chamada é da página inicial, que a pessoa deixa: prova que os spans não se perdem na troca de
# página. A última é da página onde ela fica.
for tid in "$first" "$last"; do
  services="$(curl -s "http://127.0.0.1:13200/api/traces/${tid}" \
    | grep -o '"key":"service.name","value":{"stringValue":"[^"]*"' \
    | sed 's/.*"stringValue":"//; s/"$//' | sort -u | tr '\n' ' ')"
  echo "    trace ${tid}: ${services}"
  for s in l2-frontend traefik l2-api; do
    case " $services " in
      *" $s "*) ;;
      *) echo "FALHOU: '$s' não está no trace ${tid}" >&2; exit 1 ;;
    esac
  done
done
echo "OK: o trace começa no navegador e atravessa Traefik e l2-api, inclusive na página que a pessoa deixou."
