# portal-gitops — contexto para o Claude

GitOps do **Lumi Links** (hackathon *Portal dos Links*). Este repositório é a **fonte da verdade do
cluster**: o ArgoCD sincroniza o que está aqui. O código da aplicação vive em
[`MeloJu/portal-app`](https://github.com/MeloJu/portal-app) (branch `develop`).

Leia antes de mexer: [`TASKS.md`](TASKS.md) (plano, decisões, riscos) e [`README.md`](README.md).

## Stack
Kubernetes (k3d/K3s local, K3s na Oracle depois) · Kustomize · ArgoCD (app-of-apps) · GitHub Actions ·
OpenTelemetry → Tempo · Prometheus · Grafana. Namespace da app: `l2`.

## Estrutura
- `apps/l2/base/` manifests · `apps/l2/overlays/{local,ci,oracle}` por ambiente (o bump de imagem edita só o bloco `images:`)
- `bootstrap/` ArgoCD + app-of-apps · `scripts/` · `.github/workflows/`

## Regras que não se negociam
1. **Mudança só pelo Git.** `kubectl patch/edit` à mão é revertido pelo ArgoCD (`selfHeal`). Para testar, commite numa branch.
2. **Secret nunca em claro.** `kind: Secret` só no overlay `ci` (valores descartáveis). Local: criado por `scripts/bootstrap-local.sh`. Oracle: SealedSecret.
3. **Paths do Ingress terminam em `/`** (`/r/`, `/api/`). O Traefik trata `Prefix` como prefixo de texto: `/r` capturaria o link curto `rocket`.
4. **Actuator (8081) nunca no Ingress.** Probes e Prometheus entram por dentro do cluster.
5. **Postgres usa `strategy: Recreate`** (PVC `ReadWriteOnce`). A API usa a role `l2_app`, nunca o superuser.
6. **Containers**: não-root, `readOnlyRootFilesystem`, `drop: ["ALL"]`, `seccomp: RuntimeDefault` (o namespace aplica PSA `restricted`).
7. **Sem `latest`**; imagens de terceiros por digest.

## Fluxo
Gitflow: `main` (produção/oracle) ← `release/*` ou `develop` ← `feature/*`, `fix/*`, `chore/*`; `hotfix/*` sai da `main`.
PR obrigatório, Conventional Commits, **sem assinatura do Claude em commits e PRs**. Cada PR diz como foi validado.

## Como validar uma mudança
```bash
kubectl kustomize apps/l2/overlays/local | docker run --rm -i ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary -kubernetes-version 1.35.0 -
./scripts/bootstrap-local.sh      # cluster k3d + ArgoCD (idempotente)
kubectl -n argocd get applications
```
Validar em cluster real vale mais que revisar YAML: foi assim que se achou o bug do `Prefix` do Traefik.

## Registro de uso do copiloto
Atualize [`docs/uso-do-claude.md`](docs/uso-do-claude.md) quando houver decisão relevante **ou um erro do Claude que foi corrigido**.
