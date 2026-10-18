# Ambiente Azure

A mesma aplicação e a mesma plataforma do cluster local, numa VM com K3s criada pelo Terraform
(`terraform/`). O ArgoCD da VM sincroniza este repositório; ninguém aplica nada à mão.

```
você ──ssh──► VM (K3s)  ◄── ArgoCD puxa do GitHub (branch develop)
  │             ├─ Traefik :80/:443 ──► l2 (HTTPS Let's Encrypt) ◄── internet
  │             ├─ Grafana / Tempo / Prometheus   (sem Ingress: só por túnel SSH)
  │             └─ API do Kubernetes :6443        (fechada no firewall: só por túnel SSH)
```

## O que é exposto e o que não é

| Porta | Quem acessa | Como |
| --- | --- | --- |
| 80 / 443 | internet | Traefik: aplicação e `/otlp/v1/traces` (o navegador envia spans) |
| 22 | só o seu IP (`ssh_allowed_cidr`) | SSH com chave, sem senha |
| 6443 (API do Kubernetes) | só você | túnel SSH |
| Grafana, ArgoCD, Prometheus, Tempo | só você | `port-forward` dentro da VM + túnel SSH |

## Subir (uma vez)

Pré-requisitos: `terraform apply` feito (`terraform/README.md`), `ssh` e `kubectl` no Git Bash.

```bash
./scripts/bootstrap-azure.sh     # instala o ArgoCD na VM e aplica o app-of-apps
```

O script abre um túnel SSH para a API do Kubernetes e usa um kubeconfig próprio
(`kubeconfig-azure.yaml`, ignorado pelo Git). O seu `~/.kube/config` **não é alterado**: um `kubectl`
comum continua falando com o cluster local.

Depois do bootstrap a plataforma sobe sozinha (cert-manager, Sealed Secrets, Prometheus/Grafana,
Tempo, Collector). A aplicação só fica pronta depois do passo de segredos.

## Segredos (primeiro uso real do Sealed Secrets)

O `l2-secrets` não é criado pelo script: ele vem de um **SealedSecret** commitado, que só o
controller **deste** cluster consegue abrir. O `kubeseal` precisa da chave pública do cluster,
então só dá para selar depois que o controller subir:

```bash
./scripts/azure.sh kubectl                 # terminal 1: abre o túnel e imprime o `export KUBECONFIG=...`
# terminal 2 (cole o export):
kubectl -n kube-system get deploy sealed-secrets-controller          # tem que estar 1/1
scripts/seal-secret.sh l2-secrets l2 JWT_SECRET DB_PASSWORD POSTGRES_PASSWORD \
  > apps/l2/overlays/azure/sealed-secret.yaml                         # pede cada valor, sem eco
```

Depois: acrescente `- sealed-secret.yaml` em `resources:` do `apps/l2/overlays/azure/kustomization.yaml`
e abra um PR normal. **Guarde as senhas escolhidas** (um gerenciador de senhas): o Postgres só aplica
`POSTGRES_PASSWORD` quando o volume está vazio.

Em seguida, **faça o backup da chave do controller** e guarde fora do Git. Se a VM for recriada sem
ele, todo SealedSecret do repositório fica ilegível:

```bash
KUBECONFIG=kubeconfig-azure.yaml scripts/sealed-secrets-key.sh backup ~/sealed-secrets-key-azure.yaml
```

Detalhes e o teste de restauração: [`sealed-secrets.md`](sealed-secrets.md).

## Ver o ambiente na nuvem

A aplicação (pública, HTTPS de verdade):

```
https://<fqdn>        # terraform -chdir=terraform output -raw fqdn
```

Tudo o que não é público passa por `scripts/azure.sh`. Cada comando abre um túnel e fica em primeiro
plano; **Ctrl+C fecha o acesso**.

| Quero ver | Comando | Abrir |
| --- | --- | --- |
| Applications do ArgoCD, pods, HPA, certificado | `./scripts/azure.sh status` | (no terminal) |
| Grafana (dashboards, traces no Tempo, alertas) | `./scripts/azure.sh grafana` | http://localhost:3000 |
| ArgoCD (UI) | `./scripts/azure.sh argocd` | https://localhost:8444 |
| Senhas do Grafana e do ArgoCD | `./scripts/azure.sh senhas` | (no terminal) |
| `kubectl` do seu computador na VM | `./scripts/azure.sh kubectl` | outro terminal: `export KUBECONFIG=...` |
| Shell na VM | `./scripts/azure.sh ssh` | |

No Grafana: **Dashboards → Lumi, Visão geral** para as métricas e **Explore → Tempo** para os traces.
Para ter o que ver, gere carga contra a nuvem, cada clique vira viagem e trace:

```bash
BASE_URL=https://<fqdn> ./scripts/demo-load.sh setup
```

## Custo e desligar

A VM desliga sozinha às 23h. Para parar a cobrança de CPU na hora: `az vm deallocate -g l2-rg -n l2-vm`
(o `shutdown` de dentro da VM **não** para a cobrança). Para religar: `az vm start -g l2-rg -n l2-vm`.
O IP é estático e o DNS não muda. O `terraform destroy` apaga tudo, **inclusive o banco**.

## Imagens: promoção deliberada

O bump automático do pipeline edita só o overlay `local`. O overlay `azure` tem o próprio bloco
`images:`, atualizado à mão (copiando do `local`) depois que a versão provou-se lá: é o embrião do
gate de promoção (task D5). O ArgoCD da VM segue a `develop`.

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `A API do cluster não respondeu pelo túnel` | VM desligada, ou o seu IP mudou | `az vm start ...`; atualize `ssh_allowed_cidr` e rode `terraform apply` |
| API/Postgres em `CreateContainerConfigError` | falta o SealedSecret | passo "Segredos" |
| Certificado `False` / navegador avisa | o desafio HTTP-01 ainda não passou (leva ~1 min) | `kubectl -n l2 describe certificate l2-tls` e `kubectl get challenges -A` |
| `bind: Only one usage of each socket` | porta local ocupada (o túnel anterior ainda vive) | feche o outro terminal, ou `LOCAL_PORT=6444 ./scripts/azure.sh kubectl` |
