# Terraform: o ambiente Azure

Uma VM Ubuntu 24.04 com **K3s** (o mesmo Kubernetes do k3d local, na mesma versão) atrás de um firewall que só
deixa entrar 80 e 443. Pensado para a **assinatura estudantil** (crédito limitado), com desligamento automático.

```
internet --80/443--> IP público estático --> NSG da sub-rede --> VM Standard_B2ms (2 vCPU / 8 GB)
você ------22------> (só do SEU IP) -----------------------------> SSH + túnel para o kubectl
```

| Criado | Detalhe |
| --- | --- |
| Resource group, VNet, sub-rede | `10.20.0.0/16`, isolado |
| IP público **estático** + nome DNS grátis | `l2-xxxxx.<região>.cloudapp.azure.com`, serve de endereço e de nome para o Let's Encrypt (sem comprar domínio) |
| NSG na **sub-rede** | só `80`, `443` e `22` (este, **apenas do seu IP**). A API do Kubernetes (6443), o Actuator, o Prometheus e o Grafana **não** são expostos |
| VM `Standard_B2ms` | login **só por chave SSH**, disco Standard SSD de 64 GB |
| K3s `v1.35.5+k3s1` | instalado por cloud-init; Traefik, metrics-server e local-path vêm junto |
| Desligamento diário às 23h | protege o crédito de uma VM esquecida ligada |

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.9 e a [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
- Uma chave SSH: `ssh-keygen -t ed25519` (a **pública** vai para a VM, a privada nunca sai da sua máquina).

## 1. Antes de aplicar: o que a SUA assinatura permite

A assinatura estudantil limita regiões, tamanhos de VM e vCPUs, e isso **varia de pessoa para pessoa**.
No portal da Azure, abra o **Cloud Shell** (Bash) e rode:

```bash
# regiões permitidas (a policy "Allowed resource deployment regions")
az policy assignment list --query "[?contains(displayName,'region')].{nome:displayName, regioes:parameters.listOfAllowedLocations.value}" -o json

# a B2ms existe e está liberada na região escolhida?
az vm list-skus --location brazilsouth --size Standard_B2 --query "[].{tamanho:name, restricao:restrictions[0].reasonCode}" -o table

# quota de vCPU
az vm list-usage --location brazilsouth --query "[?contains(name.value,'cores') || contains(name.value,'standardB')].{nome:name.localizedValue, usado:currentValue, limite:limit}" -o table
```

Se `brazilsouth` não estiver na lista, use outra região permitida em `location`. Se a B2ms aparecer com
restrição, escolha `vm_size = "Standard_B2als_v2"` **só** se aceitar 4 GB (não recomendado: o projeto usa ~4,1 GB)
ou `Standard_B4als_v2` (4 vCPU / 8 GB, mais cara).

## 2. Aplicar

```bash
az login
az account show --query id -o tsv          # o subscription_id

cd terraform
cp terraform.tfvars.example terraform.tfvars   # NÃO entra no Git; preencha os 4 valores
curl -s https://api.ipify.org                  # o seu IP, para ssh_allowed_cidr = "<ip>/32"

terraform init
terraform plan -out=tfplan                     # leia: deve criar ~11 recursos, nenhum "destroy"
terraform apply tfplan
```

O `apply` leva uns 2 minutos, e o K3s termina de instalar uns 2 a 3 minutos **depois** (cloud-init). Para
acompanhar: `ssh lumi@<fqdn> 'sudo cloud-init status --wait && sudo k3s kubectl get nodes'`.

## 3. Usar o cluster da sua máquina

A porta 6443 não é exposta; o `kubectl` passa por um túnel SSH (os comandos exatos saem em `terraform output`):

```bash
terraform output -raw kubeconfig_comando | bash     # baixa o kubeconfig para kubeconfig-azure.yaml
terraform output -raw kubectl_tunnel | bash &       # túnel local 6443 -> VM
export KUBECONFIG=$PWD/kubeconfig-azure.yaml
kubectl get nodes
```

## Custo e como não gastar o crédito à toa

| O que | Custo |
| --- | --- |
| VM ligada (B2ms, ~US$ 0,08/h, **confira na [calculadora](https://azure.microsoft.com/pricing/calculator/)**) | ~US$ 60 por mês ligada 24 h |
| VM **desligada (deallocate)** | não cobra CPU nem RAM; disco e IP seguem cobrando uns poucos dólares por mês |
| Desligamento automático | todo dia às 23h (`auto_shutdown_time`), a menos que você ponha `auto_shutdown_enabled = false` |

```bash
terraform output -raw parar_vm | bash    # desliga já (deallocate, não é só "stop")
terraform output -raw ligar_vm | bash    # liga; K3s e ArgoCD sobem sozinhos, o IP e o DNS são os mesmos
```

> Parar a VM **pelo sistema** (`shutdown`) não para a cobrança: só o `deallocate` da Azure para.

## Apagar tudo

```bash
terraform destroy      # remove a VM, o disco, o IP e o resource group. O banco vai junto.
```

Faça antes um backup do banco (`docs/backup.md`) se houver algo que importe: o dump fica num volume **da própria
VM**, então também some.

## Decisões de segurança

- **SSH sem valor padrão:** `ssh_allowed_cidr` é obrigatório e **recusa `0.0.0.0/0`** (a validação falha no `plan`).
- **NSG antes da VM:** a NIC depende explicitamente da associação do NSG à sub-rede. Sem isso o Terraform podia
  criar a VM (com IP público) alguns segundos antes de o firewall existir.
- **Sem senha:** `disable_password_authentication = true`.
- **Estado local fora do Git:** `*.tfstate`, `*.tfvars` e `.terraform/` estão no `.gitignore`. O estado pode ter dados
  sensíveis; não suba num bucket público.
- **`lifecycle.ignore_changes` na imagem e no cloud-init:** a tag `latest` da imagem muda com o tempo e o cloud-init só
  roda no primeiro boot; sem isso, um `apply` futuro **recriaria a VM** e apagaria o cluster e o banco.

## O que foi verificado (sem criar nada na Azure)

| Verificação | Resultado |
| --- | --- |
| `terraform fmt -check` / `validate` | limpos |
| Validação das variáveis | recusa SSH aberto ao mundo, CIDR inválido, "chave" que não é pública e horário inválido |
| cloud-init renderizado | sem placeholder esquecido, YAML válido e aprovado pelo `cloud-init schema` oficial |
| Trivy (IaC) | limpo; com o SSH aberto ao mundo ele **falha** (o gate funciona) |
| Grafo de dependências | VM → NIC → NSG da sub-rede |

**Ainda não verificado:** o `plan` e o `apply` contra uma conta real (exigem as suas credenciais), e a instalação do
K3s numa VM de verdade. É o que o primeiro `apply` vai provar.

## Solução de problemas

| Sintoma | Causa provável |
| --- | --- |
| `RequestDisallowedByPolicy` | a região não está na policy da sua assinatura; mude `location` |
| `SkuNotAvailable` / `QuotaExceeded` | tamanho indisponível na região ou sem vCPU de quota; veja o passo 1 |
| `MissingSubscriptionRegistration` | provedor de recurso não registrado: `az provider register --namespace Microsoft.Compute` (e `Microsoft.Network`, `Microsoft.DevTestLab`) |
| Não consigo entrar por SSH | o seu IP mudou (IP residencial): atualize `ssh_allowed_cidr` e rode `terraform apply` |
| `azurerm` 5.x | o projeto fixa a 4.x (`~> 4.81`); a 5.x muda o schema e deve ser migrada à parte |

## Próximos passos (fora deste PR)

1. Overlay `azure` do ArgoCD (host = o `fqdn`, `SESSION_COOKIE_SECURE=true`) e um `ClusterIssuer` do Let's Encrypt.
2. `scripts/bootstrap-azure.sh`: instala o ArgoCD e aplica o app-of-apps na VM.
3. SealedSecret do `l2-secrets` para este cluster (e backup da chave, `docs/sealed-secrets.md`).
