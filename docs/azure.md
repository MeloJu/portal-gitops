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

Depois: o `sealed-secret.yaml` já está em `resources:` do `apps/l2/overlays/azure/kustomization.yaml`
(basta refazer o arquivo e abrir um PR normal para trocar os valores). Os valores usados foram
aleatórios e **não precisam ser lembrados**: o controller os grava no Secret `l2-secrets` do
cluster, de onde dá para lê-los. Cuidado só ao **trocar** `POSTGRES_PASSWORD`: o Postgres só aplica
essa senha quando o volume está vazio.

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

## Chave do VirusTotal (opcional)

A tools-api só faz a análise de segurança de links (`POST /tools/scan`) se o `l2-secrets` tiver
`VT_API_KEY`; sem ela responde `503 SCAN_NOT_CONFIGURED` e o resto funciona. Para acrescentar a
chave **sem trocar as outras senhas** (resselar tudo quebraria o Postgres, que já nasceu com elas),
use `--merge-into`, com o túnel aberto (`./scripts/azure.sh kubectl`) e o `KUBECONFIG` exportado:

```bash
kubectl create secret generic l2-secrets -n l2 --from-literal=VT_API_KEY="<a chave>" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
      --format yaml --merge-into apps/l2/overlays/azure/sealed-secret.yaml
```

Depois é um PR normal. A chave real fica só no seu `.env` e no cluster (cifrada no Git).

## Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `A API do cluster não respondeu pelo túnel` | VM desligada, ou o seu IP mudou | `az vm start ...`; atualize `ssh_allowed_cidr` e rode `terraform apply` |
| API/Postgres em `CreateContainerConfigError` | falta o SealedSecret | passo "Segredos" |
| Certificado `False` / navegador avisa | o desafio HTTP-01 ainda não passou (leva ~1 min). Se a razão for `wrong status code '502'`, o Traefik não alcança o pod do desafio: confira a NetworkPolicy `allow-acme-solver` | `kubectl -n l2 describe certificate l2-tls` e `kubectl get challenges -A` |
| `l2-azure` fica `OutOfSync` esperando um PVC, mesmo depois de um commit novo | a operação de sync foi iniciada com uma versão antiga e não troca de commit sozinha | `kubectl -n argocd patch application l2-azure --type merge -p '{"operation":null}'` (só encerra a operação; o auto-sync recomeça) |
| `bind: Only one usage of each socket` | porta local ocupada (o túnel anterior ainda vive) | feche o outro terminal, ou `LOCAL_PORT=6444 ./scripts/azure.sh kubectl` |
