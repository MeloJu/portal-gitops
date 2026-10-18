#!/usr/bin/env bash
# Exibe o roteiro de captura; as imagens devem ser capturadas manualmente nas fontes reais.
set -euo pipefail

usage() {
  cat <<'EOF'
uso: ./scripts/capturar.sh [--help]

Mostra a lista de evidências reais a capturar em docs/evidencias/.
Não consulta GitHub ou Kubernetes, não abre serviços, não cria imagens e não altera arquivos.
Consulte docs/evidencias/README.md para os passos, comandos somente de leitura e legendas.
EOF
}

if (( $# > 0 )); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
fi

cat <<'EOF'
Captura assistida do Lumi Links

01  01-argocd-synced.png             ArgoCD: Applications Synced e Healthy
02  02-portal-app-actions.png        Actions: CI real do portal-app concluído
03  03-gitops-pr-validation.png      PR real de bump: verificações concluídas
04  04-grafana-hpa.png               Grafana: carga e réplicas observadas no HPA
05  05-tempo-browser-api-db.png      Tempo: navegador, Traefik, API e span JDBC
06  06-alert-l2picoameacas.png       Prometheus/Grafana: L2PicoDeAmeacas firing

Capture somente quando a tela mostrar o estado descrito. Não salve senhas, tokens ou Secrets.
As evidências dependentes de infraestrutura não são geradas por este script.
Leia docs/evidencias/README.md antes de capturar.
EOF
