#!/usr/bin/env bash
# Smoke test da aplicação num cluster qualquer (o kind efêmero do CI ou o k3d local).
#
#   NAMESPACE=l2 ./tests/smoke.sh
#
# Fala com os Services por port-forward (não depende de Ingress) e prova, em ordem:
#   1. a API está pronta (readiness na 8081) e o Flyway criou o schema;
#   2. cadastro, criação de link e o redirect 302 com os cabeçalhos de privacidade;
#   3. a viagem aparece nas métricas (Actuator na 8081, que NÃO é exposto no Ingress);
#   4. o dado sobrevive à destruição do pod do Postgres (PVC + strategy Recreate);
#   5. o frontend serve o SPA e repassa /tools/ para a tools-api;
#   6. o CronJob de backup gera um dump válido (pg_restore --list dentro do próprio job).
set -euo pipefail

NS="${NAMESPACE:-l2}"
API=18080 MGMT=18081 FE=18082
failures=0
pids=()

pass() { echo "  ok    $1"; }
fail() { echo "  FALHA $1"; failures=$((failures + 1)); }
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

forward() { # forward <svc> <porta-local>:<porta-do-service>
  kubectl -n "$NS" port-forward "svc/$1" "$2" >/dev/null 2>&1 &
  pids+=("$!")
}
wait_http() { # wait_http <url> <segundos>
  for _ in $(seq 1 "$2"); do curl -sf -o /dev/null "$1" && return 0; sleep 1; done
  return 1
}

echo "==> port-forward (namespace ${NS})"
forward l2-api "${API}:8080"
forward l2-api "${MGMT}:8081"
forward frontend "${FE}:8080"
wait_http "http://127.0.0.1:${MGMT}/actuator/health/readiness" 60 || { echo "API não ficou pronta"; exit 1; }

echo "==> 1. API pronta"
ready="$(curl -s "http://127.0.0.1:${MGMT}/actuator/health/readiness")"
[[ "$ready" == *'"UP"'* ]] && pass "readiness UP" || fail "readiness: ${ready}"

echo "==> 2. Fluxo principal"
jar="$(mktemp)"
email="smoke-$(date +%s)-$RANDOM@l2.dev"
code_http="$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -H 'Content-Type: application/json' \
  -d "{\"name\":\"Smoke\",\"email\":\"${email}\",\"password\":\"SenhaForte#2026\"}" \
  "http://127.0.0.1:${API}/api/auth/register")"
[ "$code_http" = 201 ] && pass "cadastro 201" || fail "cadastro: HTTP ${code_http}"

# As imagens novas do portal-app só deixam criar portal com o e-mail verificado. Sem SMTP o e-mail é
# simulado: o link com o token vai para o log da API (LoggingEmailSender), e é de lá que o smoke o lê.
# Uma imagem antiga não manda esse e-mail: o passo é pulado e o resto do teste segue igual.
token=""
for _ in $(seq 1 15); do
  token="$(kubectl -n "$NS" logs deploy/l2-api --tail=400 2>/dev/null \
    | grep -F -A12 "$email" | grep -o 'verificar-email?token=[A-Za-z0-9._~-]*' | tail -1 | cut -d= -f2 || true)"
  [ -n "$token" ] && break
  sleep 1
done
if [ -n "$token" ]; then
  verify_http="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"token\":\"${token}\"}" "http://127.0.0.1:${API}/api/auth/verify-email")"
  [ "$verify_http" = 204 ] && pass "e-mail verificado (token lido do log)" || fail "verificação do e-mail: HTTP ${verify_http}"
else
  echo "  --    sem e-mail de verificação no log (imagem sem esse passo): seguindo"
fi

alias="smoke$RANDOM"
link="$(curl -s -b "$jar" -H 'Content-Type: application/json' \
  -d "{\"targetUrl\":\"https://example.com/smoke\",\"alias\":\"${alias}\"}" "http://127.0.0.1:${API}/api/links")"
[[ "$link" == *"\"code\":\"${alias}\""* ]] && pass "link criado (${alias})" || fail "criar link: ${link}"

headers="$(curl -s -D - -o /dev/null "http://127.0.0.1:${API}/r/${alias}")"
grep -q "^HTTP/1.1 302" <<<"$headers" && pass "GET /r/${alias} -> 302" || fail "redirect: $(head -1 <<<"$headers")"
grep -qi "^location: https://example.com/smoke" <<<"$headers" && pass "Location correto" || fail "Location ausente"
grep -qi "^referrer-policy: no-referrer" <<<"$headers" && pass "Referrer-Policy: no-referrer" || fail "Referrer-Policy ausente"
grep -qi "^cache-control: no-store" <<<"$headers" && pass "Cache-Control: no-store" || fail "Cache-Control ausente"

echo "==> 3. Métricas no Actuator (porta interna)"
travels="$(curl -s "http://127.0.0.1:${MGMT}/actuator/prometheus" | awk '/^l2_travels_total/ {s += $2} END {print s + 0}')"
awk -v t="$travels" 'BEGIN { exit !(t >= 1) }' && pass "l2_travels_total = ${travels}" || fail "l2_travels_total = ${travels}"

echo "==> 4. Persistência: o link sobrevive à destruição do pod do Postgres"
kubectl -n "$NS" delete pod -l app.kubernetes.io/name=postgres --wait=true >/dev/null
kubectl -n "$NS" rollout status deploy/postgres --timeout=180s >/dev/null
found=""
for _ in $(seq 1 30); do
  if curl -s -b "$jar" "http://127.0.0.1:${API}/api/links" | grep -q "\"code\":\"${alias}\""; then found=1; break; fi
  sleep 2 # o pool de conexões da API reconecta sozinho ao Postgres novo
done
[ -n "$found" ] && pass "link ${alias} continua lá" || fail "link sumiu depois de recriar o Postgres"

echo "==> 5. Frontend"
wait_http "http://127.0.0.1:${FE}/healthz" 30 || true
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${FE}/")" = 200 ] && pass "SPA /" || fail "SPA /"
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${FE}/dashboard")" = 200 ] && pass "rota do React Router" || fail "rota do React Router"
tools="$(curl -s "http://127.0.0.1:${FE}/tools/health")"
[[ "$tools" == *'"ok"'* ]] && pass "nginx -> tools-api" || fail "nginx -> tools-api: ${tools}"

echo "==> 6. Backup"
job="smoke-backup-$(date +%s)"
kubectl -n "$NS" create job --from=cronjob/postgres-backup "$job" >/dev/null
if kubectl -n "$NS" wait --for=condition=complete "job/$job" --timeout=180s >/dev/null 2>&1; then
  pass "$(kubectl -n "$NS" logs "job/$job" | grep 'backup ok' | sed 's#/backup/##')"
else
  fail "backup: $(kubectl -n "$NS" logs "job/$job" 2>&1 | tail -2 | tr '
' ' ')"
fi

rm -f "$jar"
echo
if [ "$failures" -gt 0 ]; then echo "${failures} falha(s)"; exit 1; fi
echo "Smoke test OK"
