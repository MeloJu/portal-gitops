# Sealed Secrets

Segredo no Git só pode existir **criptografado**. Base64 não é criptografia: um `kind: Secret`
commitado é um segredo vazado. O [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
resolve isso com criptografia assimétrica:

- o **controller** (no cluster) guarda a chave **privada** e é o único que abre o segredo;
- `kubeseal` (na sua máquina) usa a chave **pública** do cluster para gerar um `SealedSecret`;
- o `SealedSecret` vai para o Git; o controller o transforma em `Secret` dentro do cluster.

## Onde cada ambiente usa

| Overlay | Segredo `l2-secrets` | Por quê |
| --- | --- | --- |
| `local` | criado por `scripts/bootstrap-local.sh` (aleatório, fora do Git) | cada dev tem o seu cluster, e um SealedSecret só abre no cluster que o selou |
| `ci` | `Secret` descartável em `overlays/ci/secret.yaml` | cluster efêmero; liberado no gitleaks por caminho |
| `oracle` | **SealedSecret** | é o único ambiente compartilhado e persistente |

O CI recusa `kind: Secret` fora do overlay `ci` (job *Nenhum Secret em claro*).

## Como instalar

Já é automático: `platform/sealed-secrets/application.yaml` é uma Application do ArgoCD (chart
`sealed-secrets` **2.20.0**, controller **0.40.0**, namespace `kube-system`, nome
`sealed-secrets-controller`, os padrões do `kubeseal`). Ela entra no app-of-apps do cluster e sai
na wave `-1`, antes da aplicação.

```bash
kubectl -n kube-system get deploy sealed-secrets-controller
```

Precisa do `kubeseal` na sua máquina (mesma versão do controller):
<https://github.com/bitnami-labs/sealed-secrets/releases/tag/v0.40.0>

## Como selar

Aponte o `kubectl` para o cluster **de destino** (a chave pública é por cluster):

```bash
scripts/seal-secret.sh l2-secrets l2 JWT_SECRET DB_PASSWORD POSTGRES_PASSWORD \
  > apps/l2/overlays/oracle/sealed-secret.yaml
```

Chave sem `=` pede o valor de forma **oculta** (não vai para o histórico do shell). Aceita também
`CHAVE=valor` e `CHAVE=@arquivo`. O Secret em claro nunca é criado no cluster nem gravado em disco
(`--dry-run=client` direto para o `kubeseal`).

Depois: commit do `sealed-secret.yaml`, PR, merge. O ArgoCD aplica e o controller cria o `Secret`.

## O que foi comprovado (cluster k3d, controller 0.40.0)

| Cenário | Resultado |
| --- | --- |
| Selar `SENHA=valor-super-secreto` e procurar o valor no arquivo | **0 ocorrências**: o valor não aparece |
| Aplicar o `SealedSecret` | o controller criou o `Secret` com o valor correto |
| Aplicar o mesmo `SealedSecret` em **outro namespace** | `Synced=False` — *no key could decrypt secret*; nenhum Secret criado |
| Perder a chave (apagar o Secret da chave e o pod do controller) e reaplicar | controller gera chave **nova** e **não** abre mais o `SealedSecret` |
| Restaurar o backup da chave e reiniciar o controller | o `Secret` volta a ser criado com o valor correto |

Conclusões:

1. **O SealedSecret é amarrado ao nome e ao namespace** (escopo *strict*, o padrão). Renomear ou
   mudar de namespace exige selar de novo. É uma proteção, não um defeito: ninguém copia um
   segredo seu para outro lugar.
2. **A chave privada é o ponto único de falha.** Recriar o cluster sem backup torna todos os
   `SealedSecret` do Git ilegíveis.

## Backup da chave (faça antes de confiar no cluster)

```bash
scripts/sealed-secrets-key.sh backup ~/sealed-secrets-key-oracle.yaml   # contexto = cluster oracle
```

O arquivo é a **chave privada**: guarde num cofre ou gerenciador de senhas. **Nunca no Git**
(o `.gitignore` bloqueia `sealed-secrets-key*` e `*-key-backup*.yaml`). Para restaurar num cluster
novo, **antes** de aplicar qualquer SealedSecret:

```bash
scripts/sealed-secrets-key.sh restore ~/sealed-secrets-key-oracle.yaml
```

## Rotação

O controller gera uma chave nova a cada 30 dias e **mantém as antigas** para abrir o que já foi
selado. Isso renova a chave de *selar*, mas não troca o segredo em si: se um valor vazou, **gere
outro valor e sele de novo**. Mantenha os backups de todas as chaves.
