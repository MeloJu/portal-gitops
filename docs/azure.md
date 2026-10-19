# Ambiente Azure

A mesma aplicação e a mesma plataforma do cluster local, numa VM com K3s criada pelo Terraform
(`terraform/`). O ArgoCD da VM sincroniza este repositório; ninguém aplica nada à mão.

```
você ──ssh──► VM (K3s)  ◄── ArgoCD puxa do GitHub (branch develop)
  │             ├─ Traefik :80/:443 ──► l2 (HTTPS Let's Encrypt) ◄── internet
  │             ├─ Grafana em /grafana/ (login)   ◄── navegador (os traces ficam no Tempo, dentro do Grafana)
  │             ├─ Tempo / Prometheus / ArgoCD    (sem Ingress: só por túnel SSH)
  │             └─ API do Kubernetes :6443        (fechada no firewall: só por túnel SSH)
```

## O que é exposto e o que não é

| Porta | Quem acessa | Como |
| --- | --- | --- |
| 80 / 443 | internet | Traefik: aplicação e `/otlp/v1/traces` (o navegador envia spans) |
| 22 | só o seu IP (`ssh_allowed_cidr`) | SSH com chave, sem senha |
| 6443 (API do Kubernetes) | só você | túnel SSH |
| Grafana (`/grafana/`) | quem tiver o login | navegador, por HTTPS (mesmo host e certificado da aplicação). Exposição autorizada pelo dono; o login é obrigatório |
| ArgoCD, Prometheus, Tempo | só você | `port-forward` dentro da VM + túnel SSH |

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
https://lumilinks.duckdns.org    # nome principal (DuckDNS, grátis): os links curtos nascem aqui
https://<fqdn>                   # reserva: terraform -chdir=terraform output -raw fqdn
```

O DuckDNS aponta para o IP fixo da VM (`terraform output public_ip`). Se ele cair, o nome da Azure
continua respondendo, com o mesmo certificado (um certificado só, com os dois nomes). O Grafana só
responde no nome principal.

Tudo o que não é público passa por `scripts/azure.sh`. Cada comando abre um túnel e fica em primeiro
plano; **Ctrl+C fecha o acesso**.

| Quero ver | Comando | Abrir |
| --- | --- | --- |
| Applications do ArgoCD, pods, HPA, certificado | `./scripts/azure.sh status` | (no terminal) |
| Grafana (dashboards, traces no Tempo, alertas) | **sem comando**, direto no navegador (usuário `admin`; a senha: `./scripts/azure.sh senhas`) | `https://lumilinks.duckdns.org/grafana/` (com a barra final) |
| Grafana, se o Ingress estiver fechado | `./scripts/azure.sh grafana` | http://localhost:3000 |
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

## Do commit à nuvem: o Azure segue a `main`

O Azure é a "produção". O ArgoCD da VM lê a **`main`**; o cluster local lê a **`develop`**. Nada vai
para a nuvem por push direto: só por um PR de release.

```
portal-app (develop) ──CI/CD──► PR de bump ──► portal-gitops develop ──► ArgoCD LOCAL (k3d) testa
                                                       │
                       ./scripts/promover-imagens-azure.sh  (copia as imagens do local para o azure)
                                                       ▼
                         PR de release develop ──► main ──► ArgoCD AZURE aplica sozinho (~3 min)
```

| Mudança | Como chega à nuvem |
| --- | --- |
| Manifests (`apps/l2/base`, `platform/`, `overlays/azure`, `bootstrap/apps/azure`) | PR para a `develop` e, quando testado, PR de release `develop` → `main` |
| Imagens novas do `portal-app` | o bump cai na `develop` (local); rode `./scripts/promover-imagens-azure.sh`, abra o PR e faça o release para a `main` |
| Segredos (SealedSecret) | mesmo caminho: PR e release |
| `terraform/` (VM, rede, firewall) | `terraform apply` (o ArgoCD não toca na infraestrutura) |
| O próprio ArgoCD e o `root` | `./scripts/bootstrap-azure.sh` (idempotente) |

`./scripts/promover-imagens-azure.sh --check` diz se o Azure está atrás do local. **Rollback** é um
`git revert` na `main`. O gate de promoção completo (verificar as 3 tags antes do release) é a task D5.

Mudar de `develop` para `main` num cluster que já roda exige reaplicar o `root` uma vez
(`./scripts/bootstrap-azure.sh`), porque a Application `root` é criada à mão.

## Verificação de e-mail (a imagem nova exige)

A partir do `sha-c546009` o `portal-app` só deixa **criar portal com o e-mail verificado**
(`EMAIL_NOT_VERIFIED`). As contas que já existiam foram marcadas como verificadas pela migração V3; só contas
**novas** passam pelo fluxo:

1. Cadastre-se no site. Tentar criar um portal responde `EMAIL_NOT_VERIFIED`.
2. Sem SMTP (`MAIL_ENABLED=false`, o padrão) o "e-mail" é simulado: o link vai para o log da API. Pegue-o com
   `./scripts/azure.sh codigo <email-da-conta>`, que imprime `https://…/verificar-email?token=…`.
3. Abra o link (vale 30 min, uma vez). O portal passa a poder ser criado.

Para mandar e-mail de verdade, configure `MAIL_ENABLED=true`, `MAIL_FROM` e as variáveis `SMTP_*` (as credenciais
entram no `l2-secrets` por SealedSecret, nunca no Git).

## Voltar atrás (rollback)

O Azure segue a `main` e o ArgoCD tem `selfHeal`: o botão *Rollback* da interface do ArgoCD **não resolve**, porque
o ArgoCD reaplica o Git em seguida. O rollback é do Git:

```bash
gh pr create --base main --head <branch-com-o-git-revert> ...   # `git revert -m 1 <merge do release>` na main
```

O Argo aplica a versão anterior em ~3 min (a API reinicia). O **banco não volta junto**: as migrações V3 e V4 são
aditivas (colunas anuláveis ou com valor padrão e tabelas novas), então a imagem antiga continua funcionando com o
schema novo, mas confira. O backup de antes da promoção é o `l2-20261019T141802Z.dump` (ver [`backup.md`](backup.md)).

## O que o `l2-secrets` precisa ter

| Chave | Para quê | Obrigatória |
| --- | --- | --- |
| `DB_PASSWORD`, `POSTGRES_PASSWORD` | senha do banco (a role `l2_app` e o superuser) | sim |
| `JWT_SECRET` | assina a sessão (≥ 256 bits) | sim |
| `APP_CODE_PEPPER` | pepper dos códigos de verificação (≥ 256 bits); as imagens do `portal-app` **não sobem sem ele** | sim, a partir das imagens que o exigem |
| `VT_API_KEY` | análise do VirusTotal | não |

Uma chave nova entra com `kubeseal --merge-into` (sem trocar as outras), como na seção abaixo. Foi assim que o
`APP_CODE_PEPPER` chegou: o `portal-app` passou a exigi-lo e todos os PRs de bump falharam no smoke test até o
`portal-gitops` fornecê-lo, o que é exatamente o que esse check existe para pegar.

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
