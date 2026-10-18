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
  MSYS_NO_PATHCONV=1 docker run --rm -v "$repo_mount:/r:ro" mikefarah/yq:4.48.1@sha256:75b3a60dce1fa4641b0f02bdb4465eddc5da95e62028118a292239ca8e3921e5 '.spec' /r/apps/l2/base/alerts.yaml > "$dir/l2-rules.yaml"
fi
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint promtool -v "$mount:/t" -w /t prom/prometheus:v3.6.0@sha256:76947e7ef22f8a698fc638f706685909be425dbe09bd7a2cd7aca849f79b5f64 \
  test rules l2-rules.test.yaml
