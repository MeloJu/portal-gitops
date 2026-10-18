## Execução da verificação — 2026-10-18

Commit verificado: `origin/develop` em `d342c3cb415f5f1c5e2026586ed93b1b03368d57` (merge do PR #42).
Ambiente: Windows 11 + Git Bash, Docker Desktop (8,28 GB para o Docker), k3d v5.9.0 (K3s v1.35.5), kubectl v1.36.1, kubeseal 0.40.0.

### Resumo

Nenhuma falha de segurança encontrada. Os números batem com o relatório, com duas exceções só de contagem
(SealedSecret com 4 chaves; gitleaks com 80 commits). Há dois pontos menores (permissão do arquivo da chave
no Windows e a liveness do Grafana em máquina com pouca memória).

| Item | Esperado | Medido | Status |
|---|---|---|---|
| Checkov | 1344 / 0 / 39 | 1344 / 0 / 39 | OK |
| Anotações `checkov.io/skip` | 39 | 39 | OK |
| gitleaks | ≥ 79 commits, sem leaks | 80 commits, sem leaks | OK |
| Chaves no SealedSecret da azure | 3 | 4 | Diverge (ver achados) |
| NetworkPolicies local / azure | 7 / 8 | 7 / 8 | OK |
| Camadas do OTLP na azure | 4 | 4 | OK |
| Probes de NetworkPolicy no cluster | — | 16/16 | OK |

### 1. Sem cluster

#### 1.1 Render dos overlays

```bash
mkdir -p rendered
for d in apps/l2/overlays/*/; do kubectl kustomize "$d" > rendered/$(basename $d).yaml; done
```

Overlays: `azure`, `ci`, `local`. Os três renderizam sem erro.

#### 1.2 Checkov

```bash
docker run --rm -v "$PWD/rendered:/rl:ro" \
  bridgecrew/checkov:3.2.500@sha256:5a4407716a99cb170af27f1df9467f23d6f335fe824384b9ad053f58388d81a4 \
  -d /rl --framework kubernetes --compact --quiet
```

```text
Passed checks: 1344, Failed checks: 0, Skipped checks: 39
```

#### 1.3 Skips justificados

```bash
cat rendered/*.yaml | grep -E 'checkov.io/skip' | sed -E 's/^ +//' | sort | uniq -c
```

Total: 39 = 15 × CKV_K8S_40 (UIDs fixos das imagens: 1001 backend, 1001 Playwright, 101 nginx-unprivileged,
70 postgres ×2) + 9 × CKV_K8S_43 (tag `sha-` imutável) + 9 × CKV_K8S_15 (`IfNotPresent` com tag única)
\+ 6 × CKV_K8S_35 (segredos por variável de ambiente).

#### 1.4 gitleaks

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.28.0 \
  git /repo --config /repo/.gitleaks.toml --no-banner --no-color
```

```text
INF 80 commits scanned.
INF no leaks found
```

#### 1.5 Segredos no Git

```bash
grep -rlE '^kind:\s*Secret\s*$' apps bootstrap platform | grep -v '^apps/l2/overlays/ci/'   # sem saída
grep -rlE '^kind:\s*SealedSecret' apps bootstrap platform
```

- `kind: Secret` só em `apps/l2/overlays/ci/secret.yaml`, comentado como valores descartáveis do smoke test.
- SealedSecret só em `apps/l2/overlays/azure/sealed-secret.yaml`, sem `data:` nem `stringData:` em claro.
- 4 chaves cifradas (`Ag...`): `DB_PASSWORD`, `JWT_SECRET`, `POSTGRES_PASSWORD`, `VT_API_KEY`.

#### 1.6 NetworkPolicies e OTLP

| Overlay | NetworkPolicies |
|---|---|
| local | 7: allow-dns, default-deny, frontend, l2-api, postgres, postgres-backup, tools-api |
| ci | 7 |
| azure | 8: as 7 + `allow-acme-solver` |

```bash
kubectl kustomize platform/observability/otlp-azure \
  | grep -E 'path:|pathType:|number:|router.middlewares|average:|burst:|maxRequestBodyBytes:'
```

As 4 camadas estão presentes na azure, iguais às do local:

1. `pathType: Exact` em `/otlp/v1/traces`;
2. rate limit `average: 20`, `burst: 50` (middleware `otlp-limit`);
3. corpo máximo de 1 MiB (`maxRequestBodyBytes: 1048576`, middleware `otlp-body`);
4. backend na porta `4319`.

#### 1.7 Imagens

```bash
grep -hE '^\s+image:' rendered/*.yaml | grep -vE '@sha256:|:[A-Za-z0-9._-]+$'   # sem saída
grep -hE '^\s+image:' rendered/*.yaml | grep -E ':latest$'                     # sem saída
```

- Imagens próprias em `sha-f6a2ea0@sha256:…`; Postgres e postgres-exporter só por digest.
- `f6a2ea0` é o HEAD da `develop` do portal-app. No run 39150297400, o step
  "Trivy barra CRITICAL com correção disponível" passou nos 3 jobs de imagem, e os digests publicados
  são os mesmos do overlay.

### 2. Com cluster (k3d local)

Antes: `./scripts/bootstrap-local.sh` a partir da `develop`; todas as Applications sincronizadas em `d342c3c`.

#### 2.1 Pod Security Admission

```bash
kubectl -n l2 run psa-priv  --image=busybox:1.37 --restart=Never --privileged --dry-run=server
kubectl -n l2 run psa-plain --image=busybox:1.37 --restart=Never --dry-run=server
kubectl label --dry-run=server --overwrite ns l2 pod-security.kubernetes.io/enforce=restricted
```

- Os dois pods de teste são recusados com `violates PodSecurity "restricted:latest"`.
- O relabel em dry-run não gera avisos: todos os pods em execução cumprem o `restricted`.

#### 2.2 Hardening em execução (exec no frontend)

| Verificação | Resultado |
|---|---|
| `id` | `uid=101(nginx)` |
| Escrita em `/` e em `/usr/share/nginx/html` | `Read-only file system` |
| Escrita em `/tmp` | permitida (emptyDir) |
| `CapPrm` / `CapEff` / `CapBnd` | `0000000000000000` |
| `NoNewPrivs` / `Seccomp` | `1` / `2` (filtro ativo) |

Em todos os workloads (frontend, l2-api, tools-api, postgres + exporter): `runAsNonRoot`, UID numérico
(101/1001/1001/70), `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `drop: [ALL]`,
`RuntimeDefault`, requests e limits, `automountServiceAccountToken: false`.

#### 2.3 NetworkPolicies (probes de dentro dos pods)

No frontend com `nc -z -w 4`; no l2-api e no tools-api com `bash /dev/tcp` e `timeout 5`.

| Origem | Destino | Esperado | Medido |
|---|---|---|---|
| frontend | l2-api:8080 | aberto | aberto |
| frontend | tools-api:3001 | aberto | aberto |
| frontend | l2-api:8081 (Actuator) | bloqueado | bloqueado |
| frontend | postgres:5432 | bloqueado | bloqueado |
| frontend | 1.1.1.1:443 | bloqueado | bloqueado |
| frontend | otel-collector:4318 | bloqueado | bloqueado |
| l2-api | postgres:5432 | aberto | aberto |
| l2-api | otel-collector:4318 | aberto | aberto |
| l2-api | otel-collector:4317 | bloqueado | bloqueado |
| l2-api | tools-api:3001 | bloqueado | bloqueado |
| l2-api | 1.1.1.1:443 | bloqueado | bloqueado |
| tools-api | 1.1.1.1:443 | aberto | aberto |
| tools-api | l2-api:8080 | bloqueado | bloqueado |
| tools-api | postgres:5432 | bloqueado | bloqueado |
| tools-api | 169.254.169.254:80 (metadata) | bloqueado | bloqueado |
| tools-api | kubernetes.default.svc:443 | bloqueado | bloqueado |

#### 2.4 Ingress, Actuator e OTLP

```bash
curl -sk --resolve l2.localhost:443:127.0.0.1 -o /dev/null -w '%{http_code}\n' "https://l2.localhost/<path>"
```

| Requisição | Resposta |
|---|---|
| `GET /` (HTTP e HTTPS) | 200, frontend |
| `GET /api/` | 401 |
| `GET /r/nao-existe-s6` | 404 `LINK_NOT_FOUND` |
| `GET /rocket` | 200, frontend (sem a armadilha do `Prefix` `/r`) |
| `GET /actuator/health`, `GET /actuator/prometheus` | `index.html` do frontend (Actuator fora do Ingress) |
| `GET /otlp/v1/traces` | 405 (só POST) |
| `POST /otlp/v1/traces` com `{}` | 200 `{"partialSuccess":{}}` |
| `POST /otlp/v1/traces/x`, `/otlp/v1/metrics`, `/otlp/v1/logs` | 405 (fora do `Exact`) |
| `POST /otlp/v1/traces` com 1,05 MiB | 413 |
| `POST /otlp/v1/traces` com 0,95 MiB | passa do limite de corpo (400 do collector por JSON inválido) |

Rate limit, disparado com um único `curl -Z --parallel-max N -K <lista de URLs>`:

| Rota | Limite | Carga | Resultado |
|---|---|---|---|
| `/otlp/v1/traces` | 20/s, burst 50 | 200 POST em 3,0 s | 107 × 200, 93 × 429 |
| Ingress `l2` | 200/s, burst 500 | 4000 GET (HTTP) em 8,6 s | 2015 × 200, 1985 × 429 |

Nota: por HTTPS, a partir do Windows (Schannel), a carga não passou de ~90 req/s e não disparou o limite
da aplicação. Para testar o limite de 200/s é preciso mais vazão; por HTTP foi suficiente.

#### 2.5 Segredos, banco, digest e backup

| Verificação | Resultado |
|---|---|
| `l2-secrets` no local | criado pelo bootstrap, fora do ArgoCD; chaves `DB_PASSWORD`, `JWT_SECRET`, `POSTGRES_PASSWORD` |
| Role usada pela API | `DB_USER=l2_app`; `l2_app` com `rolsuper=false`; conexões ativas só de `l2_app` |
| `scripts/sealed-secrets-key.sh backup <arquivo>` | exit 0, 1 chave ativa; recusa sobrescrever arquivo existente; arquivo apagado logo depois |
| `kubeseal --fetch-cert` | certificado obtido do controller |
| `kubeseal --validate` do SealedSecret da azure no cluster local | `unable to decrypt sealed secret: l2-secrets` (esperado: cifrado para a chave da azure) |
| Digest em execução (`imageID`) × overlay | os 5 containers batem |
| Postgres | `strategy: Recreate`, PVC `postgres-pvc` RWO `Bound` |
| Backup | `kubectl create job --from=cronjob/postgres-backup` → `backup ok: /backup/l2-20261018T222053Z.dump (192.0K)` |

### Achados

1. **SealedSecret da azure com 4 chaves, não 3.** O `VT_API_KEY` entrou no commit `dabbfd3`. Todas cifradas;
   só a contagem do relatório muda.
2. **Permissão do backup da chave no Windows.** O `sealed-secrets-key.sh` usa `umask 077` e diz
   "permissão 600", mas no Git Bash/NTFS o arquivo sai `-rw-r--r--`. Sugestão: avisar no script ou no doc
   que, no Windows, a proteção depende das ACLs da pasta, e guardar a chave fora de pastas compartilhadas.
3. **Grafana em CrashLoopBackOff com pouca memória.** Com 8 GB para o Docker, o Grafana passa de 160 s para
   subir e a liveness o reinicia (`Shutdown started reason="System signal: terminated"`). É capacidade, não
   segurança, e não afeta o `l2`. Mitigação: mais memória para o WSL ou um `startupProbe`/`initialDelaySeconds`
   maior no values do kube-prometheus-stack.
4. **gitleaks com 80 commits** (o relatório citava 79). Só contagem.

### Pendências

- Testar a **restauração** do dump (`pg_restore` num Postgres temporário). Nesta rodada só foi confirmada a geração do arquivo.
- Testar o rate limit da aplicação por **HTTPS** a partir de uma máquina com mais vazão (ou de dentro do cluster).
