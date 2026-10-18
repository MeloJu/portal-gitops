#!/usr/bin/env bash
# Gera a carga das cenas da demo pela API pública (Ingress), sem tocar no cluster.
#
#   ./scripts/demo-load.sh setup                 # cria um usuário e alguns links
#   ./scripts/demo-load.sh cliques               # GET /r/{code} em loop -> HPA da l2-api escala
#   ./scripts/demo-load.sh ameaca                # rajadas de login -> RATE_LIMIT no painel de Ameaças
#   ./scripts/demo-load.sh --help
#
# Pré-requisitos: bash e curl (funciona no Git Bash do Windows e no Linux).
set -euo pipefail

usage() {
  cat <<'EOF'
uso: demo-load.sh <setup|cliques|ameaca> [opções]

Modos
  setup     Cadastra um usuário (POST /api/auth/register) e cria --links links
            (POST /api/links). Imprime os códigos e as credenciais.
  cliques   Dispara GET /r/{code} em loop, com --concurrency workers, por --duration
            segundos. Sem --codes, roda o setup antes. Acompanhe:
              kubectl -n l2 get hpa l2-api -w
  ameaca    Rajadas de POST /api/auth/login (senha errada) acima do limite de login
            (60/min por IP). Uma rajada a cada 61 s enquanto durar --duration.

Opções (cada uma também aceita a variável de ambiente indicada)
  --url URL            BASE_URL      Endereço do Ingress (padrão: http://l2.localhost)
  --duration SEG       DURATION      Duração (padrão: 180 em cliques, 150 em ameaca)
  --concurrency N      CONCURRENCY   Workers em paralelo (padrão: 8 em cliques, 20 em ameaca)
  --burst N            BURST         Logins por rajada no modo ameaca (padrão: 240)
  --links N            LINKS         Links criados no setup (padrão: 5)
  --codes A,B,C        CODES         Códigos já existentes (pula o setup no modo cliques)
  --user-agent UA      USER_AGENT    User-Agent (padrão: um Chrome de desktop; ver abaixo)
  -k, --insecure       INSECURE=1    Aceita o certificado self-signed (URL https:// local)
  -h, --help                         Esta ajuda

Credenciais do setup: DEMO_EMAIL e DEMO_PASSWORD (sem aspas nem barra invertida). Sem elas,
o script gera um e-mail único e uma senha aleatória e mostra os dois no final.

Por que o User-Agent de navegador: a API classifica como bot quem se identifica como curl,
e o painel "Cliques (viagens) por segundo" separa bot de humano. Para a carga aparecer como
cliques humanos, o padrão é um Chrome. Use --user-agent curl/8 para ver a curva de bots.

Como o rate limit da API funciona (portal-app, pacote dev.l2.api.ratelimit)
  - Balde por rota (LOGIN, REGISTER, TRAVEL) + IP do cliente, EM MEMÓRIA, POR POD:
    capacidade 60 e recarga de 60 por minuto (1 token/s). Com N pods o limite efetivo é N x 60.
  - Requisições sequenciais lentas não esvaziam o balde: a rajada precisa ser concorrente.
    Por isso o padrão é 240 logins com 20 workers (passa de 60 mesmo com 3 réplicas).
  - O bloqueio responde 429, mas só a PRIMEIRA recusa de cada janela (1 min) por rota+IP+pod
    vira evento: incrementa l2_threats_blocked_total{reason="RATE_LIMIT"} e grava o BlockedEvent.
    Por isso o modo ameaca repete a rajada a cada 61 s: cada rajada soma 1 por pod atingido.
  - O overlay local sobe APP_RATELIMIT_TRAVEL_CAPACITY para 6000/min (100/s por pod), então o
    loop de cliques gera CPU antes de bater no limite. Se passar disso, os 429 de TRAVEL também
    viram RATE_LIMIT no painel de Ameaças: rode as duas cenas em momentos separados.
EOF
}

die() { echo "erro: $*" >&2; exit 1; }

is_int() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 > 0 )); }

MODE=""
while (( $# > 0 )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --url) BASE_URL="${2:?--url pede um valor}"; shift 2 ;;
    --duration) DURATION="${2:?--duration pede um valor}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:?--concurrency pede um valor}"; shift 2 ;;
    --burst) BURST="${2:?--burst pede um valor}"; shift 2 ;;
    --links) LINKS="${2:?--links pede um valor}"; shift 2 ;;
    --codes) CODES="${2:?--codes pede um valor}"; shift 2 ;;
    --user-agent) USER_AGENT="${2:?--user-agent pede um valor}"; shift 2 ;;
    -k|--insecure) INSECURE=1; shift ;;
    setup|cliques|ameaca)
      [[ -z "$MODE" ]] || die "um modo só por vez (já escolhido: $MODE)"
      MODE="$1"; shift ;;
    *) die "argumento desconhecido: $1 (veja --help)" ;;
  esac
done
[[ -n "$MODE" ]] || { usage >&2; exit 2; }

BASE_URL="${BASE_URL:-http://l2.localhost}"
BASE_URL="${BASE_URL%/}"
LINKS="${LINKS:-5}"
BURST="${BURST:-240}"
CODES="${CODES:-}"
INSECURE="${INSECURE:-0}"
USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36}"
case "$MODE" in
  ameaca) DURATION="${DURATION:-150}"; CONCURRENCY="${CONCURRENCY:-20}" ;;
  *)      DURATION="${DURATION:-180}"; CONCURRENCY="${CONCURRENCY:-8}" ;;
esac
for var in DURATION CONCURRENCY BURST LINKS; do
  is_int "${!var}" || die "$var deve ser um inteiro positivo (recebido: '${!var}')"
done
[[ "$BASE_URL" =~ ^https?:// ]] || die "BASE_URL deve começar com http:// ou https:// (recebido: '$BASE_URL')"
command -v curl >/dev/null || die "falta 'curl' no PATH"

CURL=(curl -s --connect-timeout 5 --max-time 15 -A "$USER_AGENT")
[[ "$INSECURE" == "1" ]] && CURL+=(-k)

WORK_DIR="$(mktemp -d)"
cleanup() {
  local pids
  pids="$(jobs -p)"
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

now() { date +%s; }

# Chamada JSON com o cookie de sessão (lumi_session, HttpOnly) num cookie jar.
# Imprime o status; o corpo fica em $WORK_DIR/resp.
api() {
  local method="$1" path="$2" body="$3"
  "${CURL[@]}" -X "$method" -H 'Content-Type: application/json' --data "$body" \
    -b "$WORK_DIR/cookies" -c "$WORK_DIR/cookies" \
    -o "$WORK_DIR/resp" -w '%{http_code}' "${BASE_URL}${path}" || echo "000"
}

setup() {
  local email password name="Demo Load" status code i
  email="${DEMO_EMAIL:-demo-load-$(now)-${RANDOM}@example.com}"
  password="${DEMO_PASSWORD:-$(head -c 18 /dev/urandom | base64 | tr -d '=+/\n')}"
  : >"$WORK_DIR/cookies"

  echo "==> Cadastro de ${email}"
  status="$(api POST /api/auth/register \
    "{\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"${password}\"}")"
  case "$status" in
    201) ;;
    409)
      echo "    e-mail já cadastrado, entrando com login"
      status="$(api POST /api/auth/login "{\"email\":\"${email}\",\"password\":\"${password}\"}")"
      [[ "$status" == "200" ]] || die "login falhou (HTTP $status): $(cat "$WORK_DIR/resp" 2>/dev/null)"
      ;;
    000) die "sem resposta de ${BASE_URL} (o cluster e o Ingress estão no ar?)" ;;
    *) die "cadastro falhou (HTTP $status): $(cat "$WORK_DIR/resp" 2>/dev/null)" ;;
  esac

  echo "==> Criando ${LINKS} links"
  local codes=()
  for (( i = 1; i <= LINKS; i++ )); do
    status="$(api POST /api/links \
      "{\"targetUrl\":\"https://example.com/lumi-demo/${i}\",\"title\":\"Demo load ${i}\"}")"
    [[ "$status" == "201" ]] || die "criação do link $i falhou (HTTP $status): $(cat "$WORK_DIR/resp" 2>/dev/null)"
    code="$(grep -o '"code" *: *"[^"]*"' "$WORK_DIR/resp" | head -n 1 | cut -d'"' -f4 || true)"
    [[ -n "$code" ]] || die "resposta sem 'code': $(cat "$WORK_DIR/resp")"
    codes+=("$code")
    echo "    ${BASE_URL}/r/${code}"
  done
  CODES="$(IFS=,; echo "${codes[*]}")"

  echo
  echo "Usuário: ${email}"
  echo "Senha:   ${password}"
  echo "CODES=${CODES}"
}

# Um worker = um processo curl com várias URLs: reaproveita a conexão (keep-alive), o que dá
# muito mais requisições por segundo que um curl por requisição. Grava um status por linha.
run_curl_batch() {
  local out="$1"; shift
  "${CURL[@]}" -w '%{http_code}\n' "$@" >>"$out" 2>/dev/null || sleep 1
}

summary() {
  local title="$1" total
  total="$(cat "$WORK_DIR"/w-*.log 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "==> ${title}: ${total} requisições, por status HTTP:"
  cat "$WORK_DIR"/w-*.log 2>/dev/null | sort | uniq -c | sort -rn | sed 's/^/    /'
}

clicks_worker() {
  local id="$1" deadline="$2" args=() code n
  local -a list
  IFS=, read -r -a list <<<"$CODES"
  # Cada worker começa num link diferente; ~100 requisições por processo curl.
  for (( n = 0; n < 100; n++ )); do
    code="${list[$(( (id + n) % ${#list[@]} ))]}"
    args+=(-o /dev/null "${BASE_URL}/r/${code}")
  done
  while (( $(now) < deadline )); do
    run_curl_batch "$WORK_DIR/w-${id}.log" "${args[@]}"
  done
}

clicks() {
  [[ -n "$CODES" ]] || setup
  [[ "$CODES" =~ ^[A-Za-z0-9,-]+$ ]] || die "CODES inválido: '$CODES' (códigos separados por vírgula)"
  local deadline id
  deadline=$(( $(now) + DURATION ))
  echo
  echo "==> Cliques: ${CONCURRENCY} workers por ${DURATION}s em ${BASE_URL}/r/{${CODES}}"
  echo "    Acompanhe: kubectl -n l2 get hpa l2-api -w   (o scale-up espera 60 s de CPU alta)"
  for (( id = 1; id <= CONCURRENCY; id++ )); do
    clicks_worker "$id" "$deadline" &
  done
  wait
  summary "Cliques"
  echo "    302 = viagem registrada; 429 = passou do limite de TRAVEL (suba APP_RATELIMIT_TRAVEL_CAPACITY ou baixe --concurrency)"
}

threat_burst() {
  local round="$1" per id n email
  per=$(( (BURST + CONCURRENCY - 1) / CONCURRENCY ))
  email="ataque-${RANDOM}@example.com"
  for (( id = 1; id <= CONCURRENCY; id++ )); do
    (
      args=()
      for (( n = 0; n < per; n++ )); do args+=(-o /dev/null "${BASE_URL}/api/auth/login"); done
      run_curl_batch "$WORK_DIR/w-r${round}-${id}.log" -H 'Content-Type: application/json' \
        --data "{\"email\":\"${email}\",\"password\":\"senha-errada-${RANDOM}\"}" "${args[@]}"
    ) &
  done
  wait
  local blocked
  blocked="$(cat "$WORK_DIR"/w-r"${round}"-*.log 2>/dev/null | grep -c '^429$' || true)"
  echo "    rajada ${round}: $(( per * CONCURRENCY )) logins, ${blocked} bloqueados (429)"
}

threat() {
  local start round=0 next
  start="$(now)"
  echo "==> Ameaça: rajada de ${BURST} logins (${CONCURRENCY} em paralelo) a cada 61 s por ${DURATION}s"
  echo "    Cada rajada gera 1 evento RATE_LIMIT por pod atingido (janela de 1 min por rota+IP)."
  while :; do
    round=$(( round + 1 ))
    threat_burst "$round"
    next=$(( start + round * 61 ))
    (( next < start + DURATION )) || break
    while (( $(now) < next )); do sleep 1; done
  done
  summary "Ameaça"
  echo "    401 = senha errada (passou pelo limite); 429 = bloqueado pelo rate limit"
  echo "    Grafana: painel 'Ameaças bloqueadas por motivo' (reason=RATE_LIMIT)"
}

case "$MODE" in
  setup) setup ;;
  cliques) clicks ;;
  ameaca) threat ;;
esac
