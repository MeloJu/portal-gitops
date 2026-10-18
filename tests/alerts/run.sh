#!/usr/bin/env bash
# Extrai as regras do PrometheusRule e roda `promtool test rules` (mesma imagem e versão no CI).
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$dir/../.." && pwd)"
mount="$dir"; repo_mount="$repo"
if command -v cygpath >/dev/null; then mount="$(cygpath -w "$dir")"; repo_mount="$(cygpath -w "$repo")"; fi
if command -v yq >/dev/null; then
  yq '.spec' "$repo/apps/l2/base/alerts.yaml" > "$dir/l2-rules.yaml"
else # sem yq local (o runner do CI tem): usa a imagem oficial
  MSYS_NO_PATHCONV=1 docker run --rm -v "$repo_mount:/r:ro" mikefarah/yq:4.48.1 '.spec' /r/apps/l2/base/alerts.yaml > "$dir/l2-rules.yaml"
fi
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint promtool -v "$mount:/t" -w /t prom/prometheus:v3.6.0 \
  test rules l2-rules.test.yaml
